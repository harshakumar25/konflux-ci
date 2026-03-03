#!/bin/bash -eu

# Setup k3d Local Cluster for Konflux
#
# This script sets up a local k3d (K3s in Docker) cluster as a memory-efficient
# alternative to Kind, especially suited for macOS development and CI.
#
# k3d advantages over Kind on macOS:
#   - Idle cluster uses ~360MB RAM (vs ~2-3GB for Kind) when using embedded etcd
#   - K3s uses embedded etcd (via --cluster-init) — same as Vanilla Kubernetes/Kind
#   - Tekton and Konflux are fully compatible with K3s (CNCF-certified conformant)
#   - Zero changes to Konflux code required: only setup scripts differ
#
# Datastore choice:
#   By default K3s would use SQLite. This script explicitly uses k3d-config.yaml
#   which passes --cluster-init to enable EMBEDDED ETCD, the same datastore used
#   by standard Kubernetes and Kind. This preserves correctness parity while
#   saving ~1.5-2 GB of RAM vs a full Kind node.
#
# This script is for LOCAL DEVELOPMENT / CI CONVENIENCE ONLY. The Konflux operator
# and its components work on ANY Kubernetes cluster.
#
# Prerequisites:
#   - k3d (https://k3d.io — install: brew install k3d)
#   - docker or colima (as the container runtime for k3d)
#   - kubectl
#
# Configuration:
# Set these environment variables:
#   - KIND_CLUSTER:         Cluster name (default: konflux — reuses Kind var for compat)
#   - REGISTRY_HOST_PORT:   Host port for registry (default: 5001)
#   - ENABLE_REGISTRY_PORT: Enable registry port binding (default: 1)
#
# Note: The cluster config (k3d-config.yaml) passes --cluster-init to K3s which
# enables embedded etcd instead of the default SQLite datastore.

# Determine the absolute path of the repository root
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
REPO_ROOT=$(dirname "$SCRIPT_DIR")

# Set defaults
K3D_CLUSTER="${KIND_CLUSTER:-konflux}"
REGISTRY_HOST_PORT="${REGISTRY_HOST_PORT:-5001}"
ENABLE_REGISTRY_PORT="${ENABLE_REGISTRY_PORT:-1}"

# ─────────────────────────────────────────────────────────────────────────────
# Prerequisite checks
# ─────────────────────────────────────────────────────────────────────────────

echo "🔍 Checking prerequisites for k3d cluster setup..."

# k3d
if ! command -v k3d &> /dev/null; then
    echo "ERROR: k3d is not installed."
    echo ""
    echo "Install it with one of:"
    echo "  brew install k3d                        (macOS Homebrew)"
    echo "  curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash   (Linux/macOS)"
    echo ""
    echo "See https://k3d.io for more options."
    exit 1
fi
echo "  ✓ k3d $(k3d version | head -1)"

# Docker or Colima (k3d uses Docker API)
if ! command -v docker &> /dev/null; then
    echo "ERROR: docker is not installed or not in PATH."
    echo ""
    echo "k3d requires Docker (or a Docker-compatible runtime such as Colima)."
    echo "Install options:"
    echo "  brew install --cask docker               (Docker Desktop)"
    echo "  brew install colima && colima start      (Colima — lightweight VM-based)"
    exit 1
fi
if ! docker info &> /dev/null; then
    echo "ERROR: Docker daemon is not running."
    echo ""
    echo "Start it with:"
    echo "  open -a Docker                           (Docker Desktop on macOS)"
    echo "  colima start                             (Colima)"
    exit 1
fi
echo "  ✓ docker $(docker version --format '{{.Client.Version}}' 2>/dev/null || echo '(version unavailable)')"

# kubectl
if ! command -v kubectl &> /dev/null; then
    echo "ERROR: kubectl is not installed."
    echo "Install: brew install kubectl"
    exit 1
fi
echo "  ✓ kubectl $(kubectl version --client --short 2>/dev/null | head -1 || kubectl version --client 2>/dev/null | grep 'Client Version' | head -1)"

echo "  All prerequisites met."
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Memory validation (macOS: Docker VM; Linux: /proc/meminfo)
# ─────────────────────────────────────────────────────────────────────────────

MIN_REQUIRED_MB=6144   # 6 GB minimum for Konflux core components

check_available_memory() {
    local available_mb=0

    if [[ "$(uname)" == "Darwin" ]]; then
        # On macOS, k3d runs inside Docker's VM. Try to read the VM memory limit.
        local docker_mem
        docker_mem=$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo "0")
        # docker_mem is in bytes; convert to MB
        if [[ "$docker_mem" =~ ^[0-9]+$ ]] && [[ "$docker_mem" -gt 0 ]]; then
            available_mb=$(( docker_mem / 1024 / 1024 ))
        fi

        if [[ "$available_mb" -lt "$MIN_REQUIRED_MB" ]]; then
            echo "⚠️  WARNING: Docker VM has ${available_mb}MB memory."
            echo "   Konflux recommends at least ${MIN_REQUIRED_MB}MB (6GB)."
            echo ""
            echo "   To increase Docker Desktop VM memory:"
            echo "     Docker Desktop → Settings → Resources → Memory"
            echo ""
            echo "   To increase Colima VM memory:"
            echo "     colima stop && colima start --memory 8"
            echo ""
            echo "   Proceeding, but deployment may fail or be slow."
            echo ""
        else
            echo "✓ Docker VM memory: ${available_mb}MB (>= ${MIN_REQUIRED_MB}MB required)"
        fi
    elif [[ "$(uname)" == "Linux" ]]; then
        local mem_total
        mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        available_mb=$(( mem_total / 1024 ))
        if [[ "$available_mb" -lt "$MIN_REQUIRED_MB" ]]; then
            echo "⚠️  WARNING: System has ${available_mb}MB memory (< ${MIN_REQUIRED_MB}MB recommended for Konflux)."
        else
            echo "✓ System memory: ${available_mb}MB (>= ${MIN_REQUIRED_MB}MB required)"
        fi
    fi
}

check_available_memory

# ─────────────────────────────────────────────────────────────────────────────
# Existing cluster check
# ─────────────────────────────────────────────────────────────────────────────

if k3d cluster list --no-headers 2>/dev/null | awk '{print $1}' | grep -q "^${K3D_CLUSTER}$"; then
    # Cluster exists — check if it's reachable
    if kubectl --context "k3d-${K3D_CLUSTER}" cluster-info &> /dev/null; then
        echo "k3d cluster '${K3D_CLUSTER}' already exists and is usable."
        echo "Skipping cluster creation. Delete it first if you want to recreate:"
        echo "  k3d cluster delete ${K3D_CLUSTER}"
        exit 0
    else
        echo "k3d cluster '${K3D_CLUSTER}' exists but is not responding. Deleting and recreating..."
        k3d cluster delete "${K3D_CLUSTER}"
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Port availability check
# ─────────────────────────────────────────────────────────────────────────────

check_port() {
    local port="$1"
    local label="$2"

    if command -v lsof &> /dev/null; then
        if lsof -i ":${port}" > /dev/null 2>&1; then
            echo "ERROR: Port ${port} (${label}) is already in use."
            lsof -i ":${port}"
            return 1
        fi
    elif command -v ss &> /dev/null; then
        if ss -ltn "sport = :${port}" | grep -q ":${port}"; then
            echo "ERROR: Port ${port} (${label}) is already in use."
            return 1
        fi
    elif command -v netstat &> /dev/null; then
        if netstat -an | grep -q "[:.]${port}.*LISTEN"; then
            echo "ERROR: Port ${port} (${label}) is already in use."
            return 1
        fi
    else
        echo "WARNING: Cannot check port ${port} availability (lsof/ss/netstat not found). Proceeding."
        return 0
    fi
    return 0
}

echo "Checking required host ports..."
PORT_ERROR=0
check_port 8888 "Konflux UI"       || PORT_ERROR=1
check_port 9443 "PaC"              || PORT_ERROR=1
check_port 8180 "Dex"              || PORT_ERROR=1

if [[ "${ENABLE_REGISTRY_PORT}" -eq 1 ]]; then
    check_port "${REGISTRY_HOST_PORT}" "Registry" || PORT_ERROR=1
fi

if [[ "${PORT_ERROR}" -eq 1 ]]; then
    echo ""
    echo "One or more required ports are in use. Resolve the conflicts above and retry."
    echo ""
    echo "On macOS, port 5000 is often used by AirPlay Receiver."
    echo "Disable it: System Settings → General → AirDrop & Handoff → AirPlay Receiver"
    echo ""
    echo "Or change REGISTRY_HOST_PORT in scripts/deploy-local.env"
    exit 1
fi
echo "  All required ports are available."
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Build k3d config (handle non-default registry port)
# ─────────────────────────────────────────────────────────────────────────────

K3D_CONFIG="${REPO_ROOT}/k3d-config.yaml"
K3D_CONFIG_EFFECTIVE="${K3D_CONFIG}"

# If registry port or cluster name differs from defaults, generate a temp config
if [[ "${REGISTRY_HOST_PORT}" != "5001" ]] || [[ "${K3D_CLUSTER}" != "konflux" ]] || [[ "${ENABLE_REGISTRY_PORT}" -eq 0 ]]; then
    K3D_CONFIG_EFFECTIVE="$(mktemp /tmp/k3d-config-XXXXXX.yaml)"
    # shellcheck disable=SC2064
    trap "rm -f '${K3D_CONFIG_EFFECTIVE}'" EXIT

    # Start from the base config and patch dynamically
    sed \
        -e "s/name: konflux/name: ${K3D_CLUSTER}/" \
        -e "s|\"5001:30001\"|\"${REGISTRY_HOST_PORT}:30001\"|" \
        "${K3D_CONFIG}" > "${K3D_CONFIG_EFFECTIVE}"

    # Remove registry port block entirely if disabled
    if [[ "${ENABLE_REGISTRY_PORT}" -eq 0 ]]; then
        # Remove the registry port entry (uses a 3-line block pattern)
        sed -i.bak "/# Internal container registry/,+3d" "${K3D_CONFIG_EFFECTIVE}" && \
            rm -f "${K3D_CONFIG_EFFECTIVE}.bak"
        echo "Registry port binding disabled."
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Create k3d cluster
# ─────────────────────────────────────────────────────────────────────────────

echo "Creating k3d cluster '${K3D_CLUSTER}'..."
k3d cluster create "${K3D_CLUSTER}" --config "${K3D_CONFIG_EFFECTIVE}"

# Merge new kubeconfig into default context (k3d does this automatically,
# but make the new context active explicitly)
kubectl config use-context "k3d-${K3D_CLUSTER}"

echo ""
echo "✓ k3d cluster '${K3D_CLUSTER}' created successfully"
echo ""
echo "Cluster info:"
kubectl cluster-info --context "k3d-${K3D_CLUSTER}" 2>/dev/null || true
echo ""
echo "Memory snapshot (for baseline benchmarking):"
docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}" \
    "k3d-${K3D_CLUSTER}-server-0" 2>/dev/null || \
    echo "  (run 'docker stats --no-stream' to see container memory usage)"
echo ""
echo "Next steps:"
echo "  1. Deploy dependencies: ./deploy-deps.sh"
echo "  2. Deploy operator: cd operator && make deploy"
echo "  3. Apply Konflux CR: kubectl apply -f my-konflux.yaml"
echo ""
echo "Or use the all-in-one script: CLUSTER_PROVIDER=k3d ./scripts/deploy-local.sh"
