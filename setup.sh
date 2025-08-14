#!/usr/bin/env bash
# setup.v2.sh — Bootstrap and make entrypoint (refactored with shared lib)
# 정책 요약 (우선순위):
# 1) --version <ref> (또는 위치 인자 vX / main 등)
# 2) -f/--force  : 명시 버전 없으면 최신으로 강제 (정책/핀/프롬프트 무시)
# 3) UMS_BOOTSTRAP_POLICY : latest | prompt | pin (기본 prompt)
# 4) .ums-version (핀)
# 5) 현재 설치본
#
# - 대화형(tty)에서 UMS_BOOTSTRAP_POLICY=prompt 이고 최신이 다르면 한 번 물어봄(기본 Pinned)
# - 비대화형/CI 에서는 질문 없이 정책/핀에 따름
# - 최신/동의/강제로 버전이 바뀌면 .ums-version 도 동기화(UPDATE_PIN=true)

set -euo pipefail

# --- Project settings ---
GITHUB_OWNER="jinwoo-j"
GITHUB_REPO="universal-makefile"
MAIN_BRANCH="main"
MAKEFILE_SYSTEM_DIR="${GITHUB_REPO}"

# Bootstrap version selection policy: pin | prompt | latest
UMS_BOOTSTRAP_POLICY="${UMS_BOOTSTRAP_POLICY:-prompt}"
# Source selection: bootstrap | submodule | subtree | auto (default: bootstrap)
SOURCE_MODE="${UMS_SOURCE_MODE:-bootstrap}"

# Colors
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
  RED=$(tput setaf 1); GREEN=$(tput setaf 2); YELLOW=$(tput setaf 3); BLUE=$(tput setaf 4); RESET=$(tput sgr0)
else
  RED=""; GREEN=""; YELLOW=""; BLUE=""; RESET=""
fi
log_info()    { echo -e "${BLUE}ℹ️  $1${RESET}"; }
log_success() { echo -e "${GREEN}✅ $1${RESET}"; }
log_warn()    { echo -e "${YELLOW}⚠️  $1${RESET}"; }
log_debug()   { if [ "${DEBUG:-false}" = "true" ]; then echo -e "${YELLOW}[debug] $1${RESET}"; fi; }
enable_xtrace_if_debug() { if [ "${DEBUG:-false}" = "true" ]; then set -x; log_debug "xtrace enabled"; fi }

# Retry defaults (env-overridable)
CURL_RETRY_MAX=${CURL_RETRY_MAX:-3}
CURL_RETRY_DELAY_SEC=${CURL_RETRY_DELAY_SEC:-2}

FORCE_UPDATE=${FORCE_UPDATE:-false}
CLI_VERSION=""
DEBUG=${DEBUG:-false}
# Allow running local mode explicitly (default false). Env override: UMS_SETUP_ALLOW_LOCAL=true
ALLOW_LOCAL="${UMS_SETUP_ALLOW_LOCAL:-false}"

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

# --- Fallbacks for release lib ---
if ! declare -F umr_is_true >/dev/null 2>&1; then
  umr_is_true() {
    case "${1:-}" in true|1|yes|on|Y|y) return 0 ;; *) return 1 ;; esac
  }
fi
if ! declare -F umr_prompt_confirm >/dev/null 2>&1; then
  umr_prompt_confirm() {
    local msg="$1" reply
    if [ -t 0 ]; then
      read -r -p "${msg} [y/N]: " reply || true
      case "$reply" in [yY][eE][sS]|[yY]) return 0 ;; *) return 1 ;; esac
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
      echo "${expected}  ${file_path}" | sha256sum -c --status; return $?
    elif command -v shasum >/dev/null 2>&1; then
      echo "${expected}  ${file_path}" | shasum -a 256 -c --status; return $?
    else
      return 3
    fi
  }
fi
if ! declare -F umr_fetch_latest_release_tag >/dev/null 2>&1; then
  umr_fetch_latest_release_tag() {
    local owner="$1" repo="$2"
    local api_url="https://api.github.com/repos/${owner}/${repo}/releases/latest"
    local tag; local auth=()
    [[ -n "${GITHUB_TOKEN:-}" ]] && auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
    tag=$(curl -fsSL "${auth[@]}" "$api_url" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^\"]*\)".*/\1/p' | head -n1 || true)
    if [ -n "$tag" ]; then echo "$tag"; return 0; fi
    if command -v git >/dev/null 2>&1; then
      git ls-remote --tags --refs "https://github.com/${owner}/${repo}.git" 2>/dev/null \
        | awk '{print $2}' | sed 's@refs/tags/@@' | sort -Vr | head -n1
    fi
  }
fi
if ! declare -F umr_build_tarball_urls >/dev/null 2>&1; then
  umr_build_tarball_urls() {
    local owner="$1" repo="$2" ref="$3"
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
      echo "https://api.github.com/repos/${owner}/${repo}/tarball/${ref}"
      case "$ref" in
        main|master|develop|*-branch|*-snapshot) echo "https://codeload.github.com/${owner}/${repo}/tar.gz/refs/heads/${ref}" ;;
        *) echo "https://codeload.github.com/${owner}/${repo}/tar.gz/refs/tags/${ref}" ;;
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
    local url="$1" out="$2"; shift 2
    local -a headers=("$@"); local -a curl_headers=()
    for h in "${headers[@]}"; do curl_headers+=( -H "$h" ); done
    for attempt in $(seq 1 ${CURL_RETRY_MAX}); do
      local _had_xtrace=0; case "$-" in *x*) _had_xtrace=1; set +x ;; esac
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
    local owner="$1" repo="$2" ref="$3" out_tar="$4"
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
      local repo_code
      repo_code=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer ${GITHUB_TOKEN}" "https://api.github.com/repos/${owner}/${repo}") || repo_code="000"
      if [[ "$repo_code" != "200" ]]; then
        log_warn "GitHub token may not have access to ${owner}/${repo} (HTTP ${repo_code}). Falling back if possible."
      fi
    fi
    local -a urls; readarray -t urls < <(umr_build_tarball_urls "$owner" "$repo" "$ref")
    local primary="${urls[0]}"; local mirror="${urls[1]:-}"
    local -a headers=()
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
      headers+=("Authorization: Bearer ${GITHUB_TOKEN}" "X-GitHub-Api-Version: 2022-11-28" "Accept: application/vnd.github+json")
    fi
    umr_download_with_retries "$primary" "$out_tar" "${headers[@]}" || {
      [[ -n "$mirror" ]] && umr_download_with_retries "$mirror" "$out_tar" "${headers[@]}"
    }
  }
fi
if ! declare -F umr_tar_first_dir >/dev/null 2>&1; then
  umr_tar_first_dir() { local tarfile="$1"; tar -tzf "$tarfile" >/dev/null 2>&1 || return 2; tar -tzf "$tarfile" 2>/dev/null | head -n1 | cut -d/ -f1; }
fi
if ! declare -F umr_extract_tarball >/dev/null 2>&1; then
  umr_extract_tarball() { local tarfile="$1" dest="$2"; mkdir -p "$dest" && tar -xzf "$tarfile" -C "$dest" 2>/dev/null; }
fi

# --- Fallbacks for scaffold lib ---
if ! declare -F umc_scaffold_project_files >/dev/null 2>&1; then umc_scaffold_project_files() { :; }; fi
if ! declare -F umc_create_main_makefile   >/dev/null 2>&1; then umc_create_main_makefile()   { :; }; fi
if ! declare -F umc_create_project_config  >/dev/null 2>&1; then umc_create_project_config()  { :; }; fi
if ! declare -F umc_update_gitignore       >/dev/null 2>&1; then umc_update_gitignore()       { :; }; fi
if ! declare -F umc_create_environments    >/dev/null 2>&1; then umc_create_environments()    { :; }; fi
if ! declare -F umc_create_sample_compose  >/dev/null 2>&1; then umc_create_sample_compose()  { :; }; fi

# Thin wrappers
is_true() { umr_is_true "$@"; }
prompt_confirm() { umr_prompt_confirm "$@"; }

parse_cli_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force|-f) FORCE_UPDATE=true; shift ;;
      --debug|-d) DEBUG=true; shift ;;
      --mode|--source)
        shift || true
        SOURCE_MODE="${1:-}"
        if [ -z "${SOURCE_MODE}" ]; then echo "--mode requires a value (bootstrap|submodule|subtree|auto)" >&2; exit 2; fi
        case "${SOURCE_MODE}" in bootstrap|submodule|subtree|auto) : ;; *) echo "Invalid --mode: ${SOURCE_MODE}" >&2; exit 2 ;; esac
        shift ;;
      --allow-local) ALLOW_LOCAL=true; shift ;;
      --version|-v)
        shift || true
        CLI_VERSION="${1:-}"
        if [ -z "${CLI_VERSION}" ]; then echo "--version requires a value" >&2; exit 2; fi
        shift ;;
      --) shift; break ;;
      v[0-9]*|main|master|develop) CLI_VERSION="$1"; shift ;;  # positional version
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

# --- Entry ---
parse_cli_args "$@"
if [ "${DEBUG}" = "true" ]; then
  log_info "[debug] flags: FORCE_UPDATE=${FORCE_UPDATE} DEBUG=${DEBUG} CLI_VERSION=${CLI_VERSION}"
  log_info "[debug] context: PWD=$(pwd) USER=$(id -un 2>/dev/null || whoami) SHELL=${SHELL:-n/a}"
  log_info "[debug] paths: MAKEFILE_SYSTEM_DIR=${MAKEFILE_SYSTEM_DIR} GITHUB_REPO=${GITHUB_REPO}"
  log_info "[debug] source: SOURCE_MODE=${SOURCE_MODE}"
fi

# Hard guard: prevent running inside UMF system directory itself
if [[ -f "makefiles/core.mk" ]] && [[ "$(basename "${PWD}")" = "${GITHUB_REPO}" ]]; then
  log_warn "Detected UMF system directory (${GITHUB_REPO}). Use install.sh for maintenance."
  exit 1
fi

case "${SOURCE_MODE}" in
  bootstrap)
    log_info "Bootstrap mode detected (forced)"
    ;;
  submodule)
    if [ -f ".gitmodules" ] && grep -q "path = ${MAKEFILE_SYSTEM_DIR}" .gitmodules; then
      if [ ! -f "${MAKEFILE_SYSTEM_DIR}/Makefile.universal" ]; then
        log_warn "Submodule is not initialized. Running 'git submodule update'..."
        git submodule update --init --recursive
        log_success "Submodule initialized successfully."
      else
        log_success "Submodule is already initialized."
      fi
      log_info "Local mode complete. To initialize project files, run './install.sh install'."
      exit 0
    else
      log_warn "Submodule config not found for path ${MAKEFILE_SYSTEM_DIR}. Falling back to bootstrap."
      SOURCE_MODE="bootstrap"
    fi
    ;;
  subtree)
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
      && git log --grep="git-subtree-dir: ${MAKEFILE_SYSTEM_DIR}" --oneline 2>/dev/null | grep -q .; then
      log_success "Subtree is present."
      log_info "Local mode complete. To initialize project files, run './install.sh install'."
      exit 0
    else
      log_warn "Subtree not detected or not a git repo. Falling back to bootstrap."
      SOURCE_MODE="bootstrap"
    fi
    ;;
  auto)
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      if [ -f ".gitmodules" ] && grep -q "path = ${MAKEFILE_SYSTEM_DIR}" .gitmodules; then
        if [ ! -f "${MAKEFILE_SYSTEM_DIR}/Makefile.universal" ]; then
          log_warn "Submodule is not initialized. Running 'git submodule update'..."
          git submodule update --init --recursive
          log_success "Submodule initialized successfully."
        else
          log_success "Submodule is already initialized."
        fi
        log_info "Local mode complete. To initialize project files, run './install.sh install'."
        exit 0
      elif git log --grep="git-subtree-dir: ${MAKEFILE_SYSTEM_DIR}" --oneline 2>/dev/null | grep -q .; then
        log_success "Subtree is present."
        log_info "Local mode complete. To initialize project files, run './install.sh install'."
        exit 0
      fi
    fi
    SOURCE_MODE="bootstrap"
    ;;
  *) : ;;
esac

  # -------------------------
  # Bootstrap (default path)
  # -------------------------
  log_info "Bootstrap mode detected (${SOURCE_MODE} => bootstrap)"
  DESIRED_VERSION=""
  if [ -f ".ums-version" ]; then
    DESIRED_VERSION="$(cat .ums-version)"; log_info "Found .ums-version: ${DESIRED_VERSION}"
  else
    DESIRED_VERSION="$(umr_fetch_latest_release_tag "${GITHUB_OWNER}" "${GITHUB_REPO}" || true)"
    if [ -z "${DESIRED_VERSION}" ]; then
      log_warn "Could not resolve latest release via API. Falling back to main branch archive."
      DESIRED_VERSION="${MAIN_BRANCH}"
    else
      log_info "Resolved latest release tag: ${DESIRED_VERSION}"
    fi
  fi
  if [ -n "${CLI_VERSION}" ]; then DESIRED_VERSION="${CLI_VERSION}"; log_info "CLI version specified: ${DESIRED_VERSION}"; fi

  LATEST_TAG="$(umr_fetch_latest_release_tag "${GITHUB_OWNER}" "${GITHUB_REPO}" || true)"
  if [ -n "${LATEST_TAG}" ]; then
    log_info "Latest available release: ${LATEST_TAG}"
    if [ -f .ums-version ] && [ "${DESIRED_VERSION}" != "${LATEST_TAG}" ]; then
      log_warn "Pinned version differs from latest (pinned: ${DESIRED_VERSION}, latest: ${LATEST_TAG})"
    fi
  fi

  UPDATE_PIN=false

  if umr_is_true "${FORCE_UPDATE}" && [ -z "${CLI_VERSION}" ] && [ -n "${LATEST_TAG}" ]; then
    if [ "${DESIRED_VERSION}" != "${LATEST_TAG}" ]; then
      log_info "--force specified: overriding desired (${DESIRED_VERSION}) -> ${LATEST_TAG}"
      DESIRED_VERSION="${LATEST_TAG}"
      UPDATE_PIN=true
    else
      log_info "--force specified: reinstalling latest ${LATEST_TAG}"
    fi
  fi

  # 정책 적용: FORCE가 아닐 때만 프롬프트/정책 수행
  if ! umr_is_true "${FORCE_UPDATE}" && [ -z "${CLI_VERSION}" ] && [ -n "${LATEST_TAG}" ] && [ "${DESIRED_VERSION}" != "${LATEST_TAG}" ]; then
    case "${UMS_BOOTSTRAP_POLICY}" in
      latest)
        log_info "Policy=latest: overriding pin (${DESIRED_VERSION}) -> ${LATEST_TAG}"
        DESIRED_VERSION="${LATEST_TAG}"; UPDATE_PIN=true ;;
      prompt)
        if [ -t 0 ]; then
          echo ""; echo "A newer release is available."
          echo "  pinned : ${DESIRED_VERSION}"
          echo "  latest : ${LATEST_TAG}"
          read -r -p "Choose [P]inned / [L]atest / [C]ustom / [S]kip (default P): " ans
          USER_VERSION_CHOICE_MADE=true
          case "${ans}" in
            [lL]*) DESIRED_VERSION="${LATEST_TAG}"; UPDATE_PIN=true ;;
            [cC]*) read -r -p "Enter tag/branch: " custom; if [ -n "$custom" ]; then DESIRED_VERSION="$custom"; UPDATE_PIN=true; fi ;;
            [sS]*) log_info "Skipped by user choice."; exit 1 ;;
            *)     : ;; # keep pinned
          esac
        else
          log_info "Non-interactive: sticking to pinned ${DESIRED_VERSION} (set UMS_BOOTSTRAP_POLICY=latest to override)."
        fi ;;
      pin|*) log_info "Pinned ${DESIRED_VERSION}; newer exists (${LATEST_TAG}). Use -f or UMS_BOOTSTRAP_POLICY=latest to override." ;;
    esac
  fi

  if [ -e "${GITHUB_REPO}" ]; then
    current_bootstrap=""
    if [ -f ".ums-release-version" ]; then current_bootstrap="$(cat ".ums-release-version")"
    elif [ -f "${GITHUB_REPO}/VERSION" ]; then current_bootstrap="$(tr -d '\n\r' < "${GITHUB_REPO}/VERSION")"; fi
    log_warn "Target directory '${GITHUB_REPO}' already exists."
    [ -n "${current_bootstrap}" ] && log_info "Current installed release: ${current_bootstrap}"
    log_info "Desired release: ${DESIRED_VERSION}"

    # 이미 원하는 버전과 동일 & 강제 아님 → 최신이 있고 policy=prompt 이면 제안
    if [ -n "${current_bootstrap}" ] && [ "${current_bootstrap}" = "${DESIRED_VERSION}" ] && ! umr_is_true "${FORCE_UPDATE}"; then
      if [ -n "${LATEST_TAG}" ] && [ "${LATEST_TAG}" != "${DESIRED_VERSION}" ] && [ "${UMS_BOOTSTRAP_POLICY}" = "prompt" ] && [ -t 0 ]  && [ "${USER_VERSION_CHOICE_MADE}" != "true" ]; then
        if umr_prompt_confirm "A newer release is available (${DESIRED_VERSION} → ${LATEST_TAG}). Update now?"; then
          DESIRED_VERSION="${LATEST_TAG}"; UPDATE_PIN=true
        else
          log_success "Pinned version is installed (installed: ${current_bootstrap}). Newer release available: ${LATEST_TAG}"
          exit 0
        fi
      else
        log_success "Already up to date (installed: ${current_bootstrap})."; exit 0
      fi
    fi

    # 업데이트 실행 여부
    DO_UPDATE=false
    if umr_is_true "${FORCE_UPDATE}"; then
      DO_UPDATE=true; log_info "--force specified: updating in place..."
    else
      if umr_prompt_confirm "New release available (${current_bootstrap:-none} → ${DESIRED_VERSION}). Update now?"; then
        DO_UPDATE=true
      else
        log_info "Skipped update by user choice."; exit 1
      fi
    fi

    if umr_is_true "${DO_UPDATE}"; then
      TMPDIR_UMR="$(mktemp -d)"; trap 'rm -rf "${TMPDIR_UMR}" >/dev/null 2>&1 || true' EXIT INT TERM
      TARBALL_PATH="${TMPDIR_UMR}/repo.tar.gz"
      umr_download_tarball "${GITHUB_OWNER}" "${GITHUB_REPO}" "${DESIRED_VERSION}" "${TARBALL_PATH}" || { log_warn "Download failed"; exit 1; }
      EXTRACT_DIR="${TMPDIR_UMR}/extract"; mkdir -p "${EXTRACT_DIR}"
      umr_extract_tarball "${TARBALL_PATH}" "${EXTRACT_DIR}" || { log_warn "Extraction failed"; exit 1; }
      ROOT_DIR_NAME="$(umr_tar_first_dir "${TARBALL_PATH}" || true)"; [ -z "${ROOT_DIR_NAME}" ] && log_warn "Extracted directory not found." && exit 1
      rm -rf "${GITHUB_REPO}" && mv "${EXTRACT_DIR}/${ROOT_DIR_NAME}" "${GITHUB_REPO}"
      echo "${DESIRED_VERSION}" > .ums-release-version || true
      if [ "${UPDATE_PIN}" = "true" ]; then echo "${DESIRED_VERSION}" > .ums-version || true; else [ -f ".ums-version" ] || echo "${DESIRED_VERSION}" > .ums-version || true; fi
      log_debug "bootstrap updated: wrote $(pwd)/.ums-release-version and ensured $(pwd)/.ums-version"
      log_success "Project updated to '${DESIRED_VERSION}'."
      exit 0
    fi
  fi

  # Fresh bootstrap
  TMPDIR_UMR="$(mktemp -d)"; trap 'rm -rf "${TMPDIR_UMR}" >/dev/null 2>&1 || true' EXIT INT TERM
  TARBALL_PATH="${TMPDIR_UMR}/repo.tar.gz"
  umr_download_tarball "${GITHUB_OWNER}" "${GITHUB_REPO}" "${DESIRED_VERSION}" "${TARBALL_PATH}" || { log_warn "Failed to download repository release tarball for ${DESIRED_VERSION}."; exit 1; }
  EXTRACT_DIR="${TMPDIR_UMR}/extract"; mkdir -p "${EXTRACT_DIR}"
  umr_extract_tarball "${TARBALL_PATH}" "${EXTRACT_DIR}" || { log_warn "Extraction failed."; exit 1; }
  ROOT_DIR_NAME="$(umr_tar_first_dir "${TARBALL_PATH}" || true)"; [ -z "${ROOT_DIR_NAME}" ] && log_warn "Extracted directory not found." && exit 1
  mv "${EXTRACT_DIR}/${ROOT_DIR_NAME}" "${GITHUB_REPO}"
  echo "${DESIRED_VERSION}" > .ums-release-version || true
  if [ "${UPDATE_PIN}" = "true" ]; then echo "${DESIRED_VERSION}" > .ums-version || true; else [ -f ".ums-version" ] || echo "${DESIRED_VERSION}" > .ums-version || true; fi
  log_debug "bootstrap created: $(pwd)/.ums-release-version and $(pwd)/.ums-version"
  log_success "Project downloaded to '${GITHUB_REPO}' from release ${DESIRED_VERSION}."

  (
    log_info "Running installer..."
    if [ -f "${GITHUB_REPO}/install.sh" ]; then
      log_info "Using install.sh (release-aware)"
      # Forward debug flag to installer so DEBUG_MODE propagates to lib_installer/lib_scaffold
      if [ "${DEBUG}" = "true" ]; then
        MAKEFILE_DIR="${GITHUB_REPO}" bash "${GITHUB_REPO}/install.sh" init --debug || { log_warn "install.sh init failed."; exit 0; }
      else
        MAKEFILE_DIR="${GITHUB_REPO}" bash "${GITHUB_REPO}/install.sh" init || { log_warn "install.sh init failed."; exit 0; }
      fi
    elif [ -f "${GITHUB_REPO}/install.legacy.sh" ]; then
      log_info "Using legacy install.sh"
      if [ "${DEBUG}" = "true" ]; then
        MAKEFILE_DIR="${GITHUB_REPO}" bash "${GITHUB_REPO}/install.legacy.sh" install --debug || { log_warn "install.legacy.sh install failed."; exit 0; }
      else
        MAKEFILE_DIR="${GITHUB_REPO}" bash "${GITHUB_REPO}/install.legacy.sh" install || { log_warn "install.legacy.sh install failed."; exit 0; }
      fi
    else
      log_warn "No installer found. Running scaffold fallback."
      umc_scaffold_project_files "${MAKEFILE_SYSTEM_DIR}"
    fi
  )

  echo ""; log_info "Next steps:"; echo "1. cd ${GITHUB_REPO}"; echo "2. make help"
 
