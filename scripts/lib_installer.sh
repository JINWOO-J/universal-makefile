#!/usr/bin/env bash
# scripts/lib_installer.sh — Core installer logic as a reusable library
# Exposes: umf_install_main "$@"

set -euo pipefail

: "${TMPDIR:=/tmp}"
TMPDIR="${TMPDIR%/}"
UMF_TMP_DIR="$(mktemp -d "${TMPDIR}/umf-install.XXXXXX")"
_umf_cleanup_tmp() { rm -rf "${UMF_TMP_DIR}" >/dev/null 2>&1 || true; }
trap _umf_cleanup_tmp EXIT INT TERM

# Colors
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
  RED=$(tput setaf 1); GREEN=$(tput setaf 2); YELLOW=$(tput setaf 3); BLUE=$(tput setaf 4); RESET=$(tput sgr0)
else
  RED=""; GREEN=""; YELLOW=""; BLUE=""; RESET=""
fi
log_info()    { echo "${BLUE}ℹ️  $1${RESET}"; }
log_success() { echo "${GREEN}✅ $1${RESET}"; }
log_warn()    { echo "${YELLOW}⚠️  $1${RESET}"; }
log_error()   { echo "${RED}❌ $1${RESET}" >&2; }

MAKEFILE_DIR=".makefile-system"
GITHUB_OWNER="jinwoo-j"
GITHUB_REPO="universal-makefile"
GITHUB_REPO_SLUG="${GITHUB_OWNER}/${GITHUB_REPO}"
MAIN_BRANCH="main"

REPO_URL="https://github.com/${GITHUB_REPO_SLUG}"
INSTALLER_SCRIPT_URL="https://raw.githubusercontent.com/${GITHUB_REPO_SLUG}/${MAIN_BRANCH}/install.sh"

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
INSTALLATION_TYPE="release"
DESIRED_REF=""
YES=false

FORCE_INSTALL=false
DRY_RUN=false
BACKUP=false
EXISTING_PROJECT=false
DEBUG_MODE=false
CURRENT_CMD=""

# Retry configs
CURL_RETRY_MAX=${CURL_RETRY_MAX:-3}
CURL_RETRY_DELAY_SEC=${CURL_RETRY_DELAY_SEC:-2}

log_debug() { if [[ "${DEBUG_MODE:-false}" == "true" ]]; then echo "${YELLOW}🔎 $*${RESET}"; fi; return 0; }

enable_xtrace_if_debug() { if [[ "${DEBUG_MODE:-false}" == "true" ]]; then set -x; log_debug "xtrace enabled"; fi }

# --- Source shared libs (optional) ---
_umr_try_source() { local cands=("./scripts/lib_release.sh" "${MAKEFILE_DIR}/scripts/lib_release.sh"); for f in "${cands[@]}"; do [[ -f "$f" ]] && . "$f" && return 0; done; return 1; }
_umc_try_source() { local cands=("./scripts/lib_scaffold.sh" "${MAKEFILE_DIR}/scripts/lib_scaffold.sh"); for f in "${cands[@]}"; do [[ -f "$f" ]] && . "$f" && return 0; done; return 1; }
_umr_try_source || true
_umc_try_source || true

# Fallbacks if libs not available
type umr_verify_sha256 >/dev/null 2>&1 || umr_verify_sha256() { local file_path="$1" expected="$2"; if [ -z "$expected" ]; then return 2; fi; if command -v sha256sum >/dev/null 2>&1; then echo "${expected}  ${file_path}" | sha256sum -c --status; return $?; fi; if command -v shasum >/dev/null 2>&1; then echo "${expected}  ${file_path}" | shasum -a 256 -c --status; return $?; fi; return 3; }

type umr_fetch_latest_release_tag >/dev/null 2>&1 || umr_fetch_latest_release_tag() {
  local owner="$1" repo="$2"
  local api_url="https://api.github.com/repos/${owner}/${repo}/releases/latest"
  local tag
  local -a auth=()
  [[ -n "${GITHUB_TOKEN:-}" ]] && auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  if command -v curl >/dev/null 2>&1; then
    tag=$(curl -fsSL "${auth[@]}" "$api_url" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1 || true)
  elif command -v wget >/dev/null 2>&1; then
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
      tag=$(wget -qO- --header="Authorization: Bearer ${GITHUB_TOKEN}" "$api_url" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1 || true)
    else
      tag=$(wget -qO- "$api_url" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1 || true)
    fi
  fi
  if [[ -n "$tag" ]]; then
    echo "$tag"; return 0
  fi
  if command -v git >/dev/null 2>&1; then
    tag=$(git ls-remote --tags --refs "https://github.com/${owner}/${repo}.git" 2>/dev/null | awk '{print $2}' | sed 's@refs/tags/@@' | sort -Vr | head -n1)
    [[ -n "$tag" ]] && echo "$tag" && return 0
  fi
  return 1
}

type umr_build_tarball_urls >/dev/null 2>&1 || umr_build_tarball_urls() {
  local owner="$1" repo="$2" ref="$3"
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    echo "https://api.github.com/repos/${owner}/${repo}/tarball/${ref}"
    case "$ref" in
      main|master|develop|*-branch|*-snapshot)
        echo "https://codeload.github.com/${owner}/${repo}/tar.gz/refs/heads/${ref}"
        ;;
      *)
        echo "https://codeload.github.com/${owner}/${repo}/tar.gz/refs/tags/${ref}"
        ;;
    esac
    return 0
  fi
  case "$ref" in
    main|master|develop|*-branch|*-snapshot)
      echo "https://github.com/${owner}/${repo}/archive/refs/heads/${ref}.tar.gz"
      echo "https://codeload.github.com/${owner}/${repo}/tar.gz/refs/heads/${ref}"
      ;;
    *)
      echo "https://github.com/${owner}/${repo}/archive/refs/tags/${ref}.tar.gz"
      echo "https://codeload.github.com/${owner}/${repo}/tar.gz/refs/tags/${ref}"
      ;;
  esac
}

type umr_download_with_retries >/dev/null 2>&1 || umr_download_with_retries() {
  local url="$1" out="$2"
  shift 2
  local -a headers=("$@")
  local -a curl_headers=()
  for h in "${headers[@]}"; do
    curl_headers+=( -H "$h" )
  done
  local attempt
  for attempt in $(seq 1 ${CURL_RETRY_MAX}); do
    if command -v curl >/dev/null 2>&1; then
      local _had_xtrace=0; case "$-" in *x*) _had_xtrace=1; set +x ;; esac
      if curl -fSL --connect-timeout 10 --max-time 300 "${curl_headers[@]}" -o "$out" "$url"; then
        [ "$_had_xtrace" -eq 1 ] && set -x
        [[ -s "$out" ]] && return 0
      fi
      [ "$_had_xtrace" -eq 1 ] && set -x
    elif command -v wget >/dev/null 2>&1; then
      local -a wget_hdr=()
      for h in "${headers[@]}"; do wget_hdr+=(--header "$h"); done
      if wget -q "${wget_hdr[@]}" -O "$out" "$url"; then [[ -s "$out" ]] && return 0; fi
    else
      return 127
    fi
    sleep $((CURL_RETRY_DELAY_SEC * (2 ** (attempt - 1)))) || sleep ${CURL_RETRY_DELAY_SEC}
  done
  return 1
}

type umr_download_tarball >/dev/null 2>&1 || umr_download_tarball() {
  local owner="$1" repo="$2" ref="$3" out_tar="$4"
  local primary mirror
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    local repo_code
    repo_code=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer ${GITHUB_TOKEN}" "https://api.github.com/repos/${owner}/${repo}") || repo_code="000"
    if [[ "$repo_code" != "200" ]]; then
      log_warn "GitHub token may not have access to ${owner}/${repo} (HTTP ${repo_code}). Falling back if possible."
    fi
  fi
  read -r primary < <(umr_build_tarball_urls "$owner" "$repo" "$ref")
  read -r mirror < <(umr_build_tarball_urls "$owner" "$repo" "$ref" | sed -n '2p')
  local -a headers=()
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    headers+=("Authorization: Bearer ${GITHUB_TOKEN}" "X-GitHub-Api-Version: 2022-11-28" "Accept: application/vnd.github+json")
  fi
  umr_download_with_retries "$primary" "$out_tar" "${headers[@]}" \
    || umr_download_with_retries "$mirror" "$out_tar" "${headers[@]}"
}

type umr_tar_first_dir >/dev/null 2>&1 || umr_tar_first_dir() { local tarfile="$1"; tar -tzf "$tarfile" >/dev/null 2>&1 || return 2; tar -tzf "$tarfile" 2>/dev/null | head -n1 | cut -d/ -f1; }

type umr_extract_tarball >/dev/null 2>&1 || umr_extract_tarball() { local tarfile="$1" dest="$2"; mkdir -p "$dest" && tar -xzf "$tarfile" -C "$dest" 2>/dev/null; }

# Scaffold lib fallbacks
type umc_scaffold_project_files >/dev/null 2>&1 || umc_scaffold_project_files() { umc_create_main_makefile; umc_create_project_config; umc_update_gitignore; umc_create_environments; }

type umc_create_main_makefile >/dev/null 2>&1 || umc_create_main_makefile() { :; }
type umc_create_project_config >/dev/null 2>&1 || umc_create_project_config() { :; }
type umc_update_gitignore >/dev/null 2>&1 || umc_update_gitignore() { :; }
type umc_create_environments >/dev/null 2>&1 || umc_create_environments() { :; }
type umc_create_sample_compose >/dev/null 2>&1 || umc_create_sample_compose() { :; }

usage_installer() {
  cat <<EOF
Universal Makefile System Installer (lib)

Usage: install.sh <command> [options]
Commands: install | update | uninstall | status | app | help
EOF
}

resolve_flag() {
  local env_var_name=$1 long_flag=$2 short_flag=$3; shift 3
  local all_args=("$@")
  for arg in "${all_args[@]:-}"; do
    if [[ "$arg" == "$long_flag" || (-n "$short_flag" && "$arg" == "$short_flag") ]]; then echo "true"; return; fi
  done
  eval "local env_val=\"\${$env_var_name:-}\""
  if [ -n "${env_val+x}" ]; then
    if [[ "$(echo "$env_val" | tr '[:upper:]' '[:lower:]')" == "true" ]]; then echo "true"; else echo "false"; fi
  else
    echo "false"
  fi
}

parse_common_args_installer() {
  FORCE_INSTALL=$(resolve_flag "FORCE" "--force" "" "$@")
  DRY_RUN=$(resolve_flag "DRY_RUN" "--dry-run" "" "$@")
  BACKUP=$(resolve_flag "BACKUP" "--backup" "" "$@")
  DEBUG_MODE=$(resolve_flag "DEBUG" "--debug" "-d" "$@")
  YES=$(resolve_flag "YES" "--yes" "-y" "$@")
}

parse_install_args_installer() {
  INSTALLATION_TYPE="release"; EXISTING_PROJECT=false
  local remaining_args=()
  while [[ $# -gt 0 ]]; do
    case $1 in
      --copy)       INSTALLATION_TYPE="copy"; shift ;;
      --subtree)    INSTALLATION_TYPE="subtree"; shift ;;
      --submodule)  INSTALLATION_TYPE="submodule"; shift ;;
      --release)    INSTALLATION_TYPE="release"; shift ;;
      --prefix)     MAKEFILE_DIR="$2"; shift 2 ;;
      --version)    DESIRED_REF="$2"; shift 2 ;;
      --ref)        DESIRED_REF="$2"; shift 2 ;;
      --existing-project) EXISTING_PROJECT=true; shift ;;
      --help|-h)    usage_installer; return 2 ;;
      *)            remaining_args+=("$1"); shift ;;
    esac
  done
  parse_common_args_installer "${remaining_args[@]:-}"
}

# The following functions are adapted from install.sh
has_universal_id() { local file=$1; [[ -f "$file" ]] && grep -q "Universal Makefile System" "$file"; }

check_requirements_installer() {
  log_info "Checking requirements..."
  if [[ "$CURRENT_CMD" == "install" || "$CURRENT_CMD" == "update" ]]; then
    if [[ "$INSTALLATION_TYPE" == "submodule" || "$INSTALLATION_TYPE" == "subtree" ]]; then
      command -v git >/dev/null 2>&1 || { log_error "Git is required for $INSTALLATION_TYPE installation"; exit 1; }
      git rev-parse --git-dir >/dev/null 2>&1 || { log_error "Not in a git repository. Initialize git first or use --copy"; exit 1; }
    fi
    if [[ "$INSTALLATION_TYPE" == "release" ]]; then
      command -v tar >/dev/null 2>&1 || { log_error "tar is required for --release installation"; exit 1; }
      command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || { log_error "Either curl or wget is required for --release installation"; exit 1; }
    fi
  fi
  command -v make >/dev/null 2>&1 || { log_error "Make is required"; exit 1; }
  log_success "Requirements check passed"
}

install_submodule() {
  log_info "Installing as git submodule..."
  if [[ "$FORCE_INSTALL" == true && -d "$MAKEFILE_DIR" ]]; then
    log_info "Removing existing submodule..."; git submodule deinit -f "$MAKEFILE_DIR" || true; git rm -f "$MAKEFILE_DIR" || true; rm -rf ".git/modules/$MAKEFILE_DIR" "$MAKEFILE_DIR"
  fi
  if ! git submodule add "$REPO_URL" "$MAKEFILE_DIR"; then
    if git config --file .gitmodules --get "submodule.$MAKEFILE_DIR.url" >/dev/null 2>&1; then log_info "Submodule already exists, continuing..."; else log_error "Failed to add submodule"; exit 1; fi
  fi
  git submodule update --init --recursive; log_success "Submodule installation completed"
}

install_copy() {
  log_info "Installing by copying files..."; local temp_dir; temp_dir="$(mktemp -d "${UMF_TMP_DIR}/copy.XXXXXX")"
  local source_dir; if [[ -f "$SCRIPT_DIR/makefiles/core.mk" ]]; then log_info "Using local repository files"; source_dir="$SCRIPT_DIR"; else log_info "Cloning from $REPO_URL"; git clone "$REPO_URL" "$temp_dir/universal-makefile"; source_dir="$temp_dir/universal-makefile"; fi
  [[ "$FORCE_INSTALL" == true || ! -d "makefiles" ]] && cp -r "$source_dir/makefiles" .
  [[ "$FORCE_INSTALL" == true || ! -d "scripts" ]] && cp -r "$source_dir/scripts" . 2>/dev/null || true
  [[ "$FORCE_INSTALL" == true || ! -d "templates" ]] && cp -r "$source_dir/templates" . 2>/dev/null || true
  [[ -f "$source_dir/VERSION" ]] && cp "$source_dir/VERSION" .
  log_success "Copy installation completed"
}

install_subtree() {
  log_info "Installing via git subtree..."
  command -v git >/dev/null 2>&1 || { log_error "Git is required for subtree installation"; exit 1; }
  git rev-parse --git-dir >/dev/null 2>&1 || { log_error "Not in a git repository. Initialize git first or use --copy"; exit 1; }

  local prefix_dir="$MAKEFILE_DIR" remote_name="universal-makefile-remote"
  if ! git remote get-url "$remote_name" >/dev/null 2>&1; then git remote add "$remote_name" "$REPO_URL"; log_info "Added remote '$remote_name' -> $REPO_URL"; fi
  local remote_head; remote_head=$(git ls-remote --symref "$remote_name" HEAD 2>/dev/null | sed -n 's@^ref: refs/heads/\([^\t\n\r ]*\)[\t ]*HEAD@\1@p' | head -n1)
  if [[ -z "$remote_head" ]]; then if git ls-remote --exit-code --heads "$remote_name" main >/dev/null 2>&1; then remote_head=main; elif git ls-remote --exit-code --heads "$remote_name" master >/dev/null 2>&1; then remote_head=master; else remote_head="$MAIN_BRANCH"; fi; fi
  log_info "Using remote default branch: ${remote_head}"; git fetch "$remote_name" "$remote_head" --tags --quiet || git fetch "$remote_name" --tags --quiet

  if [[ -d "$prefix_dir" ]]; then
    log_warn "Directory '$prefix_dir' already exists. Attempting to merge updates..."; git subtree pull --prefix="$prefix_dir" "$remote_name" "$remote_head" --squash || { log_error "git subtree pull failed"; exit 1; }; log_success "Subtree updated at '$prefix_dir'"
  else
    git subtree add --prefix="$prefix_dir" "$remote_name" "$remote_head" --squash || { log_error "git subtree add failed"; exit 1; }; log_success "Subtree installed at '$prefix_dir'"
  fi
}

install_release() {
  log_info "Installing via GitHub release tarball..."
  enable_xtrace_if_debug

  local desired=""
  if [[ -n "${DESIRED_REF:-}" ]]; then
    desired="${DESIRED_REF}"; log_info "Using explicit ref: ${desired}"
  elif [[ -f ".ums-version" ]]; then
    desired="$(cat .ums-version)"; log_info "Pinned version found in .ums-version: ${desired}"
  else
    desired="$(umr_fetch_latest_release_tag "${GITHUB_OWNER}" "${GITHUB_REPO}" || true)"
    if [[ -z "${desired}" ]]; then
      log_warn "Could not resolve latest release via API. Falling back to branch snapshot: ${MAIN_BRANCH}"; desired="${MAIN_BRANCH}"
    else
      log_info "Resolved latest release tag: ${desired}"
    fi
  fi

  local workdir="${UMF_TMP_DIR}/release.$$"
  local tarball
  local extract_dir
  mkdir -p "${workdir}"; tarball="${workdir}/umf.tar.gz"; extract_dir="${workdir}/extract"; mkdir -p "${extract_dir}"
  log_debug "workdir=${workdir}"; log_debug "tarball=${tarball}"; log_debug "extract_dir=${extract_dir}"; log_debug "INSTALL_PREFIX(MAKEFILE_DIR)=${MAKEFILE_DIR}"

  if ! umr_download_tarball "${GITHUB_OWNER}" "${GITHUB_REPO}" "${desired}" "${tarball}"; then
    log_error "Failed to download release tarball for ${desired}."; [[ -n "${GITHUB_TOKEN:-}" ]] && log_warn "If private repo, ensure token access."; return 1
  fi

  if ! tar -tzf "${tarball}" >/dev/null 2>&1; then log_error "Downloaded file is not a valid tar.gz archive"; return 1; fi
  log_success "Download verified: valid tar.gz archive."

  local ROOT_DIR_NAME; ROOT_DIR_NAME="$(umr_tar_first_dir "${tarball}" || true)"; if [[ -z "${ROOT_DIR_NAME}" ]]; then log_error "Could not determine top-level directory inside the archive."; return 1; fi

  log_debug "Extracting tarball to ${extract_dir} ..."; if ! umr_extract_tarball "${tarball}" "${extract_dir}"; then log_error "tar extraction failed"; return 1; fi

  local top="${extract_dir}/${ROOT_DIR_NAME}"; if [[ ! -d "${top}" ]]; then
    log_warn "Top dir '${top}' not found; scanning extract_dir for candidates..."; top="$(find "${extract_dir}" -mindepth 1 -maxdepth 1 -type d | head -n1 || true)"; [[ -z "${top}" || ! -d "${top}" ]] && { log_error "Extracted directory not found."; return 1; }
  fi

  rm -rf "${MAKEFILE_DIR}"; mv "${top}" "${MAKEFILE_DIR}"; if [[ "${desired}" != "${MAIN_BRANCH}" ]]; then echo "${desired}" > "${MAKEFILE_DIR}/.version"; fi
  log_success "Makefile system installed at '${MAKEFILE_DIR}' (source: ${desired})."

  local must_have=("makefiles/core.mk" "makefiles/help.mk" "makefiles/version.mk"); local missing=0; local rel
  for rel in "${must_have[@]}"; do [[ -f "${MAKEFILE_DIR}/${rel}" ]] || { log_warn "Missing expected file: ${MAKEFILE_DIR}/${rel}"; missing=1; }; done; [[ "${missing}" -eq 1 ]] && log_warn "Some expected files are missing. Archive layout may have changed."
}

install_github_workflow() {
  log_info "Installing GitHub Actions workflow..."; mkdir -p .github/workflows
  local src_dir="$MAKEFILE_DIR/github/workflows"; shopt -s nullglob; local files=("$src_dir"/*); shopt -u nullglob
  if [[ ${#files[@]} -eq 0 ]]; then log_warn "No workflows to install in $src_dir"; return 0; fi
  log_info "Copying the following workflow files:"; for f in "${files[@]}"; do echo "  - $f"; done
  cp -rf "${files[@]}" .github/workflows/; log_success "GitHub Actions workflow installed"
}

show_status_installer() {
  log_info "Checking status of the installed Universal Makefile System..."; echo ""
  if [[ -d "$MAKEFILE_DIR" ]] && (cd "$MAKEFILE_DIR" && git rev-parse --is-inside-work-tree >/dev/null 2>&1); then
    local git_dir="$MAKEFILE_DIR" remote branch commit status
    remote=$(git -C "$git_dir" remote get-url origin 2>/dev/null || echo "N/A")
    branch=$(git -C "$git_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "N/A")
    commit=$(git -C "$git_dir" rev-parse --short HEAD 2>/dev/null || echo "N/A")
    status=$(git -C "$git_dir" status --porcelain 2>/dev/null)
    echo "  Installation Type : Submodule"; echo "  Path              : ${git_dir}"; echo "  Remote URL        : ${remote}"; echo "  Branch            : ${branch}"; echo "  Commit            : ${commit}"
    if [[ -n "$status" ]]; then log_warn "Status            : Modified (Local changes detected in system files)"; else log_success "  Status            : Clean"; fi
  elif [[ -d "makefiles" ]]; then
    echo "  Installation Type : Copied Files"; if [[ -f "VERSION" ]]; then local version; version=$(cat VERSION); echo "  Version File      : ${version}"; else echo "  Version File      : Not found"; fi; log_warn "  Cannot determine specific git commit for copied files."
  else
    log_error "Universal Makefile System installation not found."; exit 1
  fi
  echo ""
}

umf_install_main() {
  local cmd=${1:-install}; shift || true
  case "$cmd" in
    install)
      CURRENT_CMD="install"; parse_install_args_installer "$@"; check_requirements_installer
      case "$INSTALLATION_TYPE" in
        submodule) install_submodule ;;
        copy) install_copy ;;
        subtree) install_subtree ;;
        release) install_release ;;
        *) log_error "Invalid installation type: $INSTALLATION_TYPE"; exit 1 ;;
      esac
      _umc_try_source || true
      umc_scaffold_project_files "${MAKEFILE_DIR}" \
      && umc_update_gitignore \
      && umc_create_environments "${FORCE_INSTALL}" \
      && [[ "$EXISTING_PROJECT" == false ]] && umc_create_sample_compose "${FORCE_INSTALL}" \
      && install_github_workflow \
      && log_success "🎉 Universal Makefile System installation completed!"
      ;;
    status)
      parse_common_args_installer "$@"; show_status_installer ;;
    update|pull)
      CURRENT_CMD="update"; parse_common_args_installer "$@"; show_status_installer; log_info "Run 'install.sh install --release' to re-install from latest release" ;;
    help|-h|--help|'')
      usage_installer ;;
    *)
      log_error "Unknown command: $cmd"; usage_installer; exit 1 ;;
  esac
}


