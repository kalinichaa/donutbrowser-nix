# Repository Guidelines

## Project Structure & Module Organization
This repository is a source-build Nix flake for Donut Browser on Linux. `flake.nix` exposes package, app, overlay, check, and dev-shell outputs. `package.nix` contains the source derivation, sidecar staging, frontend build, and Tauri bundle install logic. Update automation lives in `scripts/update-version.sh` and `.github/workflows/`.

## Build, Test, and Development Commands
Use Nix-native commands from the repository root:

- `nix build .#donutbrowser --print-build-logs` builds the package exactly as CI does.
- `nix run .#donutbrowser` launches the packaged app.
- `nix flake check` validates the flake outputs for the current system.
- `./scripts/update-version.sh --check` checks whether a newer upstream release exists.
- `./scripts/update-version.sh --version 0.19.0` pins to a specific upstream release.

## Coding Style & Naming Conventions
Match existing file style. Nix uses two-space indentation and explicit semicolons. Bash scripts keep `#!/usr/bin/env bash`, `set -euo pipefail`, `snake_case` function names, and `readonly` constants for shared values. Keep packaging changes narrow and make updater logic easy to review.

## Testing Guidelines
There is no unit test suite. Validation is:

- `nix build .#donutbrowser --print-build-logs`
- `nix flake check`

If you change the updater, also run:

- `./scripts/update-version.sh --check`

## Commit & Pull Request Guidelines
Follow the existing automated update style:

- `chore: update donutbrowser to version 0.19.0`

For manual changes, use `fix:` or `chore:` with an imperative summary. If you open a PR manually, state what changed, why, and how it was validated. The hourly updater in this repo pushes version bumps directly to `main`.

## Security & Configuration Tips
Do not commit secrets. `CACHIX_AUTH_TOKEN` belongs in GitHub Actions secrets only. The `aarch64-linux` build job assumes a native ARM builder or self-hosted ARM64 runner is available before enabling full multi-arch cache publication.

<!-- gitnexus:start -->
# GitNexus — Code Intelligence

This project is indexed by GitNexus as **donutbrowser-nix** (176 symbols, 232 relationships, 7 execution flows). Use the GitNexus MCP tools to understand code, assess impact, and navigate safely.

> If any GitNexus tool warns the index is stale, run `gitnexus analyze` in terminal first.

## Always Do

- **MUST run impact analysis before editing any symbol.** Before modifying a function, class, or method, run `gitnexus_impact({target: "symbolName", direction: "upstream"})` and report the blast radius (direct callers, affected processes, risk level) to the user.
- **MUST run `gitnexus_detect_changes()` before committing** to verify your changes only affect expected symbols and execution flows.
- **MUST warn the user** if impact analysis returns HIGH or CRITICAL risk before proceeding with edits.
- When exploring unfamiliar code, use `gitnexus_query({query: "concept"})` to find execution flows instead of grepping. It returns process-grouped results ranked by relevance.
- When you need full context on a specific symbol — callers, callees, which execution flows it participates in — use `gitnexus_context({name: "symbolName"})`.

## Never Do

- NEVER edit a function, class, or method without first running `gitnexus_impact` on it.
- NEVER ignore HIGH or CRITICAL risk warnings from impact analysis.
- NEVER rename symbols with find-and-replace — use `gitnexus_rename` which understands the call graph.
- NEVER commit changes without running `gitnexus_detect_changes()` to check affected scope.

## Resources

| Resource | Use for |
|----------|---------|
| `gitnexus://repo/donutbrowser-nix/context` | Codebase overview, check index freshness |
| `gitnexus://repo/donutbrowser-nix/clusters` | All functional areas |
| `gitnexus://repo/donutbrowser-nix/processes` | All execution flows |
| `gitnexus://repo/donutbrowser-nix/process/{name}` | Step-by-step execution trace |

## CLI

| Task | Read this skill file |
|------|---------------------|
| Understand architecture / "How does X work?" | `.claude/skills/gitnexus/gitnexus-exploring/SKILL.md` |
| Blast radius / "What breaks if I change X?" | `.claude/skills/gitnexus/gitnexus-impact-analysis/SKILL.md` |
| Trace bugs / "Why is X failing?" | `.claude/skills/gitnexus/gitnexus-debugging/SKILL.md` |
| Rename / extract / split / refactor | `.claude/skills/gitnexus/gitnexus-refactoring/SKILL.md` |
| Tools, resources, schema reference | `.claude/skills/gitnexus/gitnexus-guide/SKILL.md` |
| Index, status, clean, wiki CLI commands | `.claude/skills/gitnexus/gitnexus-cli/SKILL.md` |

<!-- gitnexus:end -->
