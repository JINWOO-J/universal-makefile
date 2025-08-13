#!/usr/bin/env bash
# setup.v2.sh — Bootstrap and make entrypoint (refactored with shared lib)
# - Keeps behavior of setup.sh but delegates release ops to scripts/lib_release.sh
# - Delegates scaffolding ops to scripts/lib_scaffold.sh
# - Self-contained fallback: if libs not found, defines minimal replacements

set -euo pipefail

# --- Project settings (same as setup.sh) ---
GITHUB_OWNER="jinwoo-j"
GITHUB_REPO="universal-makefile"
MAIN_BRANCH="main"
MAKEFILE_SYSTEM_DIR=".makefile-system"

# Colors
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
  RED=$(tput setaf 1); GREEN=$(tput setaf 2); YELLOW=$(tput setaf 3); BLUE=$(tput setaf 4); RESET=$(tput sgr0)
else
  RED=""; GREEN=""; YELLOW=""; BLUE=""; RESET=""
fi
log_info()    { echo -e "${BLUE}ℹ️  $1${RESET}"; }
log_success() { echo -e "${GREEN}✅ $1${RESET}"; }
log_warn()    { echo -e "${YELLOW}⚠️  $1${RESET}"; }

# Retry defaults (env-overridable)
CURL_RETRY_MAX=${CURL_RETRY_MAX:-3}
CURL_RETRY_DELAY_SEC=${CURL_RETRY_DELAY_SEC:-2}

FORCE_UPDATE=${FORCE_UPDATE:-false}
CLI_VERSION=""

# --- Try source shared libs; else define fallback wrappers ---
_umr_try_source_release() {
  local cands=("./scripts/lib_release.sh" "${MAKEFILE_SYSTEM_DIR}/scripts/lib_release.sh")
  for f in "${cands[@]}"; do [[ -f "$f" ]] && . "$f" && return 0; done
  return 1
}
_umc_try_source_scaffold() {
  local cands=("./scripts/lib_scaffold.sh" "${MAKEFILE_SYSTEM_DIR}/scripts/lib_scaffold.sh")
  for f in "${cands[@]}"; do [[ -f "$f" ]] && . "$f" && return 0; done
  return 1
}

_umr_try_source_release || true
_umc_try_source_scaffold || true

# Fallbacks for release lib
if ! declare -F umr_is_true >/dev/null 2>&1; then
  umr_is_true() {
    case "${1:-}" in
      true|1|yes|on|Y|y) return 0 ;;
      *) return 1 ;;
    esac
  }
fi
if ! declare -F umr_prompt_confirm >/dev/null 2>&1; then
  umr_prompt_confirm() {
    local msg="$1" reply
    if [ -t 0 ]; then
      read -r -p "${msg} [y/N]: " reply || true
      case "$reply" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
      esac
    else
      return 1
    fi
  }
fi
if ! declare -F umr_verify_sha256 >/dev/null 2>&1; then
  umr_verify_sha256() {
    local file_path="$1" expected="$2"
    [ -z "$expected" ] && return 2
    if command -v sha256sum >/dev/null 2>&1; then
      echo "${expected}  ${file_path}" | sha256sum -c --status
      return $?
    elif command -v shasum >/dev/null 2>&1; then
      echo "${expected}  ${file_path}" | shasum -a 256 -c --status
      return $?
    else
      return 3
    fi
  }
fi
if ! declare -F umr_fetch_latest_release_tag >/dev/null 2>&1; then
  umr_fetch_latest_release_tag() {
    local owner="$1" repo="$2"
    local api_url="https://api.github.com/repos/${owner}/${repo}/releases/latest"
    local tag
    local auth=()
    [[ -n "${GITHUB_TOKEN:-}" ]] && auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
    tag=$(curl -fsSL "${auth[@]}" "$api_url" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^\"]*\)".*/\1/p' | head -n1 || true)
    if [ -n "$tag" ]; then
      echo "$tag"
      return 0
    fi
    if command -v git >/dev/null 2>&1; then
      git ls-remote --tags --refs "https://github.com/${owner}/${repo}.git" 2>/dev/null | awk '{print $2}' | sed 's@refs/tags/@@' | sort -Vr | head -n1
    fi
  }
fi
if ! declare -F umr_build_tarball_urls >/dev/null 2>&1; then
  umr_build_tarball_urls() {
    local owner="$1" repo="$2" ref="$3"
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
      # Use API tarball as primary when token is available, and codeload as mirror
      echo "https://api.github.com/repos/${owner}/${repo}/tarball/${ref}"
      case "$ref" in
        main|master|develop|*-branch|*-snapshot)
          echo "https://codeload.github.com/${owner}/${repo}/tar.gz/refs/heads/${ref}"
          ;;
        *)
          echo "https://codeload.github.com/${owner}/${repo}/tar.gz/refs/tags/${ref}"
          ;;
      esac
    else
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
    fi
  }
fi
if ! declare -F umr_download_with_retries >/dev/null 2>&1; then
  umr_download_with_retries() {
    local url="$1" out="$2"
    shift 2
    local -a headers=("$@")
    local -a curl_headers=()
    for h in "${headers[@]}"; do
      curl_headers+=( -H "$h" )
    done
    for attempt in $(seq 1 ${CURL_RETRY_MAX}); do
      # Avoid leaking headers/tokens when xtrace (-x) is enabled
      local _had_xtrace=0
      case "$-" in *x*) _had_xtrace=1; set +x ;; esac
      if curl -fSL --connect-timeout 10 --max-time 300 "${curl_headers[@]}" -o "$out" "$url"; then
        [ "$_had_xtrace" -eq 1 ] && set -x
        [[ -s "$out" ]] && return 0
      fi
      [ "$_had_xtrace" -eq 1 ] && set -x
      sleep $((CURL_RETRY_DELAY_SEC * (2 ** (attempt - 1)))) || sleep ${CURL_RETRY_DELAY_SEC}
    done
    return 1
  }
fi
if ! declare -F umr_download_tarball >/dev/null 2>&1; then
  umr_download_tarball() {
    local owner="$1" repo="$2" ref="$3" out_tar="$4" primary mirror
    # Optional access check when token is provided
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
    umr_download_with_retries "$primary" "$out_tar" "${headers[@]}" || \
      umr_download_with_retries "$mirror" "$out_tar" "${headers[@]}"
  }
fi
if ! declare -F umr_tar_first_dir >/dev/null 2>&1; then
  umr_tar_first_dir() {
    local tarfile="$1"
    tar -tzf "$tarfile" >/dev/null 2>&1 || return 2
    tar -tzf "$tarfile" 2>/dev/null | head -n1 | cut -d/ -f1
  }
fi
if ! declare -F umr_extract_tarball >/dev/null 2>&1; then
  umr_extract_tarball() {
    local tarfile="$1" dest="$2"
    mkdir -p "$dest" && tar -xzf "$tarfile" -C "$dest" 2>/dev/null
  }
fi

# Fallbacks for scaffold lib
if ! declare -F umc_scaffold_project_files >/dev/null 2>&1; then
  umc_scaffold_project_files() { :; }
fi
if ! declare -F umc_create_main_makefile >/dev/null 2>&1; then
  umc_create_main_makefile() { :; }
fi
if ! declare -F umc_create_project_config >/dev/null 2>&1; then
  umc_create_project_config() { :; }
fi
if ! declare -F umc_update_gitignore >/dev/null 2>&1; then
  umc_update_gitignore() { :; }
fi
if ! declare -F umc_create_environments >/dev/null 2>&1; then
  umc_create_environments() { :; }
fi
if ! declare -F umc_create_sample_compose >/dev/null 2>&1; then
  umc_create_sample_compose() { :; }
fi

# Thin wrappers for local usage (prefer shared lib names)
is_true() { umr_is_true "$@"; }
prompt_confirm() { umr_prompt_confirm "$@"; }

parse_cli_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force|-f) FORCE_UPDATE=true; shift ;;
      --version|-v)
        shift || true
        CLI_VERSION="${1:-}"
        if [ -z "${CLI_VERSION}" ]; then
          echo "--version requires a value" >&2; exit 2
        fi
        shift ;;
      --) shift; break ;;
      *) break ;;
    esac
  done
}

makefile_includes_universal() {
  if [ ! -f "Makefile" ]; then return 1; fi
  if grep -Eq '^[[:space:]]*include[[:space:]]+Makefile\.universal' Makefile; then return 0; fi
  if grep -Eq '^[[:space:]]*include[[:space:]]+\$\(MAKEFILE_DIR\)/makefiles/core\.mk' Makefile; then return 0; fi
  return 1
}

# --- Local mode vs bootstrap mode ---
parse_cli_args "$@"

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  log_info "Project repository found. Verifying Makefile system..."

  if [ -n "${CLI_VERSION}" ]; then
    DESIRED_VERSION="${CLI_VERSION}"
    log_info "CLI version specified: ${DESIRED_VERSION}"
  elif [ -f ".ums-version" ]; then
    DESIRED_VERSION=$(cat .ums-version)
    if [ -f "${MAKEFILE_SYSTEM_DIR}/.version" ]; then
      CURRENT_VERSION="$(cat "${MAKEFILE_SYSTEM_DIR}/.version")"
    else
      CURRENT_VERSION=""
    fi
    LATEST_TAG="$(umr_fetch_latest_release_tag "${GITHUB_OWNER}" "${GITHUB_REPO}" || true)"
    if [ -n "${LATEST_TAG}" ]; then
      log_info "Version status: current=${CURRENT_VERSION:-none}, desired=${DESIRED_VERSION}, latest=${LATEST_TAG}"
    else
      log_info "Version status: current=${CURRENT_VERSION:-none}, desired=${DESIRED_VERSION}"
    fi
    if [[ "${CURRENT_VERSION}" != "${DESIRED_VERSION}" ]]; then
      if [ -z "${CURRENT_VERSION}" ]; then
        log_warn "Makefile system is missing. Installing version ${DESIRED_VERSION}..."
      else
        if ! is_true "${FORCE_UPDATE}"; then
          if ! prompt_confirm "New version available (${CURRENT_VERSION} → ${DESIRED_VERSION}). Update now?"; then
            log_info "Skipped update by user choice."; DESIRED_VERSION="${CURRENT_VERSION}"
          fi
        fi
      fi
      # Install/Update via tarball
      TMPDIR_UMR="$(mktemp -d)"; trap 'rm -rf "${TMPDIR_UMR}" >/dev/null 2>&1 || true' EXIT INT TERM
      TARBALL_PATH="${TMPDIR_UMR}/umf.tar.gz"
      if ! umr_download_tarball "${GITHUB_OWNER}" "${GITHUB_REPO}" "${DESIRED_VERSION}" "${TARBALL_PATH}"; then
        log_warn "Failed to download release tarball for ${DESIRED_VERSION}."; exit 1
      fi
      EXPECTED_SHA256="${UMS_TARBALL_SHA256:-}"
      if [ -z "${EXPECTED_SHA256}" ] && [ -f ".ums-version.sha256" ]; then
        EXPECTED_SHA256="$(tr -d ' \n\r' < .ums-version.sha256)"
      fi
      if [ -n "${EXPECTED_SHA256}" ]; then
        if umr_verify_sha256 "${TARBALL_PATH}" "${EXPECTED_SHA256}"; then
          log_success "SHA256 checksum verified."
        else
          log_warn "SHA256 checksum mismatch or verification unavailable. Aborting."; exit 1
        fi
      else
        log_warn "No SHA256 provided (.ums-version.sha256 or UMS_TARBALL_SHA256). Skipping integrity verification."
      fi
      rm -rf "${MAKEFILE_SYSTEM_DIR}" || true
      EXTRACT_DIR="${TMPDIR_UMR}/extract"; mkdir -p "${EXTRACT_DIR}"
      umr_extract_tarball "${TARBALL_PATH}" "${EXTRACT_DIR}" || { log_warn "Extraction failed."; exit 1; }
      ROOT_DIR_NAME="$(umr_tar_first_dir "${TARBALL_PATH}" || true)"
      if [ -z "${ROOT_DIR_NAME}" ] || [ ! -d "${EXTRACT_DIR}/${ROOT_DIR_NAME}" ]; then
        log_warn "Extracted directory not found. Aborting."; exit 1
      fi
      mv "${EXTRACT_DIR}/${ROOT_DIR_NAME}" "${MAKEFILE_SYSTEM_DIR}"
      echo "${DESIRED_VERSION}" > "${MAKEFILE_SYSTEM_DIR}/.version"
      log_success "Makefile system version ${DESIRED_VERSION} is now ready."
    else
      if [ -n "${LATEST_TAG:-}" ] && [ "${DESIRED_VERSION}" = "${LATEST_TAG}" ]; then
        log_success "Up to date (latest: ${LATEST_TAG})."
      else
        log_success "Up to date (pinned: ${DESIRED_VERSION}${LATEST_TAG:+, latest: ${LATEST_TAG}})."
      fi
    fi
  elif [ -f ".gitmodules" ] && grep -q "path = ${MAKEFILE_SYSTEM_DIR}" .gitmodules; then
    if [ ! -f "${MAKEFILE_SYSTEM_DIR}/Makefile.universal" ]; then
      log_warn "Submodule is not initialized. Running 'git submodule update'..."
      git submodule update --init --recursive
      log_success "Submodule initialized successfully."
    else
      log_success "Submodule is already initialized."
    fi
  elif git log --grep="git-subtree-dir: ${MAKEFILE_SYSTEM_DIR}" --oneline | grep -q .; then
    log_success "Subtree is present."
  else
    LATEST_TAG="$(umr_fetch_latest_release_tag "${GITHUB_OWNER}" "${GITHUB_REPO}" || true)"
    if [ -z "${LATEST_TAG}" ]; then
      log_warn "Unable to resolve latest release tag from GitHub."
    else
      DESIRED_VERSION="${LATEST_TAG}"
      if [ -f "${MAKEFILE_SYSTEM_DIR}/.version" ]; then
        CURRENT_VERSION="$(cat "${MAKEFILE_SYSTEM_DIR}/.version")"
      else
        CURRENT_VERSION=""
      fi
      log_info "Version status: current=${CURRENT_VERSION:-none}, latest=${DESIRED_VERSION}"
      if [[ "${CURRENT_VERSION}" != "${DESIRED_VERSION}" ]]; then
        DO_UPDATE=1
        if [ -n "${CURRENT_VERSION}" ] && ! umr_is_true "${FORCE_UPDATE}"; then
          if ! umr_prompt_confirm "New release available (${CURRENT_VERSION} → ${DESIRED_VERSION}). Update now?"; then
            log_info "Skipped update by user choice."
            DO_UPDATE=0
          fi
        fi
        if [ "${DO_UPDATE}" -eq 1 ]; then
          TMPDIR_UMR="$(mktemp -d)"; trap 'rm -rf "${TMPDIR_UMR}" >/dev/null 2>&1 || true' EXIT INT TERM
          TARBALL_PATH="${TMPDIR_UMR}/umf.tar.gz"
          if ! umr_download_tarball "${GITHUB_OWNER}" "${GITHUB_REPO}" "${DESIRED_VERSION}" "${TARBALL_PATH}"; then
            log_warn "Failed to download release tarball for ${DESIRED_VERSION}."; exit 1
          fi
          rm -rf "${MAKEFILE_SYSTEM_DIR}" || true
          EXTRACT_DIR="${TMPDIR_UMR}/extract"; mkdir -p "${EXTRACT_DIR}"
          umr_extract_tarball "${TARBALL_PATH}" "${EXTRACT_DIR}" || { log_warn "Extraction failed."; exit 1; }
          ROOT_DIR_NAME="$(umr_tar_first_dir "${TARBALL_PATH}" || true)"
          [ -z "${ROOT_DIR_NAME}" ] && log_warn "Extracted directory not found." && exit 1
          mv "${EXTRACT_DIR}/${ROOT_DIR_NAME}" "${MAKEFILE_SYSTEM_DIR}"
          echo "${DESIRED_VERSION}" > "${MAKEFILE_SYSTEM_DIR}/.version"
          log_success "Updated Makefile system to latest: ${DESIRED_VERSION}."
        else
          log_success "Staying on current version (current: ${CURRENT_VERSION}, latest: ${DESIRED_VERSION})."
        fi
      else
        log_success "Already up to date (latest: ${DESIRED_VERSION})."
      fi
    fi
  fi

  # v2: 로컬 모드에서는 프로젝트 스캐폴딩/생성 작업을 하지 않음
  log_info "Local mode complete. To initialize project files, run './install.sh install'."
  exit 0

else
  # Bootstrap mode (no git repo)
  log_info "Bootstrap mode detected (no git repo)"
  DESIRED_VERSION=""
  if [ -f ".ums-version" ]; then
    DESIRED_VERSION="$(cat .ums-version)"; log_info "Found .ums-version: ${DESIRED_VERSION}"
  else
    DESIRED_VERSION="$(umr_fetch_latest_release_tag "${GITHUB_OWNER}" "${GITHUB_REPO}" || true)"
    if [ -z "${DESIRED_VERSION}" ]; then
      log_warn "Could not resolve latest release via API. Falling back to main branch archive."; DESIRED_VERSION="${MAIN_BRANCH}"
    else
      log_info "Resolved latest release tag: ${DESIRED_VERSION}"
    fi
  fi
  if [ -n "${CLI_VERSION}" ]; then DESIRED_VERSION="${CLI_VERSION}"; log_info "CLI version specified: ${DESIRED_VERSION}"; fi

  if [ -e "${GITHUB_REPO}" ]; then
    current_bootstrap=""; if [ -f "${GITHUB_REPO}/.ums-release-version" ]; then current_bootstrap="$(cat "${GITHUB_REPO}/.ums-release-version")"; elif [ -f "${GITHUB_REPO}/VERSION" ]; then current_bootstrap="$(tr -d '\n\r' < "${GITHUB_REPO}/VERSION")"; fi
    log_warn "Target directory '${GITHUB_REPO}' already exists."; [ -n "${current_bootstrap}" ] && log_info "Current installed release: ${current_bootstrap}"; log_info "Desired release: ${DESIRED_VERSION}"
    if umr_is_true "${FORCE_UPDATE}"; then
      log_info "--force specified: updating in place..."
      TMPDIR_UMR="$(mktemp -d)"; trap 'rm -rf "${TMPDIR_UMR}" >/dev/null 2>&1 || true' EXIT INT TERM
      TARBALL_PATH="${TMPDIR_UMR}/repo.tar.gz"; umr_download_tarball "${GITHUB_OWNER}" "${GITHUB_REPO}" "${DESIRED_VERSION}" "${TARBALL_PATH}" || { log_warn "Download failed"; exit 1; }
      EXTRACT_DIR="${TMPDIR_UMR}/extract"; mkdir -p "${EXTRACT_DIR}"; umr_extract_tarball "${TARBALL_PATH}" "${EXTRACT_DIR}" || { log_warn "Extraction failed"; exit 1; }
      ROOT_DIR_NAME="$(umr_tar_first_dir "${TARBALL_PATH}" || true)"; [ -z "${ROOT_DIR_NAME}" ] && log_warn "Extracted directory not found." && exit 1
      rm -rf "${GITHUB_REPO}" && mv "${EXTRACT_DIR}/${ROOT_DIR_NAME}" "${GITHUB_REPO}"; echo "${DESIRED_VERSION}" > "${GITHUB_REPO}/.ums-release-version" || true; [ -f "${GITHUB_REPO}/.ums-version" ] || echo "${DESIRED_VERSION}" > "${GITHUB_REPO}/.ums-version" || true; log_success "Project updated to '${DESIRED_VERSION}'."; exit 0
    else
      log_warn "Run with --force to overwrite/update the existing directory."; exit 1
    fi
  fi

  TMPDIR_UMR="$(mktemp -d)"; trap 'rm -rf "${TMPDIR_UMR}" >/dev/null 2>&1 || true' EXIT INT TERM
  TARBALL_PATH="${TMPDIR_UMR}/repo.tar.gz"; umr_download_tarball "${GITHUB_OWNER}" "${GITHUB_REPO}" "${DESIRED_VERSION}" "${TARBALL_PATH}" || { log_warn "Failed to download repository release tarball for ${DESIRED_VERSION}."; exit 1; }
  EXTRACT_DIR="${TMPDIR_UMR}/extract"; mkdir -p "${EXTRACT_DIR}"; umr_extract_tarball "${TARBALL_PATH}" "${EXTRACT_DIR}" || { log_warn "Extraction failed."; exit 1; }
  ROOT_DIR_NAME="$(umr_tar_first_dir "${TARBALL_PATH}" || true)"; [ -z "${ROOT_DIR_NAME}" ] && log_warn "Extracted directory not found." && exit 1
  mv "${EXTRACT_DIR}/${ROOT_DIR_NAME}" "${GITHUB_REPO}"; echo "${DESIRED_VERSION}" > "${GITHUB_REPO}/.ums-release-version" || true; [ -f "${GITHUB_REPO}/.ums-version" ] || echo "${DESIRED_VERSION}" > "${GITHUB_REPO}/.ums-version" || true; log_success "Project downloaded to '${GITHUB_REPO}' from release ${DESIRED_VERSION}."

  (
    cd "${GITHUB_REPO}" && log_info "Running installer..."
    if [ -f ./install.sh ]; then
      log_info "Using install.sh (release-aware)"
      bash ./install.sh install || { log_warn "install.sh install failed."; exit 0; }
    elif [ -f ./install.legacy.sh ]; then
      log_info "Using legacy install.sh"
      bash ./install.sh install || { log_warn "install.legacy.sh install failed."; exit 0; }
    else
      log_warn "No installer found. Running scaffold fallback."
      umc_scaffold_project_files "${MAKEFILE_SYSTEM_DIR}"
    fi
  )

  echo ""; log_info "Next steps:"; echo "1. cd ${GITHUB_REPO}"; echo "2. make help"
fi
