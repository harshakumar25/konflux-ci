# k3d Prototype Results - macOS 14GB RAM Issue

Hi @yftacherzog @ralfjbrown,

Following up on the 14GB RAM discussion from #5194 — I've put together a k3d prototype and wanted to share the results.

## Quick Answers to Your Questions

**1. Would it require changes in the way we set up the environment, or also changes in Konflux?**
- Environment setup only. No Konflux code or manifest changes needed.
- `deploy-deps.sh` exited cleanly: 31/31 deployments Available, 30/30 pods Running.

**2. SQLite concern:**
- Our config uses `--cluster-init` (embedded etcd), same datastore as Kind.
- Node shows `ROLES: control-plane,etcd,master` — confirms etcd, not SQLite.

## Benchmark (macOS + Docker Desktop)

| Metric | Kind | k3d |
|--------|------|-----|
| Idle cluster | ~2-3 GB | **~535 MiB** |
| Full Konflux deps | ~12-13 GB | **~3 GB** |
| Headroom on 14GB runner | <1 GB (fails) | **~11 GB** ✅ |

This gives us breathing room for macOS E2E tests that currently fail.

## What Changed

**Added (new files):**
- `setup-k3d-cluster.sh` — drop-in parallel to setup-kind-local-cluster.sh
- `k3d-config.yaml` — uses `--cluster-init` for embedded etcd
- `docs/k3d-macos.md` — documentation

**Modified (minimal, backward-compatible):**
- `deploy-local.sh` (+15 lines) — adds `CLUSTER_PROVIDER=kind|k3d` opt-in
- `deploy-local.env.template` (+8 lines) — documents the variable

**Unchanged:**
- `setup-kind-local-cluster.sh` — untouched
- `kind-config.yaml` — untouched
- All `.github/workflows/` — untouched
- Default behavior: `./scripts/deploy-local.sh` still runs Kind

## One Caveat

Even with k3d, the 14GB limit is a ceiling. Today we have ~11GB headroom, but as we add more components to the E2E suite, that shrinks. Eventually we might need larger runners (~$0.16/min for 32GB macOS). Something to keep on the radar.

## Next Steps

If this looks useful, I'm happy to:
1. Create a proper issue with the full proposal
2. Open a PR with the prototype changes
3. Run a deeper comparison (onboard app → build → release flow)

No rush — just wanted to get the data in front of you. Let me know what you think!

---
**Prototype branch:** https://github.com/harshakumar25/konflux-ci/tree/k3d-macos-prototype  
**Shellcheck:** Passed ✓
