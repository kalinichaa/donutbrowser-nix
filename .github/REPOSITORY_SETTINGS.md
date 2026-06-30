# Repository Settings Configuration

This repository uses hourly automation to keep Donut Browser up to date.

## Required GitHub Settings

### 1) Workflow Permissions

1. Go to **Settings** -> **Actions** -> **General**.
2. Under **Workflow permissions**, set:
   - **Read and write permissions**
3. Enable **Allow GitHub Actions to create and approve pull requests**. The
   updater's recovery path opens a PR when carried patches need refreshing, and
   this fails without it.
4. Save.

### 2) ARM Builder

Automatic CI builds and caches only `x86_64-linux`.

The `aarch64-linux` build is manual-only until one of these exists:

- a self-hosted GitHub Actions runner labeled `self-hosted`, `Linux`, `ARM64`
- a native ARM build runner you map to the same labels

If you use the manual ARM workflow with `actions/checkout@v5`, keep the self-hosted
runner updated to a recent GitHub Actions runner release that supports Node 24-era
JavaScript actions.

### 3) Updater Behavior

The hourly updater never fails silently. It handles three cases:

- **Clean update**: the version bump is built, pushed to Cachix, and committed
  directly to `main`.
- **Carried patches no longer apply**: the workflow auto-runs
  `scripts/refresh-patches.sh`, re-verifies the full `nix build`, pushes to
  Cachix, and opens a pull request. Review the refreshed patch hunks before
  merging — a 3-way merge can apply cleanly yet shift intent.
- **Refresh fails, or a non-patch block** (build / playwright-driver /
  source-layout): the workflow opens or updates a single tracking issue
  describing what needs manual intervention. No silent green skip.

The pinned packaged version stays unchanged until either the auto-opened PR is
merged or the tracking issue is resolved manually.

## Required Secrets

Add these in **Settings** -> **Secrets and variables** -> **Actions**.

- `CACHIX_AUTH_TOKEN`: Cachix auth token with push access to `hassiyyt`

`GITHUB_TOKEN` is provided automatically by GitHub Actions.

## Cachix Details

- Cache: `hassiyyt`
- Substituter: `https://hassiyyt.cachix.org`
- Public key: `hassiyyt.cachix.org-1:GPb2J+eS5AyHtVF9zQ+cchuQJl65WrxpcrdYsSiDjno=`
