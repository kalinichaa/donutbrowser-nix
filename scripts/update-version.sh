#!/usr/bin/env bash
set -euo pipefail

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

readonly GITHUB_REPO="zhom/donutbrowser"
readonly GITHUB_API_BASE="https://api.github.com/repos/${GITHUB_REPO}/releases"
readonly FAKE_HASH="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
readonly UPDATE_BLOCKED_EXIT_CODE=2

PACKAGE_BACKUP=""
RESTORE_PACKAGE_ON_EXIT=false

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

restore_package_backup() {
  if [ "$RESTORE_PACKAGE_ON_EXIT" = true ] && [ -n "$PACKAGE_BACKUP" ] && [ -f "$PACKAGE_BACKUP" ]; then
    cp "$PACKAGE_BACKUP" package.nix
  fi
  if [ -n "$PACKAGE_BACKUP" ] && [ -f "$PACKAGE_BACKUP" ]; then
    rm -f "$PACKAGE_BACKUP"
  fi
  RESTORE_PACKAGE_ON_EXIT=false
}

restore_package_backup_on_exit() {
  restore_package_backup
}

ensure_in_repository_root() {
  if [ ! -f "flake.nix" ] || [ ! -f "package.nix" ]; then
    log_error "flake.nix or package.nix not found. Run this script from the repository root."
    exit 1
  fi
}

ensure_required_tools_installed() {
  command -v curl >/dev/null 2>&1 || { log_error "curl is required but not installed."; exit 1; }
  command -v git >/dev/null 2>&1 || { log_error "git is required but not installed."; exit 1; }
  command -v jq >/dev/null 2>&1 || { log_error "jq is required but not installed."; exit 1; }
  command -v nix >/dev/null 2>&1 || { log_error "nix is required but not installed."; exit 1; }
  command -v patch >/dev/null 2>&1 || { log_error "patch is required but not installed."; exit 1; }
}

print_usage() {
  cat <<USAGE
Usage: $0 [OPTIONS]

Options:
  --check             Check whether an update is needed (no file changes)
  --version VERSION   Pin to a specific release version (e.g. 0.19.0)
  --help              Show this help message
USAGE
}

get_current_version() {
  sed -n 's/^[[:space:]]*version = "\([^"]*\)";/\1/p' package.nix | head -1
}

get_current_src_hash() {
  sed -n 's/^[[:space:]]*srcHash = "\([^"]*\)";/\1/p' package.nix | head -1
}

get_current_pnpm_hash() {
  sed -n 's/^[[:space:]]*pnpmDepsHash = "\([^"]*\)";/\1/p' package.nix | head -1
}

get_current_cargo_hash() {
  sed -n 's/^[[:space:]]*cargoDepsHash = "\([^"]*\)";/\1/p' package.nix | head -1
}

get_packaging_patch_paths() {
  awk '
    /^[[:space:]]*patches = \[/ { in_patches = 1; next }
    in_patches && /^[[:space:]]*\];/ { in_patches = 0; next }
    in_patches {
      line = $0
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      gsub(/,/, "", line)
      if (line ~ /^\.\/patches\/.*\.patch$/) {
        sub(/^\.\//, "", line)
        print line
      }
    }
  ' package.nix
}

github_api_get() {
  local url="$1"
  local token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"

  if [ -n "$token" ]; then
    curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer ${token}" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "$url"
  else
    curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "$url"
  fi
}

fetch_release_json() {
  local target_version="$1"

  if [ -n "$target_version" ]; then
    github_api_get "${GITHUB_API_BASE}/tags/v${target_version}"
  else
    github_api_get "${GITHUB_API_BASE}/latest"
  fi
}

extract_version_from_release_json() {
  jq -r '.tag_name | ltrimstr("v")'
}

prefetch_sri_hash() {
  local url="$1"
  local hash

  hash=$(
    nix store prefetch-file --json --hash-type sha256 --unpack "$url" \
      | jq -r '.hash // empty'
  )

  if [ -z "$hash" ] || [ "$hash" = "null" ]; then
    log_error "Could not prefetch source hash for $url"
    return 1
  fi

  printf '%s\n' "$hash"
}

prepare_release_source_tree() {
  local version="$1"
  local dest_dir="$2"
  local src_url="https://github.com/zhom/donutbrowser/archive/refs/tags/v${version}.tar.gz"

  mkdir -p "$dest_dir"
  curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors "$src_url" \
    | tar -xzf - --strip-components=1 -C "$dest_dir"
}

check_patch_set_applicability() {
  local version="$1"
  local repo_root temp_dir patch_path
  local -a failed_patches=()

  repo_root=$(pwd -P)
  temp_dir=$(mktemp -d)

  if ! prepare_release_source_tree "$version" "$temp_dir"; then
    rm -rf "$temp_dir"
    return 1
  fi

  while IFS= read -r patch_path; do
    [ -n "$patch_path" ] || continue

    if ! (cd "$temp_dir" && patch --dry-run -p1 --forward -i "$repo_root/$patch_path" >/dev/null); then
      failed_patches+=("$patch_path")
    fi
  done < <(get_packaging_patch_paths)

  if [ "${#failed_patches[@]}" -ne 0 ]; then
    printf '%s\n' "${failed_patches[@]}"
    rm -rf "$temp_dir"
    return 1
  fi

  rm -rf "$temp_dir"
  return 0
}

update_package_file() {
  local new_version="$1"
  local new_src_hash="$2"
  local new_pnpm_hash="$3"
  local new_cargo_hash="$4"
  local tmp_file

  tmp_file=$(mktemp)

  if ! awk \
    -v new_version="$new_version" \
    -v new_src_hash="$new_src_hash" \
    -v new_pnpm_hash="$new_pnpm_hash" \
    -v new_cargo_hash="$new_cargo_hash" '
      !version_updated && $0 ~ /^[[:space:]]*version = "/ {
        sub(/"[^"]+"/, "\"" new_version "\"")
        version_updated = 1
      }
      !src_hash_updated && $0 ~ /^[[:space:]]*srcHash = "/ {
        sub(/"[^"]+"/, "\"" new_src_hash "\"")
        src_hash_updated = 1
      }
      !pnpm_hash_updated && $0 ~ /^[[:space:]]*pnpmDepsHash = "/ {
        sub(/"[^"]+"/, "\"" new_pnpm_hash "\"")
        pnpm_hash_updated = 1
      }
      !cargo_hash_updated && $0 ~ /^[[:space:]]*cargoDepsHash = "/ {
        sub(/"[^"]+"/, "\"" new_cargo_hash "\"")
        cargo_hash_updated = 1
      }
      { print }
      END {
        if (!version_updated || !src_hash_updated || !pnpm_hash_updated || !cargo_hash_updated) {
          exit 1
        }
      }
    ' package.nix > "$tmp_file"; then
    rm -f "$tmp_file"
    return 1
  fi

  mv "$tmp_file" package.nix
}

resolve_fixed_output_hash() {
  local target="$1"
  local output
  local status
  local got_hash

  set +e
  output=$(nix build "$target" --no-link 2>&1)
  status=$?
  set -e

  if [ "$status" -eq 0 ]; then
    echo ""
    return 0
  fi

  got_hash=$(printf '%s\n' "$output" | sed -n 's/^[[:space:]]*got:[[:space:]]*//p' | tail -1)
  if [ -z "$got_hash" ]; then
    printf '%s\n' "$output" >&2
    return 1
  fi

  printf '%s\n' "$got_hash"
}

one_line_file() {
  local file="$1"

  if [ ! -s "$file" ]; then
    return 0
  fi

  tr '\n' ' ' < "$file" \
    | sed 's/[[:space:]][[:space:]]*/ /g; s/^[[:space:]]*//; s/[[:space:]]*$//'
}

print_state() {
  local current_version="$1"
  local latest_version="$2"
  local current_src_hash="$3"
  local latest_src_hash="$4"
  local current_pnpm_hash="$5"
  local latest_pnpm_hash="$6"
  local current_cargo_hash="$7"
  local latest_cargo_hash="$8"
  local update_needed="$9"

  echo "current_version=${current_version}"
  echo "latest_version=${latest_version}"
  echo "current_src_hash=${current_src_hash}"
  echo "latest_src_hash=${latest_src_hash}"
  echo "current_pnpm_hash=${current_pnpm_hash}"
  echo "latest_pnpm_hash=${latest_pnpm_hash}"
  echo "current_cargo_hash=${current_cargo_hash}"
  echo "latest_cargo_hash=${latest_cargo_hash}"
  echo "update_needed=${update_needed}"
}

print_blocked_state() {
  local update_blocked="$1"
  local blocked_reason="$2"
  local blocked_version="$3"
  local blocked_patches="$4"
  local refresh_command="$5"
  local blocked_details="${6:-}"

  echo "update_blocked=${update_blocked}"
  echo "blocked_reason=${blocked_reason}"
  echo "blocked_version=${blocked_version}"
  echo "blocked_patches=${blocked_patches}"
  echo "refresh_command=${refresh_command}"
  echo "blocked_details=${blocked_details}"
}

main() {
  ensure_in_repository_root
  ensure_required_tools_installed

  local check_only=false
  local target_version=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check)
        check_only=true
        shift
        ;;
      --version)
        target_version="${2:-}"
        if [ -z "$target_version" ]; then
          log_error "--version requires a value"
          exit 1
        fi
        target_version="${target_version#v}"
        shift 2
        ;;
      --help)
        print_usage
        exit 0
        ;;
      *)
        log_error "Unknown option: $1"
        print_usage
        exit 1
        ;;
    esac
  done

  local current_version
  current_version=$(get_current_version)
  local current_src_hash
  current_src_hash=$(get_current_src_hash)
  local current_pnpm_hash
  current_pnpm_hash=$(get_current_pnpm_hash)
  local current_cargo_hash
  current_cargo_hash=$(get_current_cargo_hash)

  local release_json
  release_json=$(fetch_release_json "$target_version")

  local latest_version
  latest_version=$(printf '%s\n' "$release_json" | extract_version_from_release_json)
  if [ -z "$latest_version" ] || [ "$latest_version" = "null" ]; then
    log_error "Could not determine latest release version"
    exit 1
  fi

  local src_url
  src_url="https://github.com/zhom/donutbrowser/archive/refs/tags/v${latest_version}.tar.gz"
  local latest_src_hash
  latest_src_hash=$(prefetch_sri_hash "$src_url")

  local update_needed=false
  if [ "$current_version" != "$latest_version" ]; then
    update_needed=true
  fi

  local update_blocked=false
  local blocked_reason=""
  local blocked_version=""
  local blocked_patches=""
  local refresh_command=""
  local blocked_details=""

  if [ "$update_needed" = true ]; then
    local patch_check_output
    patch_check_output=$(check_patch_set_applicability "$latest_version" 2>&1) || {
      update_blocked=true
      blocked_reason="patches"
      blocked_version="$latest_version"
      blocked_patches=$(printf '%s\n' "$patch_check_output" | paste -sd ',' -)
      refresh_command="./scripts/refresh-patches.sh --version ${latest_version}"
      blocked_details="carried patches no longer apply"
      update_needed=false
      log_warn "Skipping update to ${latest_version} because carried patches no longer apply:"
      printf '%s\n' "$patch_check_output" | sed 's/^/  - /'
      log_warn "Refresh command: ${refresh_command}"
    }
  fi

  if [ "$check_only" = true ]; then
    print_state \
      "$current_version" \
      "$latest_version" \
      "$current_src_hash" \
      "$latest_src_hash" \
      "$current_pnpm_hash" \
      "$current_pnpm_hash" \
      "$current_cargo_hash" \
      "$current_cargo_hash" \
      "$update_needed"
    print_blocked_state "$update_blocked" "$blocked_reason" "$blocked_version" "$blocked_patches" "$refresh_command" "$blocked_details"
    if [ "$update_blocked" = true ]; then
      exit "$UPDATE_BLOCKED_EXIT_CODE"
    fi
    if [ "$update_needed" = true ] && [ "$update_blocked" != true ]; then
      exit 1
    fi
    exit 0
  fi

  if [ "$update_needed" != true ]; then
    print_state \
      "$current_version" \
      "$latest_version" \
      "$current_src_hash" \
      "$latest_src_hash" \
      "$current_pnpm_hash" \
      "$current_pnpm_hash" \
      "$current_cargo_hash" \
      "$current_cargo_hash" \
      false
    print_blocked_state "$update_blocked" "$blocked_reason" "$blocked_version" "$blocked_patches" "$refresh_command" "$blocked_details"
    if [ "$update_blocked" = true ]; then
      exit "$UPDATE_BLOCKED_EXIT_CODE"
    fi
    exit 0
  fi

  log_info "Updating Donut Browser to version ${latest_version}..."

  PACKAGE_BACKUP=$(mktemp)
  cp package.nix "$PACKAGE_BACKUP"
  RESTORE_PACKAGE_ON_EXIT=true
  trap restore_package_backup_on_exit EXIT

  if ! update_package_file "$latest_version" "$latest_src_hash" "$FAKE_HASH" "$FAKE_HASH"; then
    restore_package_backup
    print_state \
      "$current_version" \
      "$latest_version" \
      "$current_src_hash" \
      "$latest_src_hash" \
      "$current_pnpm_hash" \
      "$current_pnpm_hash" \
      "$current_cargo_hash" \
      "$current_cargo_hash" \
      false
    print_blocked_state true "source-layout" "$latest_version" "" "" "package.nix version/hash fields were not found"
    exit "$UPDATE_BLOCKED_EXIT_CODE"
  fi

  log_info "Resolving pnpm dependency hash..."
  local latest_pnpm_hash pnpm_error
  pnpm_error=$(mktemp)
  if ! latest_pnpm_hash=$(resolve_fixed_output_hash .#pnpm-deps 2>"$pnpm_error"); then
    blocked_details=$(one_line_file "$pnpm_error")
    rm -f "$pnpm_error"
    restore_package_backup
    print_state \
      "$current_version" \
      "$latest_version" \
      "$current_src_hash" \
      "$latest_src_hash" \
      "$current_pnpm_hash" \
      "$current_pnpm_hash" \
      "$current_cargo_hash" \
      "$current_cargo_hash" \
      false
    print_blocked_state true "pnpm-hash" "$latest_version" "" "" "$blocked_details"
    exit "$UPDATE_BLOCKED_EXIT_CODE"
  fi
  rm -f "$pnpm_error"
  if [ -z "$latest_pnpm_hash" ]; then
    latest_pnpm_hash=$(get_current_pnpm_hash)
  fi
  if ! update_package_file "$latest_version" "$latest_src_hash" "$latest_pnpm_hash" "$FAKE_HASH"; then
    restore_package_backup
    print_state \
      "$current_version" \
      "$latest_version" \
      "$current_src_hash" \
      "$latest_src_hash" \
      "$current_pnpm_hash" \
      "$latest_pnpm_hash" \
      "$current_cargo_hash" \
      "$current_cargo_hash" \
      false
    print_blocked_state true "source-layout" "$latest_version" "" "" "package.nix version/hash fields were not found"
    exit "$UPDATE_BLOCKED_EXIT_CODE"
  fi

  log_info "Resolving cargo dependency hash..."
  local latest_cargo_hash cargo_error
  cargo_error=$(mktemp)
  if ! latest_cargo_hash=$(resolve_fixed_output_hash .#cargo-deps 2>"$cargo_error"); then
    blocked_details=$(one_line_file "$cargo_error")
    rm -f "$cargo_error"
    restore_package_backup
    print_state \
      "$current_version" \
      "$latest_version" \
      "$current_src_hash" \
      "$latest_src_hash" \
      "$current_pnpm_hash" \
      "$latest_pnpm_hash" \
      "$current_cargo_hash" \
      "$current_cargo_hash" \
      false
    print_blocked_state true "cargo-hash" "$latest_version" "" "" "$blocked_details"
    exit "$UPDATE_BLOCKED_EXIT_CODE"
  fi
  rm -f "$cargo_error"
  if [ -z "$latest_cargo_hash" ]; then
    latest_cargo_hash=$(get_current_cargo_hash)
  fi
  if ! update_package_file "$latest_version" "$latest_src_hash" "$latest_pnpm_hash" "$latest_cargo_hash"; then
    restore_package_backup
    print_state \
      "$current_version" \
      "$latest_version" \
      "$current_src_hash" \
      "$latest_src_hash" \
      "$current_pnpm_hash" \
      "$latest_pnpm_hash" \
      "$current_cargo_hash" \
      "$latest_cargo_hash" \
      false
    print_blocked_state true "source-layout" "$latest_version" "" "" "package.nix version/hash fields were not found"
    exit "$UPDATE_BLOCKED_EXIT_CODE"
  fi

  log_info "Verifying full package build..."
  local build_output build_status
  set +e
  build_output=$(nix build .#donutbrowser --no-link 2>&1)
  build_status=$?
  set -e
  if [ "$build_status" -ne 0 ]; then
    printf '%s\n' "$build_output" >&2
    log_warn "Skipping update to ${latest_version} because the full package build failed."
    restore_package_backup

    print_state \
      "$current_version" \
      "$latest_version" \
      "$current_src_hash" \
      "$latest_src_hash" \
      "$current_pnpm_hash" \
      "$latest_pnpm_hash" \
      "$current_cargo_hash" \
      "$latest_cargo_hash" \
      false
    print_blocked_state true "build" "$latest_version" "" "" "nix build .#donutbrowser --no-link failed"
    exit "$UPDATE_BLOCKED_EXIT_CODE"
  fi

  rm -f "$PACKAGE_BACKUP"
  PACKAGE_BACKUP=""
  RESTORE_PACKAGE_ON_EXIT=false

  print_state \
    "$current_version" \
    "$latest_version" \
    "$current_src_hash" \
    "$latest_src_hash" \
    "$current_pnpm_hash" \
    "$latest_pnpm_hash" \
    "$current_cargo_hash" \
    "$latest_cargo_hash" \
    true
  print_blocked_state false "" "" "" "" ""
}

main "$@"
