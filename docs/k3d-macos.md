# Running Konflux on macOS with k3d

> **Status: Prototype / Proof-of-Concept** — opt-in only (`CLUSTER_PROVIDER=k3d`).
> Kind remains the **default** for all existing workflows and Linux CI.

## Why k3d on macOS?

Standard macOS GitHub runners are capped at **14 GB RAM**. Deploying the full
Konflux stack on Kind pushes past that limit. k3d wraps **K3s** (a CNCF-certified,
conformant Kubernetes distribution) inside Docker containers:

| | Kind (Linux CI) | k3d / K3s (macOS opt-in) |
|---|---|---|
| Idle cluster RAM | ~2–3 GB | ~500 MB |
| Datastore | etcd | **embedded etcd** (`--cluster-init`) |
| Tekton compatible | ✅ | ✅ |
| Conformant K8s | ✅ | ✅ (CNCF certified) |

> [!IMPORTANT]
> **We use embedded etcd (not SQLite).**
> K3s defaults to SQLite for single-node clusters, but this prototype explicitly
> passes `--cluster-init` to enable K3s's embedded etcd — the same datastore used
> by standard Kubernetes and Kind. This preserves datastore parity and avoids
> the SQLite single-node constraint.

## Prerequisites

```bash
# macOS (Homebrew)
brew install k3d

# Docker runtime — choose one:
open -a Docker                             # Docker Desktop
# or
brew install colima && colima start --memory 8 --cpu 4   # Colima
```

## Usage

```bash
# Copy and edit your env file
cp scripts/deploy-local.env.template scripts/deploy-local.env
# Edit deploy-local.env: set CLUSTER_PROVIDER=k3d, GITHUB_APP_ID, etc.

# Deploy Konflux with k3d
CLUSTER_PROVIDER=k3d ./scripts/deploy-local.sh
```

Or, to create only the cluster:

```bash
KIND_CLUSTER=konflux ./scripts/setup-k3d-cluster.sh
```

## How It Works

`setup-k3d-cluster.sh` is a drop-in parallel to `setup-kind-local-cluster.sh`.
It reads `k3d-config.yaml` and creates a single-node K3s cluster using k3d.
The same host ports are exposed:

| Service | Host Port |
|---|---|
| Konflux UI | `8888` |
| Pipelines-as-Code | `9443` |
| Dex OIDC | `8180` |
| Internal Registry | `5001` |

## What Changed vs the Existing Kind Setup

### Files added (new, do not touch Kind path)
- `k3d-config.yaml` — cluster config mirroring `kind-config.yaml`
- `scripts/setup-k3d-cluster.sh` — parallel setup script using k3d

### Files modified (minimal, backward-compatible)
- `scripts/deploy-local.sh` — added `CLUSTER_PROVIDER=kind|k3d` branching (+15 lines)
- `scripts/deploy-local.env.template` — documents `CLUSTER_PROVIDER` variable (+8 lines)

**Untouched**: `scripts/setup-kind-local-cluster.sh`, `kind-config.yaml`,
all `.github/workflows/` files. Running `./scripts/deploy-local.sh` with no
env-var still uses Kind — bit-for-bit identical to before.

## Key Differences Between Kind and k3d Commands

| Operation | Kind | k3d |
|---|---|---|
| Create cluster | `kind create cluster` | `k3d cluster create` |
| Delete cluster | `kind delete cluster` | `k3d cluster delete` |
| Load image | `kind load docker-image` | `k3d image import` |
| List clusters | `kind get clusters` | `k3d cluster list` |
| kubectl context | `kind-<name>` | `k3d-<name>` |

## Benchmark Results (Prototype Run on macOS)

| Metric | Result |
|---|---|
| Cluster creation time | ~28 s |
| Idle RAM (server container) | **354 MiB** |
| Full Konflux deps RAM (post deploy-deps.sh) | **~3 GB** |
| Headroom on 14 GB macOS runner | **~11 GB free** |
| Pods Running | **30 / 30** |
| Failures | **0** |
| Konflux code/manifest changes needed | **None** |

Components verified working: Tekton Operator, Pipelines, Chains, Triggers, Results,
Pipelines-as-Code, cert-manager, trust-manager, Kyverno (4 controllers), Dex, Registry, Smee.

## Troubleshooting

**Cluster context not found:**
k3d names the kubectl context `k3d-<cluster-name>`.
Run `kubectl config get-contexts` to confirm.

**Not enough memory:**
```bash
colima stop && colima start --memory 10 --cpu 6
# or Docker Desktop → Settings → Resources → Memory
```

**Port already in use:**
Change `REGISTRY_HOST_PORT` in `scripts/deploy-local.env`, or set `ENABLE_REGISTRY_PORT=0`.
On macOS, port 5000 is often taken by AirPlay Receiver.
Disable: **System Settings → General → AirDrop & Handoff → AirPlay Receiver → Off**
