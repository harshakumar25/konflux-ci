#!/bin/bash -eu
#
# Memory Benchmark Utility for Konflux CI
#
# Captures memory usage at a given stage for benchmarking.
# Designed to work on both macOS (Colima + Docker) and Linux.
#
# Usage: benchmark-memory.sh <stage-label>
#
# Output: Prints a formatted memory report to stdout.
# In CI, pipe to a file: benchmark-memory.sh "post-deploy" | tee logs/memory-post-deploy.log

STAGE="${1:-unknown}"
TIMESTAMP="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

echo "============================================"
echo "Stage: ${STAGE}"
echo "Timestamp: ${TIMESTAMP}"
echo "============================================"
echo ""

# ── Docker container memory ─────────────────────────────────────────
echo "--- Docker Container Memory ---"
if command -v docker &> /dev/null && docker info &> /dev/null; then
    docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}\t{{.CPUPerc}}\t{{.MemPerc}}" 2>/dev/null || echo "  (docker stats unavailable)"
    echo ""

    # Total container memory
    TOTAL_MEM=$(docker stats --no-stream --format "{{.MemUsage}}" 2>/dev/null | \
        awk -F'/' '{gsub(/[A-Za-z ]/,"",$1); sum+=$1} END {printf "%.0f", sum}' 2>/dev/null || echo "0")
    echo "Docker total container memory: ~${TOTAL_MEM}MiB"
else
    echo "  Docker not available"
fi
echo ""

# ── Host memory ─────────────────────────────────────────────────────
echo "--- Host Memory ---"
if [[ "$(uname)" == "Darwin" ]]; then
    TOTAL_RAM=$(sysctl -n hw.memsize 2>/dev/null | awk '{printf "%.1f", $1/1024/1024/1024}')
    echo "Total RAM: ${TOTAL_RAM} GB"

    # Parse vm_stat for memory breakdown
    if command -v vm_stat &> /dev/null; then
        VM_STAT=$(vm_stat 2>/dev/null)
        PAGE_SIZE=$(echo "$VM_STAT" | head -1 | grep -o '[0-9]*' | tail -1)
        FREE=$(echo "$VM_STAT" | grep "Pages free" | awk '{print $3}' | tr -d '.')
        ACTIVE=$(echo "$VM_STAT" | grep "Pages active" | awk '{print $3}' | tr -d '.')
        INACTIVE=$(echo "$VM_STAT" | grep "Pages inactive" | awk '{print $3}' | tr -d '.')
        WIRED=$(echo "$VM_STAT" | grep "Pages wired" | awk '{print $4}' | tr -d '.')
        COMPRESSED=$(echo "$VM_STAT" | grep "Pages occupied by compressor" | awk '{print $5}' | tr -d '.')

        if [[ -n "$PAGE_SIZE" ]] && [[ -n "$FREE" ]]; then
            FREE_MB=$(( FREE * PAGE_SIZE / 1024 / 1024 ))
            ACTIVE_MB=$(( ACTIVE * PAGE_SIZE / 1024 / 1024 ))
            INACTIVE_MB=$(( INACTIVE * PAGE_SIZE / 1024 / 1024 ))
            WIRED_MB=$(( WIRED * PAGE_SIZE / 1024 / 1024 ))
            COMPRESSED_MB=$(( ${COMPRESSED:-0} * PAGE_SIZE / 1024 / 1024 ))
            USED_MB=$(( ACTIVE_MB + WIRED_MB + COMPRESSED_MB ))

            echo "  Free:       ${FREE_MB} MiB"
            echo "  Active:     ${ACTIVE_MB} MiB"
            echo "  Inactive:   ${INACTIVE_MB} MiB"
            echo "  Wired:      ${WIRED_MB} MiB"
            echo "  Compressed: ${COMPRESSED_MB} MiB"
            echo "  Used:       ~${USED_MB} MiB"
        fi
    fi
else
    free -h 2>/dev/null || echo "  (free command unavailable)"
fi
echo ""

# ── Colima VM stats (macOS only) ────────────────────────────────────
if [[ "$(uname)" == "Darwin" ]] && command -v colima &> /dev/null; then
    echo "--- Colima VM Status ---"
    colima status 2>/dev/null || echo "  Colima not running"
    echo ""
fi

# ── Kubernetes resource usage ───────────────────────────────────────
echo "--- Kubernetes Node Resources ---"
if command -v kubectl &> /dev/null; then
    kubectl top nodes 2>/dev/null || echo "  (metrics-server not available — using describe)"
    echo ""

    # Pod count summary
    echo "--- Pod Count by Status ---"
    kubectl get pods -A --no-headers 2>/dev/null | awk '{print $4}' | sort | uniq -c | sort -rn || echo "  No pods"
    echo ""

    # Total pod count
    TOTAL_PODS=$(kubectl get pods -A --no-headers 2>/dev/null | wc -l | tr -d ' ')
    echo "Total pods: ${TOTAL_PODS}"

    # PipelineRun count (for arewm's memory concern)
    echo ""
    echo "--- PipelineRun Count ---"
    PR_COUNT=$(kubectl get pipelineruns -A --no-headers 2>/dev/null | wc -l | tr -d ' ')
    echo "Active PipelineRuns: ${PR_COUNT}"

    TR_COUNT=$(kubectl get taskruns -A --no-headers 2>/dev/null | wc -l | tr -d ' ')
    echo "Active TaskRuns: ${TR_COUNT}"
else
    echo "  kubectl not available"
fi
echo ""

echo "============================================"
echo "End of benchmark: ${STAGE}"
echo "============================================"
