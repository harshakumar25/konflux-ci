# Slack Message for Maintainers

Hey @yftacherzog @ralfjbrown 👋

Quick update on the 14GB macOS RAM issue (#5194) — I've prototyped k3d as an alternative to Kind and the numbers look promising:

**Memory footprint:**
• Idle: ~535 MiB (vs ~2-3GB Kind)
• Full Konflux deps: ~3GB (vs ~12-13GB Kind)
• Headroom on 14GB runner: ~11GB free ✅

**Your two concerns:**
1. Environment changes only — zero Konflux code/manifest changes. All 31 deployments came up clean.
2. Uses `--cluster-init` (embedded etcd), not SQLite. Same datastore as Kind.

**What changed:**
Added: `setup-k3d-cluster.sh`, `k3d-config.yaml`, docs
Modified: `deploy-local.sh` (+15 lines for `CLUSTER_PROVIDER=kind|k3d` opt-in)
Unchanged: Kind scripts, workflows — all still default to Kind

**Trade-off to flag:**
Even with k3d, 14GB is still a ceiling. We get ~11GB headroom today, but that shrinks as we add more E2E components. At some point we might need larger runners ($$$).

Shellcheck passed, everything's documented. If this looks interesting, happy to open an issue + PR with the full proposal.

Branch: https://github.com/harshakumar25/konflux-ci/tree/k3d-macos-prototype

Let me know if you want me to dig deeper or if this is helpful as-is!
