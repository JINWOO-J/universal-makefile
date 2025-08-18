#!/usr/bin/env bash
# scripts/lib_installer.sh — Core installer logic as a reusable library
# Exposes: umf_install_main "$@"

set -euo pipefail

# ---- bash 4.2 호환 보강 ----
# readarray가 없으면 mapfile로 폴백
if ! declare -F readarray >/dev/null 2>&1 && declare -F mapfile >/dev/null 2>&1; then
  readarray() { mapfile "$@"; }
fi

: "${TMPDIR:=/tmp}"
TMPDIR="${TMPDIR%/}"
UMF_TMP_DIR="$(mktemp -d "${TMPDIR}/umf-install.XXXXXX")"
UMS_INSTALL_TYPE_FILE=".ums-install-type"
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

GITHUB_OWNER="jinwoo-j"
GITHUB_REPO="universal-makefile"
MAKEFILE_DIR="${GITHUB_REPO}"
GITHUB_REPO_SLUG="${GITHUB_OWNER}/${GITHUB_REPO}"
MAIN_BRANCH="main"

UMS_INSTALL_TYPE_FILE=".ums-install-type"

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
enable_xtrace_if_debug() { if [[ "${DEBUG_MODE:-false}" == "true" ]]; then set -x; log_debug "xtrace enabled"; fi; }

# --- Source shared libs (optional) ---
_umr_try_source() {
  local cands=("./scripts/lib_release.sh" "${MAKEFILE_DIR}/scripts/lib_release.sh")
  local f
  for f in "${cands[@]}"; do
    if [[ -f "$f" ]]; then
      log_info "[lib] sourcing: $f"
      . "$f"
      return 0
    fi
  done
  log_warn "[lib] lib_release.sh not found; using internal fallbacks"
  return 1
}
_umc_try_source() {
  local cands=("./scripts/lib_scaffold.sh" "${MAKEFILE_DIR}/scripts/lib_scaffold.sh")
  local f
  for f in "${cands[@]}"; do
    if [[ -f "$f" ]]; then
      log_info "[lib] sourcing: $f"
      . "$f"
      return 0
    fi
  done
  log_warn "[lib] lib_scaffold.sh not found; using internal scaffold fallbacks"
  return 1
}
_umr_try_source || true
_umc_try_source || true

# ---- Fallbacks (lib_release.sh 미존재 시) ----
type umr_verify_sha256 >/dev/null 2>&1 || umr_verify_sha256() {
  local file_path="$1" expected="$2"
  if [[ -z "${expected}" ]]; then return 2; fi
  if command -v sha256sum >/dev/null 2>&1; then
    echo "${expected}  ${file_path}" | sha256sum -c --status; return $?
  fi
  if command -v shasum >/dev/null 2>&1; then
    echo "${expected}  ${file_path}" | shasum -a 256 -c --status; return $?
  fi
  return 3
}

# Latest release tag fetcher (token-aware) — 빈 배열 가드 적용
type umr_fetch_latest_release_tag >/dev/null 2>&1 || umr_fetch_latest_release_tag() {
  local owner="$1" repo="$2"
  local api_url="https://api.github.com/repos/${owner}/${repo}/releases/latest"
  local tag=""
  local -a auth=()
  [[ -n "${GITHUB_TOKEN:-}" ]] && auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")

  if command -v curl >/dev/null 2>&1; then
    tag=$(
      curl -fsSL \
        ${auth[@]+"${auth[@]}"} \
        "$api_url" \
      | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
      | head -n1 || true
    )
  elif command -v wget >/dev/null 2>&1; then
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
      tag=$(wget -qO- --header="Authorization: Bearer ${GITHUB_TOKEN}" "$api_url" \
        | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1 || true)
    else
      tag=$(wget -qO- "$api_url" \
        | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1 || true)
    fi
  fi

  if [[ -n "$tag" ]]; then
    echo "$tag"; return 0
  fi

  if command -v git >/dev/null 2>&1; then
    git ls-remote --tags --refs "https://github.com/${owner}/${repo}.git" 2>/dev/null \
      | awk '{print $2}' | sed 's@refs/tags/@@' | sort -Vr | head -n1
    return $?
  fi
  return 1
}

# Tarball URL builder
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

# Robust downloader with retries — 헤더 배열 가드
type umr_download_with_retries >/dev/null 2>&1 || umr_download_with_retries() {
  local url="$1" out="$2"; shift 2

  if command -v curl >/dev/null 2>&1; then
    local -a cmd=( curl -fSL --connect-timeout 10 --max-time 300 )
    while (($#)); do cmd+=( -H "$1" ); shift; done
    cmd+=( -o "$out" )

    for attempt in $(seq 1 ${CURL_RETRY_MAX}); do
      local _had_xtrace=0; case "$-" in *x*) _had_xtrace=1; set +x ;; esac
      if "${cmd[@]}" "$url"; then
        [[ -s "$out" ]] && { [[ $_had_xtrace -eq 1 ]] && set -x; return 0; }
      fi
      [[ $_had_xtrace -eq 1 ]] && set -x
      # 지수 백오프 (Bash 4.2 OK), 실패시 고정 대기
      sleep $((CURL_RETRY_DELAY_SEC * (2 ** (attempt - 1)))) || sleep "${CURL_RETRY_DELAY_SEC}"
    done
    return 1

  elif command -v wget >/dev/null 2>&1; then
    for attempt in $(seq 1 ${CURL_RETRY_MAX}); do
      local -a wget_cmd=( wget -q -O "$out" )
      while (($#)); do wget_cmd+=( --header "$1" ); shift; done
      if "${wget_cmd[@]}" "$url"; then
        [[ -s "$out" ]] && return 0
      fi
      sleep $((CURL_RETRY_DELAY_SEC * (2 ** (attempt - 1)))) || sleep "${CURL_RETRY_DELAY_SEC}"
    done
    return 1

  else
    return 127
  fi
}

# Tarball downloader — headers/urls 배열 가드
type umr_download_tarball >/dev/null 2>&1 || umr_download_tarball() {
  local owner="$1" repo="$2" ref="$3" out_tar="$4"

  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    local repo_code
    repo_code=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer ${GITHUB_TOKEN}" "https://api.github.com/repos/${owner}/${repo}") || repo_code="000"
    if [[ "$repo_code" != "200" ]]; then
      log_warn "GitHub token may not have access to ${owner}/${repo} (HTTP ${repo_code}). Falling back if possible."
    fi
  fi

  local -a urls=()
  # readarray는 위에서 mapfile로 폴백됨
  readarray -t urls < <(umr_build_tarball_urls "$owner" "$repo" "$ref")
  local primary="${urls[0]:-}"; local mirror="${urls[1]:-}"

  local -a headers=()
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    headers+=("Authorization: Bearer ${GITHUB_TOKEN}" "X-GitHub-Api-Version: 2022-11-28" "Accept: application/vnd.github+json")
  fi

  umr_download_with_retries "$primary" "$out_tar" \
    ${headers[@]+"${headers[@]}"} \
  || { [[ -n "$mirror" ]] && umr_download_with_retries "$mirror" "$out_tar" \
       ${headers[@]+"${headers[@]}"}; }
}

type umr_tar_first_dir   >/dev/null 2>&1 || umr_tar_first_dir()   { local tarfile="$1"; tar -tzf "$tarfile" >/dev/null 2>&1 || return 2; tar -tzf "$tarfile" 2>/dev/null | head -n1 | cut -d/ -f1; }
type umr_extract_tarball >/dev/null 2>&1 || umr_extract_tarball() { local tarfile="$1" dest="$2"; mkdir -p "$dest" && tar -xzf "$tarfile" -C "$dest" 2>/dev/null; }

# ---- 사용법/공통 파서 ----
usage_installer() {
  cat <<EOF
Universal Makefile System Installer

Usage: install.sh <command> [options]
...
EOF
}

resolve_flag() {
  local env_var_name=$1 long_flag=$2 short_flag=$3; shift 3
  local all_args=( "$@" )
  for arg in "${all_args[@]:-}"; do
    if [[ "$arg" == "$long_flag" || ( -n "$short_flag" && "$arg" == "$short_flag" ) ]]; then
      echo "true"; return
    fi
  done
  # 환경변수 존재 유무 체크는 set -u에서 안전하게
  local env_val=""
  if eval "[[ \${$env_var_name+x} ]]"; then
    eval "env_val=\"\${$env_var_name}\""
    [[ "${env_val^^}" == "TRUE" ]] && { echo "true"; return; }
    echo "false"; return
  fi
  echo "false"
}

parse_common_args_installer() {
  FORCE_INSTALL=$(resolve_flag "FORCE" "--force" "" "$@")
  DRY_RUN=$(resolve_flag "DRY_RUN" "--dry-run" "" "$@")
  BACKUP=$(resolve_flag "BACKUP" "--backup" "" "$@")
  DEBUG_MODE=$(resolve_flag "DEBUG" "--debug" "-d" "$@")
  YES=$(resolve_flag "YES" "--yes" "-y" "$@")
  if [[ "${DEBUG_MODE}" == "true" ]]; then
    log_info "[debug] flags: FORCE_INSTALL=${FORCE_INSTALL} DRY_RUN=${DRY_RUN} BACKUP=${BACKUP} YES=${YES}"
  fi
}

print_debug_context() {
  [[ "${DEBUG_MODE}" == "true" ]] || return 0
  log_info "[debug] context: PWD=$(pwd) USER=$(id -un 2>/dev/null || whoami) SHELL=${SHELL:-n/a}"
  log_info "[debug] repo: GITHUB_OWNER=${GITHUB_OWNER} GITHUB_REPO=${GITHUB_REPO} REPO_URL=${REPO_URL}"
  log_info "[debug] paths: MAKEFILE_DIR=${MAKEFILE_DIR} SCRIPT_DIR=${SCRIPT_DIR} TMPDIR=${TMPDIR}"
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    log_info "[debug] git: repo-root=$(git rev-parse --show-toplevel 2>/dev/null) branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
  else
    log_info "[debug] git: not a repo"
  fi
}

SCAFFOLD_ONLY=false
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
      --scaffold-only|--init-only|--no-download) SCAFFOLD_ONLY=true; shift ;;
      --existing-project) EXISTING_PROJECT=true; shift ;;
      --help|-h)    usage_installer; return 2 ;;
      *)            remaining_args+=("$1"); shift ;;
    esac
  done
  parse_common_args_installer "${remaining_args[@]:-}"
}

parse_uninstall_args_installer() {
  local remaining_args=()
  while [[ $# -gt 0 ]]; do
    case $1 in
      --remove-pins) REMOVE_PIN_FILES=true; shift ;;
      --*)          remaining_args+=("$1"); shift ;;
      *)            remaining_args+=("$1"); shift ;;
    esac
  done
  parse_common_args_installer "${remaining_args[@]:-}"
}

parse_update_args_installer() {
  local remaining_args=()
  while [[ $# -gt 0 ]]; do
    case $1 in
      --version|-v) DESIRED_REF="$2"; shift 2 ;;
      --ref)        DESIRED_REF="$2"; shift 2 ;;
      --*)          remaining_args+=("$1"); shift ;;
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
  if [[ "${DEBUG_MODE}" == "true" ]]; then
    log_info "[debug] binaries:"
    command -v bash >/dev/null 2>&1 && log_info "  bash=$(bash --version | head -n1)"
    command -v make >/dev/null 2>&1 && log_info "  make=$(make --version 2>/dev/null | head -n1)"
    command -v git  >/dev/null 2>&1 && log_info "  git=$(git --version 2>/dev/null)"
    command -v tar  >/dev/null 2>&1 && log_info "  tar=$(tar --version 2>/dev/null | head -n1)"
    if command -v curl >/dev/null 2>&1; then log_info "  curl=$(curl --version | head -n1)"; fi
    if command -v wget >/dev/null 2>&1; then log_info "  wget=$(wget --version 2>/dev/null | head -n1)"; fi
    log_info "[debug] env: GITHUB_TOKEN=${GITHUB_TOKEN:+<set>}"
  fi
}

install_submodule() {
  log_info "Installing as git submodule..."
  if [[ "$FORCE_INSTALL" == true && -d "$MAKEFILE_DIR" ]]; then
    log_info "Removing existing submodule..."
    git submodule deinit -f "$MAKEFILE_DIR" || true
    git rm -f "$MAKEFILE_DIR" || true
    rm -rf ".git/modules/$MAKEFILE_DIR" "$MAKEFILE_DIR"
  fi
  if ! git submodule add "$REPO_URL" "$MAKEFILE_DIR"; then
    if git config --file .gitmodules --get "submodule.$MAKEFILE_DIR.url" >/dev/null 2>&1; then
      log_info "Submodule already exists, continuing..."
    else
      log_error "Failed to add submodule"; exit 1
    fi
  fi
  git submodule update --init --recursive
  echo "submodule" > "${UMS_INSTALL_TYPE_FILE}"
  log_success "Submodule installation completed"
}

install_copy() {
  log_info "Installing by copying files..."
  local temp_dir; temp_dir="$(mktemp -d "${UMF_TMP_DIR}/copy.XXXXXX")"
  local source_dir
  if [[ -f "$SCRIPT_DIR/makefiles/core.mk" ]]; then
    log_info "Using local repository files"; source_dir="$SCRIPT_DIR"
  else
    log_info "Cloning from $REPO_URL"
    git clone "$REPO_URL" "$temp_dir/universal-makefile"
    source_dir="$temp_dir/universal-makefile"
  fi
  [[ "$FORCE_INSTALL" == true || ! -d "makefiles" ]] && cp -r "$source_dir/makefiles" .
  [[ "$FORCE_INSTALL" == true || ! -d "scripts"   ]] && cp -r "$source_dir/scripts" . 2>/dev/null || true
  [[ "$FORCE_INSTALL" == true || ! -d "templates" ]] && cp -r "$source_dir/templates" . 2>/dev/null || true
  [[ -f "$source_dir/VERSION" ]] && cp "$source_dir/VERSION" .
  echo "copy" > "${UMS_INSTALL_TYPE_FILE}"
  log_success "Copy installation completed"
}

install_subtree() {
  log_info "Installing via git subtree..."
  command -v git >/dev/null 2>&1 || { log_error "Git is required for subtree installation"; exit 1; }
  git rev-parse --git-dir >/dev/null 2>&1 || { log_error "Not in a git repository. Initialize git first or use --copy"; exit 1; }

  local prefix_dir="$MAKEFILE_DIR" remote_name="universal-makefile-remote"
  if ! git remote get-url "$remote_name" >/dev/null 2>&1; then
    git remote add "$remote_name" "$REPO_URL"; log_info "Added remote '$remote_name' -> $REPO_URL"
  fi
  local remote_head
  remote_head=$(git ls-remote --symref "$remote_name" HEAD 2>/dev/null | sed -n 's@^ref: refs/heads/\([^\t\n\r ]*\)[\t ]*HEAD@\1@p' | head -n1)
  if [[ -z "$remote_head" ]]; then
    if git ls-remote --exit-code --heads "$remote_name" main   >/dev/null 2>&1; then remote_head=main
    elif git ls-remote --exit-code --heads "$remote_name" master >/dev/null 2>&1; then remote_head=master
    else remote_head="$MAIN_BRANCH"; fi
  fi
  log_info "Using remote default branch: ${remote_head}"
  git fetch "$remote_name" "$remote_head" --tags --quiet || git fetch "$remote_name" --tags --quiet

  if [[ -d "$prefix_dir" ]]; then
    log_warn "Directory '$prefix_dir' already exists. Attempting to merge updates..."
    git subtree pull --prefix="$prefix_dir" "$remote_name" "$remote_head" --squash \
      || { log_error "git subtree pull failed"; exit 1; }
    log_success "Subtree updated at '$prefix_dir'"
  else
    git subtree add --prefix="$prefix_dir" "$remote_name" "$remote_head" --squash \
      || { log_error "git subtree add failed"; exit 1; }
    log_success "Subtree installed at '$prefix_dir'"
  fi
  echo "subtree" > "${UMS_INSTALL_TYPE_FILE}"
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
      log_warn "Could not resolve latest release via API. Falling back to branch snapshot: ${MAIN_BRANCH}"
      desired="${MAIN_BRANCH}"
    else
      log_info "Resolved latest release tag: ${desired}"
    fi
  fi

  local workdir="${UMF_TMP_DIR}/release.$$"
  local tarball extract_dir
  mkdir -p "${workdir}"
  tarball="${workdir}/umf.tar.gz"
  extract_dir="${workdir}/extract"
  mkdir -p "${extract_dir}"
  log_debug "workdir=${workdir}"; log_debug "tarball=${tarball}"; log_debug "extract_dir=${extract_dir}"; log_debug "INSTALL_PREFIX(MAKEFILE_DIR)=${MAKEFILE_DIR}"

  if ! umr_download_tarball "${GITHUB_OWNER}" "${GITHUB_REPO}" "${desired}" "${tarball}"; then
    log_error "Failed to download release tarball for ${desired}."
    [[ -n "${GITHUB_TOKEN:-}" ]] && log_warn "If private repo, ensure token access."
    return 1
  fi

  if ! tar -tzf "${tarball}" >/dev/null 2>&1; then
    log_error "Downloaded file is not a valid tar.gz archive"; return 1
  fi
  log_success "Download verified: valid tar.gz archive."

  local ROOT_DIR_NAME
  ROOT_DIR_NAME="$(umr_tar_first_dir "${tarball}" || true)"
  if [[ -z "${ROOT_DIR_NAME}" ]]; then
    log_error "Could not determine top-level directory inside the archive."; return 1
  fi

  log_debug "Extracting tarball to ${extract_dir} ..."
  if ! umr_extract_tarball "${tarball}" "${extract_dir}"; then
    log_error "tar extraction failed"; return 1
  fi

  local top="${extract_dir}/${ROOT_DIR_NAME}"
  if [[ ! -d "${top}" ]]; then
    log_warn "Top dir '${top}' not found; scanning extract_dir for candidates..."
    top="$(find "${extract_dir}" -mindepth 1 -maxdepth 1 -type d | head -n1 || true)"
    [[ -z "${top}" || ! -d "${top}" ]] && { log_error "Extracted directory not found."; return 1; }
  fi

  rm -rf "${MAKEFILE_DIR}"
  mv "${top}" "${MAKEFILE_DIR}"
  if [[ "${desired}" != "${MAIN_BRANCH}" ]]; then echo "${desired}" > "${MAKEFILE_DIR}/.version"; fi
  log_success "Makefile system installed at '${MAKEFILE_DIR}' (source: ${desired})."

  local must_have=("makefiles/core.mk" "makefiles/help.mk" "makefiles/version.mk")
  local missing=0 rel
  for rel in "${must_have[@]}"; do
    [[ -f "${MAKEFILE_DIR}/${rel}" ]] || { log_warn "Missing expected file: ${MAKEFILE_DIR}/${rel}"; missing=1; }
  done
  [[ "${missing}" -eq 1 ]] && log_warn "Some expected files are missing. Archive layout may have changed."
  echo "release" > "${UMS_INSTALL_TYPE_FILE}"
  return 0
}

install_github_workflow() {
  log_info "Installing GitHub Actions workflow..."
  mkdir -p .github/workflows
  local src_dir="$MAKEFILE_DIR/github/workflows"
  shopt -s nullglob
  local files=( "$src_dir"/* )
  shopt -u nullglob
  if [[ ${#files[@]} -eq 0 ]]; then
    log_warn "No workflows to install in $src_dir"; return 0
  fi
  log_info "Copying the following workflow files:"
  local f
  for f in "${files[@]}"; do echo "  - $f"; done
  cp -rf "${files[@]}" .github/workflows/
  log_success "GitHub Actions workflow installed"
}

show_status_installer() {
  log_info "Checking status of the installed Universal Makefile System..."
  echo ""
  if [[ -f ".gitmodules" ]] && grep -q "path = ${MAKEFILE_DIR}" ".gitmodules" 2>/dev/null; then
    if [[ -d "$MAKEFILE_DIR" ]] && (cd "$MAKEFILE_DIR" && git rev-parse --is-inside-work-tree >/dev/null 2>&1); then
      local git_dir="$MAKEFILE_DIR" remote branch commit status
      remote=$(git -C "$git_dir" remote get-url origin 2>/dev/null || echo "N/A")
      branch=$(git -C "$git_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "N/A")
      commit=$(git -C "$git_dir" rev-parse --short HEAD 2>/dev/null || echo "N/A")
      status=$(git -C "$git_dir" status --porcelain 2>/dev/null || true)
      echo "  Installation Type : Submodule"
      echo "  Path              : ${git_dir}"
      echo "  Remote URL        : ${remote}"
      echo "  Branch            : ${branch}"
      echo "  Commit            : ${commit}"
      if [[ -n "$status" ]]; then log_warn "Status            : Modified (Local changes detected in system files)"
      else log_success "  Status            : Clean"; fi
    fi
  elif [[ -d "$MAKEFILE_DIR/makefiles" ]]; then
    echo "  Installation Type : Release"
    echo "  Path              : ${MAKEFILE_DIR}"
    if [[ -f "${MAKEFILE_DIR}/.version" ]]; then
      local version; version=$(cat "${MAKEFILE_DIR}/.version")
      echo "  Installed Version : ${version}"
    elif [[ -f "${MAKEFILE_DIR}/VERSION" ]]; then
      local version; version=$(cat "${MAKEFILE_DIR}/VERSION")
      echo "  Installed Version : ${version}"
    else
      echo "  Installed Version : Not found"
    fi
  elif [[ -d "makefiles" ]]; then
    echo "  Installation Type : Copied Files"
    if [[ -f "VERSION" ]]; then
      local version; version=$(cat VERSION)
      echo "  Version File      : ${version}"
    else
      echo "  Version File      : Not found"
    fi
    log_warn "  Cannot determine specific git commit for copied files."
  else
    log_error "Universal Makefile System installation not found."
    exit 1
  fi
  echo ""
}

setup_app_example() {
  local app_type="${1:-}"
  local examples_dir="$MAKEFILE_DIR/examples"
  [[ ! -d "$examples_dir" ]] && log_error "examples directory not found!" && exit 1
  if [[ -z "$app_type" ]]; then
    echo ""
    log_info "Available example apps:"
    local apps=(); local i=1
    local dir app_name
    for dir in "$examples_dir"/*/; do
      app_name=$(basename "$dir")
      [[ "$app_name" == "environments" ]] && continue
      apps+=( "$app_name" )
      echo "  $i) $app_name"
      ((i++))
    done
    [[ ${#apps[@]} -eq 0 ]] && log_warn "No app examples found!" && exit 1
    echo ""
    local choice
    if [[ "$YES" == true ]]; then
      choice=1; log_info "--yes provided; selecting first example: ${apps[0]}"
    else
      read -rp "Select example to setup (1-${#apps[@]}) [q to quit]: " choice
    fi
    [[ "${choice:-}" == "q" || "${choice:-}" == "Q" ]] && log_warn "Aborted by user." && exit 0
    [[ "${choice:-x}" =~ ^[0-9]+$ ]] || { log_error "Invalid input"; exit 1; }
    app_type="${apps[$((choice-1))]:-}"
    [[ -z "$app_type" ]] && log_error "Invalid selection" && exit 1
  fi
  local template_dir="$examples_dir/$app_type"
  [[ ! -d "$template_dir" ]] && log_error "No template directory for '$app_type'" && exit 1
  log_info "Setting up example for '$app_type'..."
  local file fname yn
  for file in "$template_dir"/*; do
    fname=$(basename "$file")
    if [[ -e "$fname" && "$FORCE_INSTALL" != true && "$YES" != true ]]; then
      read -rp "File $fname already exists. Overwrite? [y/N]: " yn
      [[ "$yn" =~ ^[Yy]$ ]] || { log_warn "Skipped $fname"; continue; }
    fi
    cp -rf "$file" .
    log_success "Installed $fname"
  done
  log_success "$app_type example setup complete!"
  echo "Try: make help"
}

show_diff_installer() {
  echo ""
  log_info "Debug mode enabled. Showing local changes that are blocking the update:"
  git --no-pager -C "$MAKEFILE_DIR" diff --color=always || true
  echo ""
}

update_makefile_system_installer() {
  log_info "Updating Universal Makefile System..."
  log_info "Detecting installation type..."
  local installed_type=""
  if [[ -f ".gitmodules" ]] && grep -q "path = ${MAKEFILE_DIR}" ".gitmodules" 2>/dev/null \
     && [[ -d "$MAKEFILE_DIR" ]] && (cd "$MAKEFILE_DIR" && git rev-parse --is-inside-work-tree >/dev/null 2>&1); then
    installed_type="submodule"
  elif git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
       && git log --grep="git-subtree-dir: ${MAKEFILE_DIR}" --oneline 2>/dev/null | grep -q .; then
    installed_type="subtree"
  elif [[ -f "${MAKEFILE_DIR}/.version" || -d "${MAKEFILE_DIR}/makefiles" ]]; then
    installed_type="release"
  elif [[ -d "makefiles" ]]; then
    installed_type="copy"
  else
    log_error "Universal Makefile System installation not found. Cannot update."; exit 1
  fi

  echo "${installed_type}" > "${UMS_INSTALL_TYPE_FILE}"
  log_info "-> Installation type detected as: ${installed_type}"
  echo ""

  case "$installed_type" in
    submodule)
      local old_commit; old_commit=$(git -C "$MAKEFILE_DIR" rev-parse HEAD 2>/dev/null || echo "")
      log_info "Detecting remote default branch..."
      local remote_head
      remote_head=$(git -C "$MAKEFILE_DIR" remote show origin 2>/dev/null | sed -n 's/.*HEAD branch: //p' | head -n1)
      if [[ -z "$remote_head" ]]; then
        remote_head=$(git -C "$MAKEFILE_DIR" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@' || true)
      fi
      if [[ -z "$remote_head" ]]; then
        if git -C "$MAKEFILE_DIR" ls-remote --exit-code --heads origin main   >/dev/null 2>&1; then remote_head=main
        elif git -C "$MAKEFILE_DIR" ls-remote --exit-code --heads origin master >/dev/null 2>&1; then remote_head=master
        else remote_head="$MAIN_BRANCH"; fi
      fi
      log_info "-> Remote default branch: ${remote_head}"
      log_info "Fetching latest changes for submodule..."
      git -C "$MAKEFILE_DIR" fetch origin --prune || true
      local current_branch; current_branch=$(git -C "$MAKEFILE_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo HEAD)
      if [[ "$FORCE_INSTALL" == true ]]; then
        log_warn "Forcibly updating submodule to origin/${remote_head}..."
        git -C "$MAKEFILE_DIR" reset --hard "origin/${remote_head}"
        log_success "Submodule forcibly updated to latest commit from remote."
      else
        if [[ "$current_branch" = "HEAD" ]]; then
          log_warn "Detached HEAD. Checking out '${remote_head}'..."
          git -C "$MAKEFILE_DIR" checkout -B "$remote_head" "origin/${remote_head}" --no-track || true
        fi
        log_info "Attempting to merge origin/${remote_head}..."
        if ! git -C "$MAKEFILE_DIR" merge --ff-only "origin/${remote_head}"; then
          echo ""
          log_error "Merge into submodule failed (non fast-forward)."
          log_warn  "You may have local changes or diverged history in '${MAKEFILE_DIR}'."
          if [[ "$DEBUG_MODE" == true ]]; then show_diff_installer
          else log_info "Re-run with --debug to see local changes, or use --force to hard reset."
          fi
          exit 1
        fi
        log_success "Submodule updated with fast-forward merge."
      fi
      ;;
    subtree)
      log_info "Pulling latest changes into git subtree..."
      git rev-parse --git-dir >/dev/null 2>&1 || { log_error "Not in a git repository. Cannot update subtree."; exit 1; }
      git subtree pull --prefix="$MAKEFILE_DIR" "$REPO_URL" "$MAIN_BRANCH" --squash \
        || { log_error "Failed to pull git subtree."; exit 1; }
      log_success "Git subtree pulled successfully."
      ;;
    copy)
      log_info "Updating by re-copying latest files..."
      local temp_dir; temp_dir="$(mktemp -d "${UMF_TMP_DIR}/copy-update.XXXXXX")"
      log_info "Cloning latest version from $REPO_URL"
      git clone "$REPO_URL" "$temp_dir/universal-makefile"
      cp -r "$temp_dir/universal-makefile/makefiles" .
      cp -r "$temp_dir/universal-makefile/scripts" . 2>/dev/null || true
      cp -r "$temp_dir/universal-makefile/templates" . 2>/dev/null || true
      [[ -f "$temp_dir/universal-makefile/VERSION" ]] && cp "$temp_dir/universal-makefile/VERSION" .
      log_success "Copied latest files from remote."
      ;;
    release)
      local PINNED="" LATEST="" CURRENT="" UPDATE_PIN=false
      [[ -f .ums-version ]] && PINNED="$(cat .ums-version)"
      [[ -f "${MAKEFILE_DIR}/.version" ]] && CURRENT="$(cat "${MAKEFILE_DIR}/.version")"
      LATEST="$(umr_fetch_latest_release_tag "${GITHUB_OWNER}" "${GITHUB_REPO}" || true)"
      if [[ -z "${DESIRED_REF:-}" ]]; then
        if [[ "${FORCE_INSTALL}" == "true" && -n "${LATEST}" ]]; then
          DESIRED_REF="${LATEST}"; UPDATE_PIN=true; log_info "--force: overriding to latest ${DESIRED_REF}"
        elif [[ -n "${PINNED}" ]]; then
          if [[ -n "${LATEST}" && "${PINNED}" != "${LATEST}" && -t 0 && "${YES}" != "true" ]]; then
            echo ""; echo "A newer release is available."
            echo "  pinned : ${PINNED}"
            echo "  latest : ${LATEST}"
            local yn; read -r -p "Update to latest? [y/N]: " yn || true
            case "$yn" in [yY][eE][sS]|[yY]) DESIRED_REF="${LATEST}"; UPDATE_PIN=true ;; *) DESIRED_REF="${PINNED}" ;; esac
          else
            DESIRED_REF="${PINNED}"
          fi
        else
          DESIRED_REF="${LATEST:-${CURRENT}}"
        fi
      fi
      log_info "Re-installing latest release archive (ref: ${DESIRED_REF})..."
      install_release || { log_error "Release update failed"; exit 1; }
      echo "${DESIRED_REF}" > .ums-release-version 2>/dev/null || true
      if [[ "${UPDATE_PIN}" == "true" ]]; then echo "${DESIRED_REF}" > .ums-version 2>/dev/null || true; fi
      log_success "Release archive updated"
      ;;
  esac
}

# ---- Uninstall ----
safe_rm_installer() {
  if [[ "$DRY_RUN" == true ]]; then
    log_info "[dry-run] Would remove: $*"
  else
    [[ "${BACKUP:-false}" == true ]] && cp -r "$@" "$backup_dir/" 2>/dev/null || true
    rm -rf "$@"
    log_info "Removed $*"
  fi
}

uninstall_installer() {
  echo "${BLUE}Uninstalling Universal Makefile System...${RESET}"
  if [[ "$FORCE_INSTALL" != true && "$YES" != true && "$DRY_RUN" != true ]]; then
    local yn; read -rp "Proceed with uninstall? This will remove generated files. [y/N]: " yn
    [[ "$yn" =~ ^[Yy]$ ]] || { log_warn "Aborted by user."; exit 0; }
  fi
  local backup_dir=""
  if [[ "$BACKUP" == true ]]; then
    backup_dir=".backup_universal_makefile_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    log_info "Backup enabled. Files will be backed up to $backup_dir"
  fi
  local f
  for f in Makefile Makefile.universal project.mk; do
    if has_universal_id "$f"; then safe_rm_installer "$f"; log_info "Removed $f"; fi
  done
  [[ -f .project.local.mk ]]      && safe_rm_installer .project.local.mk
  [[ -f .NEW_VERSION.tmp ]]       && safe_rm_installer .NEW_VERSION.tmp
  [[ -f .env ]]                   && safe_rm_installer .env
  if [[ -f docker-compose.dev.yml ]] && has_universal_id docker-compose.dev.yml; then
    safe_rm_installer docker-compose.dev.yml
  fi
  [[ -d environments ]] && safe_rm_installer environments
  [[ -d makefiles   ]]  && safe_rm_installer makefiles
  [[ -d scripts     ]]  && safe_rm_installer scripts
  [[ -d templates   ]]  && safe_rm_installer templates
  if [[ -d "$MAKEFILE_DIR" ]]; then
    if command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1 \
       && git config --file .gitmodules --get "submodule.$MAKEFILE_DIR.path" >/dev/null 2>&1; then
      if [[ "$FORCE_INSTALL" == true ]]; then
        git submodule deinit -f "$MAKEFILE_DIR" || true
        git rm -f "$MAKEFILE_DIR" || true
        rm -rf ".git/modules/$MAKEFILE_DIR" "$MAKEFILE_DIR"
        log_info "Removed submodule directory ($MAKEFILE_DIR)"
      else
        log_warn "Submodule directory ($MAKEFILE_DIR) not removed. Use --force option to remove."
      fi
    else
      safe_rm_installer "$MAKEFILE_DIR"; log_info "Removed directory $MAKEFILE_DIR"
    fi
  fi
  if [[ "${REMOVE_PIN_FILES:-false}" == true ]]; then
    [[ -f .ums-version          ]] && safe_rm_installer .ums-version
    [[ -f .ums-release-version  ]] && safe_rm_installer .ums-release-version
  fi
  sed -i.bak '/Universal Makefile System/d;/.project.local.mk/d;/\.env/d' .gitignore 2>/dev/null || true
  rm -f .gitignore.bak
  [[ -f docker-compose.yml ]] && log_warn "docker-compose.yml is not removed (user/project file)."
  [[ -f project.mk ]] && ! has_universal_id project.mk && log_warn "project.mk is not removed (user/project file)."
  log_warn "User project files such as docker-compose.yml are not removed for safety."
  log_success "Uninstallation complete"
}

# ---- Validate ----
is_universal_makefile_installed_installer() {
  local ok=true
  if [[ ! -d "${MAKEFILE_DIR}" && ! -d "makefiles" ]]; then log_error "Universal Makefile System directory (${MAKEFILE_DIR} or makefiles) not found."; ok=false; fi
  [[ -f "Makefile.universal" ]] || { log_error "Makefile.universal not found."; ok=false; }
  [[ -f "project.mk"        ]] || { log_error "project.mk not found."; ok=false; }
  if [[ ! -d "environments" || -z "$(ls environments/*.mk 2>/dev/null)" ]]; then log_error "No environments/*.mk files found."; ok=false; fi
  if [[ -f Makefile ]]; then
    echo ""
    if ! grep -q '^[[:space:]]*include[[:space:]]\+Makefile\.universal' Makefile; then
      log_warn "Makefile does NOT include 'include Makefile.universal'."
      log_info "Add this line to your Makefile:"
      echo -e "${YELLOW}include Makefile.universal${RESET} \n\n"
    fi
  fi
  if [[ "$ok" == true ]]; then log_success "Universal Makefile System is properly installed 🎉"; return 0
  else log_warn "Universal Makefile System is NOT fully installed."; return 1; fi
}

# ---- Self-update installer script ----
self_update_script_installer() {
  log_info "Updating installer script itself..."
  local tmp_script; tmp_script="$(mktemp "${UMF_TMP_DIR}/self.XXXXXX")"
  local -a curl_args=( -fsSL -L -H "Cache-Control: no-cache" )
  local -a wget_args=( -q --no-cache )
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    log_info "GITHUB_TOKEN is set. Adding authentication header."
    local auth_header="Authorization: Bearer ${GITHUB_TOKEN}"
    curl_args+=( -H "${auth_header}" ); wget_args+=( --header="${auth_header}" )
  fi
  local download_success=true
  if command -v curl >/dev/null 2>&1; then
    curl "${curl_args[@]}" "$INSTALLER_SCRIPT_URL" -o "$tmp_script" || download_success=false
  elif command -v wget >/dev/null 2>&1; then
    wget "${wget_args[@]}" -O "$tmp_script" "$INSTALLER_SCRIPT_URL" || download_success=false
  else
    log_error "curl or wget required for self-update."; exit 1
  fi
  if [[ "$download_success" == true && -s "$tmp_script" ]]; then
    chmod +x "$tmp_script"; mv "$tmp_script" "$0"; log_success "Installer script updated successfully!"
  else
    rm -f "$tmp_script"; log_error "Failed to download installer script."; exit 1
  fi
}

umf_install_main() {
  local cmd=${1:-install}; shift || true
  if [[ "${DEBUG_MODE}" == "true" ]]; then
    log_info "[debug] entry: cmd=${cmd} args='$*'"
    print_debug_context
  fi
  case "$cmd" in
    install)
      CURRENT_CMD="install"; parse_install_args_installer "$@"; check_requirements_installer
      log_info "[install] MAKEFILE_DIR=${MAKEFILE_DIR} INSTALLATION_TYPE=${INSTALLATION_TYPE} SCAFFOLD_ONLY=${SCAFFOLD_ONLY}"
      if [[ "$SCAFFOLD_ONLY" != true ]]; then
        case "$INSTALLATION_TYPE" in
          submodule) install_submodule ;;
          copy)      install_copy ;;
          subtree)   install_subtree ;;
          release)   install_release ;;
          *)         log_error "Invalid installation type: $INSTALLATION_TYPE"; exit 1 ;;
        esac
      else
        log_warn "[install] --scaffold-only specified: skipping code download/update"
      fi
      _umc_try_source || true
      if [[ "${DEBUG_MODE}" == "true" ]]; then
        if type umc_scaffold_project_files >/dev/null 2>&1; then log_info "[debug] umc_scaffold_project_files available"
        else log_warn "[debug] umc_scaffold_project_files NOT found"; fi
      fi
      if type umc_scaffold_project_files >/dev/null 2>&1; then
        log_info "[install] invoking umc_scaffold_project_files..."
        umc_scaffold_project_files "${MAKEFILE_DIR}" \
        && umc_update_gitignore \
        && umc_create_environments "${FORCE_INSTALL}" \
        && [[ "$EXISTING_PROJECT" == false ]] && umc_create_sample_compose "${FORCE_INSTALL}" \
        && install_github_workflow \
        && log_success "🎉 Universal Makefile System installation completed!"
      else
        log_warn "[install] scaffold library not available; skipping project scaffolding"
      fi
      [[ -f Makefile            ]] && log_info "[verify] Makefile exists"            || log_warn "[verify] Makefile missing"
      [[ -f Makefile.universal  ]] && log_info "[verify] Makefile.universal exists"  || log_warn "[verify] Makefile.universal missing"
      [[ -f project.mk          ]] && log_info "[verify] project.mk exists"          || log_warn "[verify] project.mk missing"
      [[ -d environments        ]] && log_info "[verify] environments/ exists"       || log_warn "[verify] environments/ missing"
      ;;
    init)
      parse_common_args_installer "$@"
      _umc_try_source || true
      log_info "[init] scaffolding only (MAKEFILE_DIR=${MAKEFILE_DIR})"
      if [[ "${DEBUG_MODE}" == "true" ]]; then print_debug_context; fi
      umc_scaffold_project_files "${MAKEFILE_DIR}"
      ;;
    app|setup-app)
      local app_type=""
      if [[ "${1:-}" =~ ^- ]]; then
        parse_common_args_installer "$@"
      else
        app_type="${1:-}"; shift || true
        parse_common_args_installer "$@"
      fi
      check_requirements_installer; setup_app_example "$app_type"
      ;;
    status)
      parse_common_args_installer "$@"; show_status_installer ;;
    update|pull)
      CURRENT_CMD="update"; parse_update_args_installer "$@"; check_requirements_installer; show_status_installer; update_makefile_system_installer ;;
    uninstall)
      CURRENT_CMD="uninstall"; parse_uninstall_args_installer "$@"; check_requirements_installer; uninstall_installer ;;
    update-script|self-update|self-update-script)
      parse_common_args_installer "$@"; self_update_script_installer ;;
    check)
      parse_common_args_installer "$@"; is_universal_makefile_installed_installer ;;
    diff)
      parse_common_args_installer "$@"; show_diff_installer ;;
    help|-h|--help|'')
      usage_installer ;;
    *)
      log_error "Unknown command: $cmd"; usage_installer; exit 1 ;;
  esac
}
