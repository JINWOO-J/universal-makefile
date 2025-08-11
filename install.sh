#!/bin/bash
set -euo pipefail
unalias -a 2>/dev/null || true

# 색상 정의
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    BLUE=$(tput setaf 4)
    RESET=$(tput sgr0)
else
    RED=""; GREEN=""; YELLOW=""; BLUE=""; RESET=""
fi

# 로깅 함수
log_info()    { echo "${BLUE}ℹ️  $1${RESET}"; }
log_success() { echo "${GREEN}✅ $1${RESET}"; }
log_warn()    { echo "${YELLOW}⚠️  $1${RESET}"; }
log_error()   { echo "${RED}❌ $1${RESET}" >&2; }

MAKEFILE_DIR=".makefile-system"

GITHUB_OWNER="jinwoo-j"
GITHUB_REPO="universal-makefile"
GITHUB_REPO_SLUG="${GITHUB_OWNER}/${GITHUB_REPO}"
MAIN_BRANCH="master"

REPO_URL="https://github.com/${GITHUB_REPO_SLUG}"
INSTALLER_SCRIPT_URL="https://raw.githubusercontent.com/${GITHUB_REPO_SLUG}/${MAIN_BRANCH}/install.sh"

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
INSTALLATION_TYPE="subtree"
DESIRED_REF=""
YES=false

FORCE_INSTALL=false
DRY_RUN=false
BACKUP=false
EXISTING_PROJECT=false
DEBUG_MODE=false
CURRENT_CMD=""

# 다운로드/검증 유틸 (setup.sh와 일치)
CURL_RETRY_MAX=${CURL_RETRY_MAX:-3}
CURL_RETRY_DELAY_SEC=${CURL_RETRY_DELAY_SEC:-2}

verify_sha256() {
    # $1: file path, $2: expected sha256
    local file_path="$1"
    local expected="$2"
    if [ -z "$expected" ]; then
        return 2
    fi
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

fetch_latest_release_tag() {
    # 최신 릴리스 태그 조회 (API → git ls-remote 폴백)
    local api_url="https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/releases/latest"
    local auth_args=()
    [[ -n "${GITHUB_TOKEN:-}" ]] && auth_args=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
    local tag
    if command -v curl >/dev/null 2>&1; then
        tag=$(curl -fsSL "${auth_args[@]}" "$api_url" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1 || true)
    elif command -v wget >/dev/null 2>&1; then
        if [[ -n "${GITHUB_TOKEN:-}" ]]; then
            tag=$(wget -qO- --header="Authorization: Bearer ${GITHUB_TOKEN}" "$api_url" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1 || true)
        else
            tag=$(wget -qO- "$api_url" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1 || true)
        fi
    fi
    if [ -n "$tag" ]; then
        echo "$tag"; return 0
    fi
    if command -v git >/dev/null 2>&1; then
        tag=$(git ls-remote --tags --refs "https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}.git" 2>/dev/null \
            | awk '{print $2}' | sed 's@refs/tags/@@' | sort -Vr | head -n1)
        if [ -n "$tag" ]; then
            echo "$tag"; return 0
        fi
    fi
    return 1
}

usage() {
    cat <<EOF
Universal Makefile System Installer

Usage: $0 <command> [options]

Commands:
    install             Install the Universal Makefile System (default)
    update | pull       Update the Universal Makefile System to the latest version
    uninstall           Remove all files created by this installer
    self-update         Update this installer script itself
    app | setup-app     Setup example app
    diff                Show differences between local and remote files
    help                Show this help message

Common options:
    --force             Force installation/uninstall/update actions
    --dry-run           Show actions without performing them
    --backup            Backup files before removing (uninstall only)
    -d, --debug         Show detailed debug info on failure
    -y, --yes           Non-interactive mode; auto-approve prompts

Install options:
    --copy              Install by copying files instead of submodule
    --submodule         Install using git submodule (instead of default subtree)
    --subtree           Install using git subtree
    --release           Install using GitHub release tarball (token-aware, private repos OK)
    --prefix DIR        Install universal system under DIR (default: .makefile-system)
    --version TAG       Pin to a specific release tag (e.g., v1.2.3)
    --ref REF           Pin to a git ref (branch/tag/commit)
    --existing-project  Setup in existing project (preserve existing files)

Examples:
    $0 install --copy
    $0 uninstall --dry-run --backup
    $0 self-update
    $0 help

Repository: $REPO_URL
EOF
}

resolve_flag() {
    local env_var_name=$1
    local long_flag=$2
    local short_flag=$3
    local all_args=("${@:4}")

    for arg in "${all_args[@]:-}"; do
        if [[ "$arg" == "$long_flag" || (-n "$short_flag" && "$arg" == "$short_flag") ]]; then
            echo "true"
            return
        fi
    done

    eval "local env_val=\"\${$env_var_name:-}\""
    if [ -n "${env_val+x}" ]; then
        if [[ "$(echo "$env_val" | tr '[:upper:]' '[:lower:]')" == "true" ]]; then
            echo "true"
        else
            echo "false"
        fi
    else
        echo "false"
    fi
}

parse_common_args() {
    FORCE_INSTALL=$(resolve_flag "FORCE" "--force" "" "$@")
    DRY_RUN=$(resolve_flag "DRY_RUN" "--dry-run" "" "$@")
    BACKUP=$(resolve_flag "BACKUP" "--backup" "" "$@")
    DEBUG_MODE=$(resolve_flag "DEBUG" "--debug" "-d" "$@")
    YES=$(resolve_flag "YES" "--yes" "-y" "$@")

    if [[ "${DEBUG_MODE}" == "true" ]]; then
        log_info "Common flags resolved as follows:"
        echo "  - FORCE_INSTALL: ${FORCE_INSTALL}"
        echo "  - DRY_RUN      : ${DRY_RUN}"
        echo "  - BACKUP       : ${BACKUP}"
        echo "  - DEBUG_MODE   : ${DEBUG_MODE}"
    fi

    local POSITIONAL_ARGS=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force|--dry-run|--backup|-d|--debug|-y|--yes)
                shift ;;
            *)
                POSITIONAL_ARGS+=("$1")
                shift ;;
        esac
    done
    eval set -- "${POSITIONAL_ARGS[@]:-}"
}


parse_install_args() {
    INSTALLATION_TYPE="subtree"
    EXISTING_PROJECT=false

    local remaining_args=()
    while [[ $# -gt 0 ]]; do
        case $1 in
            --copy)
                INSTALLATION_TYPE="copy"; shift ;;
            --subtree)
                INSTALLATION_TYPE="subtree"; shift ;;
            --submodule)
                INSTALLATION_TYPE="submodule"; shift ;;
            --release)
                INSTALLATION_TYPE="release"; shift ;;
            --prefix)
                MAKEFILE_DIR="$2"; shift 2 ;;
            --version)
                DESIRED_REF="$2"; shift 2 ;;
            --ref)
                DESIRED_REF="$2"; shift 2 ;;
            --existing-project)
                EXISTING_PROJECT=true; shift ;;
            --help|-h)
                usage; exit 0 ;;
            *)
                remaining_args+=("$1"); shift ;;
        esac
    done
    parse_common_args "${remaining_args[@]:-}"

    log_info "Installation type: $INSTALLATION_TYPE"
    [[ -n "${DESIRED_REF}" ]] && log_info "Pinned ref: ${DESIRED_REF}"
    log_info "Install prefix: ${MAKEFILE_DIR}"
}

parse_uninstall_args() {
    parse_common_args "$@"
}


parse_update_args() {
    parse_common_args "$@"
}


has_universal_id() {
    local file=$1
    [[ -f "$file" ]] && grep -q "Universal Makefile System" "$file"
}

check_requirements() {
    log_info "Checking requirements..."
    if [[ "$CURRENT_CMD" == "install" || "$CURRENT_CMD" == "update" ]]; then
        if [[ "$INSTALLATION_TYPE" == "submodule" || "$INSTALLATION_TYPE" == "subtree" ]]; then
            if ! command -v git >/dev/null 2>&1; then
                log_error "Git is required for $INSTALLATION_TYPE installation"
                exit 1
            fi
            if ! git rev-parse --git-dir >/dev/null 2>&1; then
                log_error "Not in a git repository. Initialize git first or use --copy"
                exit 1
            fi
        fi
        if [[ "$INSTALLATION_TYPE" == "release" ]]; then
            if ! command -v tar >/dev/null 2>&1; then
                log_error "tar is required for --release installation"; exit 1; fi
            if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
                log_error "Either curl or wget is required for --release installation"; exit 1; fi
        fi
    fi
    if ! command -v make >/dev/null 2>&1; then
        log_error "Make is required"
        exit 1
    fi
    log_success "Requirements check passed"
}


check_existing_installation() {
    if [[ -d "$MAKEFILE_DIR" && ! -f Makefile && ! -f project.mk && ! -d makefiles && ! -f Makefile.universal ]]; then
        log_info "Only submodule detected; proceeding as new installation."
        return 0
    fi

    if [[ -f "Makefile.universal" && "$FORCE_INSTALL" != true ]]; then
        log_error "Makefile.universal already exists. Use --force to overwrite."
        exit 1
    fi

    [[ -d "makefiles" ]] && log_warn "Makefiles directory exists (will not be overwritten)."

    if [[ -f "Makefile" && "$EXISTING_PROJECT" != true ]]; then
        if ! has_universal_id "Makefile"; then
            log_warn "Existing Makefile found (not created by universal-makefile, will NOT be overwritten)."
            log_info "To use Universal Makefile System, add this line to your Makefile:"
            echo -e "${YELLOW}include Makefile.universal${RESET}"
        fi
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
            log_error "Failed to add submodule"
            exit 1
        fi
    fi
    git submodule update --init --recursive
    log_success "Submodule installation completed"
}

install_copy() {
    log_info "Installing by copying files..."
    local temp_dir=$(mktemp -d)
    trap "rm -rf $temp_dir" EXIT
    if [[ -f "$SCRIPT_DIR/makefiles/core.mk" ]]; then
        log_info "Using local repository files"
        local source_dir="$SCRIPT_DIR"
    else
        log_info "Cloning from $REPO_URL"
        git clone "$REPO_URL" "$temp_dir/universal-makefile"
        local source_dir="$temp_dir/universal-makefile"
    fi
    [[ "$FORCE_INSTALL" == true || ! -d "makefiles" ]] && cp -r "$source_dir/makefiles" .
    [[ "$FORCE_INSTALL" == true || ! -d "scripts" ]] && cp -r "$source_dir/scripts" . 2>/dev/null || true
    [[ "$FORCE_INSTALL" == true || ! -d "templates" ]] && cp -r "$source_dir/templates" . 2>/dev/null || true
    [[ -f "$source_dir/VERSION" ]] && cp "$source_dir/VERSION" .
    log_success "Copy installation completed"
}

install_subtree() {
    log_info "Installing via git subtree..."
    # Preconditions
    if ! command -v git >/dev/null 2>&1; then
        log_error "Git is required for subtree installation"; exit 1; fi
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        log_error "Not in a git repository. Initialize git first (git init; git add .; git commit -m 'init') or use --copy"; exit 1; fi

    local prefix_dir="$MAKEFILE_DIR"
    local remote_name="universal-makefile-remote"

    # Add remote if missing
    if ! git remote get-url "$remote_name" >/dev/null 2>&1; then
        git remote add "$remote_name" "$REPO_URL"
        log_info "Added remote '$remote_name' -> $REPO_URL"
    fi

    # Fetch
    git fetch "$remote_name" "$MAIN_BRANCH" --tags --quiet

    # Try initial add
    if git rev-parse --verify "$MAIN_BRANCH" >/dev/null 2>&1; then :; fi

    if [[ -d "$prefix_dir" ]]; then
        log_warn "Directory '$prefix_dir' already exists. Attempting to merge updates..."
        if ! git subtree pull --prefix="$prefix_dir" "$remote_name" "$MAIN_BRANCH" --squash; then
            log_error "git subtree pull failed. Resolve conflicts then retry or run with --copy"
            exit 1
        fi
        log_success "Subtree updated at '$prefix_dir'"
    else
        if ! git subtree add --prefix="$prefix_dir" "$remote_name" "$MAIN_BRANCH" --squash; then
            log_error "git subtree add failed. Ensure repository is clean and committed."
            exit 1
        fi
        log_success "Subtree installed at '$prefix_dir'"
    fi
}

install_release() {
    log_info "Installing via GitHub release tarball..."

    # 원하는 버전 결정: .ums-version > 최신 릴리스 > 브랜치 스냅샷
    local desired=""
    if [[ -n "${DESIRED_REF}" ]]; then
        desired="${DESIRED_REF}"
        log_info "Using explicit ref: ${desired}"
    elif [ -f ".ums-version" ]; then
        desired="$(cat .ums-version)"
        log_info "Pinned version found in .ums-version: ${desired}"
    else
        desired="$(fetch_latest_release_tag || true)"
        if [ -z "${desired}" ]; then
            log_warn "Could not resolve latest release via API. Falling back to branch snapshot: ${MAIN_BRANCH}"
            desired="${MAIN_BRANCH}"
        else
            log_info "Resolved latest release tag: ${desired}"
        fi
    fi

    local TMPDIR
    TMPDIR="$(mktemp -d)" || { log_error "Failed to create temp directory"; exit 1; }
    trap 'rm -rf "${TMPDIR}" >/dev/null 2>&1 || true' EXIT INT TERM
    local TARBALL_PATH="${TMPDIR}/umf.tar.gz"

    local auth_args=()
    local primary_url="" mirror_url=""
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        # 토큰이 있으면 브랜치/태그 구분 없이 API tarball 사용 (프라이빗 지원)
        primary_url="https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/tarball/${desired}"
        mirror_url="${primary_url}"
        auth_args=(-H "Authorization: Bearer ${GITHUB_TOKEN}" -H "X-GitHub-Api-Version: 2022-11-28" -H "Accept: application/vnd.github+json")
        log_info "Using authenticated API tarball download"
    else
        if [[ "${desired}" = "${MAIN_BRANCH}" ]]; then
            # 브랜치 스냅샷 (퍼블릭 전제)
            primary_url="https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}/archive/refs/heads/${MAIN_BRANCH}.tar.gz"
            mirror_url="https://codeload.github.com/${GITHUB_OWNER}/${GITHUB_REPO}/tar.gz/refs/heads/${MAIN_BRANCH}"
        else
            primary_url="https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}/archive/refs/tags/${desired}.tar.gz"
            mirror_url="https://codeload.github.com/${GITHUB_OWNER}/${GITHUB_REPO}/tar.gz/refs/tags/${desired}"
        fi
    fi

    local success=0
    for src in primary mirror; do
        local url="$([ "$src" = "primary" ] && echo "${primary_url}" || echo "${mirror_url}")"
        for attempt in $(seq 1 ${CURL_RETRY_MAX}); do
            log_info "Downloading (${src} try ${attempt}/${CURL_RETRY_MAX}): ${url}"
            if command -v curl >/dev/null 2>&1; then
                if curl -fSL --connect-timeout 10 --max-time 300 "${auth_args[@]}" -o "${TARBALL_PATH}" "${url}"; then
                    [ -s "${TARBALL_PATH}" ] && success=1 && break
                fi
            elif command -v wget >/dev/null 2>&1; then
                local wget_hdr=()
                [[ -n "${GITHUB_TOKEN:-}" ]] && wget_hdr=(--header="Authorization: Bearer ${GITHUB_TOKEN}")
                if wget -q "${wget_hdr[@]}" -O "${TARBALL_PATH}" "${url}"; then
                    [ -s "${TARBALL_PATH}" ] && success=1 && break
                fi
            fi
            sleep $((CURL_RETRY_DELAY_SEC * (2 ** (attempt - 1)))) || sleep ${CURL_RETRY_DELAY_SEC}
        done
        [ "${success}" = "1" ] && break
    done
    if [ "${success}" != "1" ]; then
        log_error "Failed to download release tarball for ${desired}."
        [[ -n "${GITHUB_TOKEN:-}" ]] && log_warn "If private repo, ensure token has proper scopes and SSO authorization."
        exit 1
    fi

    # 추가 검증: 다운로드 파일 존재/크기 확인
    if [ ! -s "${TARBALL_PATH}" ]; then
        log_error "Downloaded tarball not found or empty: ${TARBALL_PATH}"
        exit 1
    fi

    # 추가 검증: tar.gz 유효성 확인 (MIME 및 압축 무결성)
    if command -v file >/dev/null 2>&1; then
        mime=$(file -b --mime-type "${TARBALL_PATH}" || true)
        case "$mime" in
            application/x-gzip|application/gzip|application/octet-stream)
                : ;; # 허용
            *)
                log_warn "Unexpected MIME type for tarball: ${mime}. Will validate with tar."
                ;;
        esac
    fi
    if ! tar -tzf "${TARBALL_PATH}" >/dev/null 2>&1; then
        log_error "Downloaded file is not a valid tar.gz archive"
        exit 1
    fi
    log_success "Download verified: valid tar.gz archive."

    # 체크섬 검증 (릴리스 태그일 때만)
    if [[ "${desired}" != "${MAIN_BRANCH}" ]]; then
        local EXPECTED_SHA256="${UMS_TARBALL_SHA256:-}"
        if [ -z "${EXPECTED_SHA256}" ] && [ -f ".ums-version.sha256" ]; then
            EXPECTED_SHA256="$(tr -d ' \n\r' < .ums-version.sha256)"
        fi
        if [ -n "${EXPECTED_SHA256}" ]; then
            if verify_sha256 "${TARBALL_PATH}" "${EXPECTED_SHA256}"; then
                log_success "SHA256 checksum verified."
            else
                log_error "SHA256 checksum mismatch or verification unavailable."
                exit 1
            fi
        fi
    fi

    # 전개
    tar -xzf "${TARBALL_PATH}" -C "${TMPDIR}"
    # 루트 디렉토리명은 가변적(특히 API tarball). 첫 엔트리 기준으로 판별
    local ROOT_DIR_NAME
    ROOT_DIR_NAME="$(tar -tzf "${TARBALL_PATH}" | head -1 | cut -d/ -f1)"
    if [ -z "${ROOT_DIR_NAME}" ] || [ ! -d "${TMPDIR}/${ROOT_DIR_NAME}" ]; then
        log_error "Extracted directory not found."
        exit 1
    fi

    # 기존 시스템 제거 후 교체
    rm -rf "${MAKEFILE_DIR}"
    mv "${TMPDIR}/${ROOT_DIR_NAME}" "${MAKEFILE_DIR}"
    if [[ "${desired}" != "${MAIN_BRANCH}" ]]; then
        echo "${desired}" > "${MAKEFILE_DIR}/.version"
    fi
    log_success "Makefile system installed at '${MAKEFILE_DIR}' (source: ${desired})."
}

# create_main_makefile 함수 전체를 이 코드로 교체합니다.
# create_main_makefile() {
#     # 1. Makefile.universal 생성 (이 부분은 기존과 동일)
#     local universal_makefile="Makefile.universal"
#     log_info "Creating ${universal_makefile}..."
#     cat > "$universal_makefile" << EOF
# # === Created by Universal Makefile System Installer ===
# # This file is the entry point for the universal makefile system.
# # It should be included by the project's main Makefile.

# .DEFAULT_GOAL := help

# # Detect installation type (submodule vs. copied files)
# ifneq (,\$(wildcard ${MAKEFILE_DIR}/))
#     MAKEFILE_DIR := ${MAKEFILE_DIR}
#     MAKEFILE_TYPE := ${INSTALLATION_TYPE}
# else ifneq (,\$(wildcard makefiles/core.mk))
#     MAKEFILE_DIR := .
#     MAKEFILE_TYPE := script
# else
#     \$(error Universal Makefile System not found. Please run 'install.sh' or 'git submodule update --init')
# endif

# # Ensure project.mk exists and include it
# ifeq (,\$(wildcard project.mk))
#     \$(error project.mk not found. Please run 'install.sh' to generate it.)
# endif
# include project.mk

# # Include environment-specific overrides
# ENV ?= development
# -include environments/\$(ENV).mk
# -include .project.local.mk

# # Include core system modules
# include \$(MAKEFILE_DIR)/makefiles/core.mk
# include \$(MAKEFILE_DIR)/makefiles/help.mk
# include \$(MAKEFILE_DIR)/makefiles/version.mk
# include \$(MAKEFILE_DIR)/makefiles/docker.mk
# include \$(MAKEFILE_DIR)/makefiles/compose.mk
# include \$(MAKEFILE_DIR)/makefiles/git-flow.mk
# include \$(MAKEFILE_DIR)/makefiles/cleanup.mk
# EOF
#     log_success "${universal_makefile} created"


#     # 2. 최상위 Makefile 생성 또는 수정 안내 (이 부분이 핵심 변경사항)
#     local main_makefile="Makefile"
    
#     if [[ ! -f ${main_makefile} ]]; then
#         log_info "Creating main ${main_makefile} with submodule auto-initialization logic..."
#         # Makefile이 없으면, 자동 초기화 로직이 포함된 Makefile을 새로 생성합니다.
#         # 셸의 변수($MAKEFILE_DIR)와 make의 변수(\$(MAKEFILE_DIR))를 구분하기 위해 \`를 사용합니다.
#         cat > "${main_makefile}" << EOF
# # === Created by Universal Makefile System Installer ===
# # This Makefile automatically initializes the submodule system on the first run.

# # Define the location of the Makefile system and the file to check for.
# MAKEFILE_SYSTEM_DIR := ${MAKEFILE_DIR}
# MAKEFILE_SYSTEM_CHECK_FILE := \$(MAKEFILE_SYSTEM_DIR)/Makefile.universal

# # If the check file is missing (e.g., after a fresh git clone),
# # run 'git submodule update' automatically.
# ifeq (\$(wildcard \$(MAKEFILE_SYSTEM_CHECK_FILE)),)
# \$(warning ⚠️  Makefile system not found in \$(MAKEFILE_SYSTEM_DIR). Initializing submodule...)
# \$(shell @git submodule update --init --recursive || exit 1)
# endif

# # Now that the system is guaranteed to be present, include it.
# include \$(MAKEFILE_SYSTEM_CHECK_FILE)

# # Project-specific targets can be added below this line.
# # e.g.,
# # build:
# #	@echo "Building the main project..."

# EOF
#         log_success "Created ${main_makefile} with auto-init logic."
#     else
#         # Makefile이 이미 존재하면, 사용자에게 직접 추가하도록 안내합니다.
#         log_warn "Existing ${main_makefile} detected."
#         echo ""
#         log_info "To enable automatic submodule initialization, add the following lines to the TOP of your Makefile:"
#         # 사용자에게 보여줄 안내 메시지 생성
#         local instructions
#         instructions=$(cat <<EOF

# # --- Start of Universal Makefile System ---
# # Automatically initialize submodule if it's missing.
# MAKEFILE_SYSTEM_DIR := ${MAKEFILE_DIR}
# MAKEFILE_SYSTEM_CHECK_FILE := \$(MAKEFILE_SYSTEM_DIR)/Makefile.universal
# ifeq (\$(wildcard \$(MAKEFILE_SYSTEM_CHECK_FILE)),)
# \$(warning ⚠️  Makefile system not found. Initializing submodule...)
# \$(shell @git submodule update --init --recursive || exit 1)
# endif
# include \$(MAKEFILE_SYSTEM_CHECK_FILE)
# # --- End of Universal Makefile System ---

# EOF
# )
#         echo -e "${YELLOW}${instructions}${RESET}"
#     fi
# }
# install.sh의 create_main_makefile 함수

create_main_makefile() {
    # 1. Makefile.universal을 사용자가 제공한 새로운 내용으로 생성합니다.
    local universal_makefile="Makefile.universal"
    log_info "Creating ${universal_makefile}..."
    cat > "$universal_makefile" << EOF
# === Created by Universal Makefile System Installer ===
# This file is the entry point for the universal makefile system.
# It should be included by the project's main Makefile.

.DEFAULT_GOAL := help

# 1. 먼저 project.mk를 include하여 MAKEFILE_DIR 같은 핵심 변수를 로드합니다.
ifeq (\$(wildcard project.mk),)
    \$(error project.mk not found. Please run 'install.sh' to generate it.)
endif
include project.mk

# 2. 이제 MAKEFILE_DIR 변수가 정의되었으므로, Makefile 시스템의 존재 여부를 확인합니다.
# 이 검사는 설치 유형(submodule 또는 copy)을 감지하고 올바른 경로를 설정합니다.
ifneq (\$(wildcard \$(MAKEFILE_DIR)/makefiles/core.mk),)
    # Submodule 설치: project.mk에 정의된 MAKEFILE_DIR 경로가 유효합니다.
    # 설치 유형을 'submodule'로 명시적으로 설정합니다.
    MAKEFILE_TYPE := submodule
else ifneq (\$(wildcard makefiles/core.mk),)
    # Copy 설치: project.mk의 MAKEFILE_DIR이 유효하지 않을 수 있습니다.
    # 현재 디렉토리를 기준으로 시스템 파일을 찾습니다.
    MAKEFILE_DIR := .
    MAKEFILE_TYPE := copy
else
    # 두 경우 모두 실패 시 사용자에게 친절한 에러 메시지를 보여줍니다.
    \$(warning ⚠️  Universal Makefile System files not found in '\$(MAKEFILE_DIR)')
    \$(error Please run 'git submodule update --init --recursive' and try again.)
endif

# 3. 환경별 오버라이드 파일을 include 합니다.
ENV ?= development
-include environments/\$(ENV).mk
-include .project.local.mk

# 4. 모든 변수와 경로 설정이 끝났으므로, 핵심 시스템 모듈들을 include 합니다.
include \$(MAKEFILE_DIR)/makefiles/core.mk
include \$(MAKEFILE_DIR)/makefiles/help.mk
include \$(MAKEFILE_DIR)/makefiles/version.mk
include \$(MAKEFILE_DIR)/makefiles/docker.mk
include \$(MAKEFILE_DIR)/makefiles/compose.mk
include \$(MAKEFILE_DIR)/makefiles/git-flow.mk
include \$(MAKEFILE_DIR)/makefiles/cleanup.mk
EOF
    log_success "${universal_makefile} created"


    # 2. 최상위 Makefile을 생성하거나 사용자에게 추가 방법을 안내합니다.
    local main_makefile="Makefile"
    
    if [[ ! -f ${main_makefile} ]]; then
        log_info "Creating main ${main_makefile} with submodule auto-initialization logic..."
        # Makefile이 없으면, 자동 초기화 로직이 포함된 Makefile을 새로 생성합니다.
        cat > "${main_makefile}" << EOF
# === Created by Universal Makefile System Installer ===
# This Makefile automatically initializes the submodule system on the first run.

# Define the location of the Makefile system and the file to check for.
MAKEFILE_SYSTEM_DIR := ${MAKEFILE_DIR}
MAKEFILE_SYSTEM_CHECK_FILE := \$(MAKEFILE_SYSTEM_DIR)/Makefile

# If the check file is missing (e.g., after a fresh git clone),
# run 'git submodule update' automatically.
ifeq (\$(wildcard \$(MAKEFILE_SYSTEM_CHECK_FILE)),)
\$(warning ⚠️  Makefile system not found in \$(MAKEFILE_SYSTEM_DIR). Initializing submodule...)
\$(shell git submodule update --init --recursive || exit 1)
endif

# Now that the system is guaranteed to be present, include it.
include Makefile.universal
EOF
        log_success "Created ${main_makefile} with auto-init logic."
    else
        # Makefile이 이미 존재하면, 사용자에게 직접 추가하도록 안내합니다.
        log_warn "Existing ${main_makefile} detected."
        echo ""
        log_info "To enable automatic submodule initialization, add the following lines to the TOP of your Makefile:"
        local instructions
        instructions=$(cat <<EOF

# --- Start of Universal Makefile System ---
# Automatically initialize submodule if it's missing.
MAKEFILE_SYSTEM_DIR := ${MAKEFILE_DIR}
MAKEFILE_SYSTEM_CHECK_FILE := \$(MAKEFILE_SYSTEM_DIR)/Makefile
ifeq (\$(wildcard \$(MAKEFILE_SYSTEM_CHECK_FILE)),)
\$(warning ⚠️  Makefile system not found in \$(MAKEFILE_SYSTEM_DIR). Initializing submodule...)
\$(shell git submodule update --init --recursive || exit 1)
endif
include Makefile.universal
# --- End of Universal Makefile System ---

EOF
)
        echo -e "${YELLOW}${instructions}${RESET}"
    fi
}
create_project_config() {
    [[ -f "project.mk" && "$FORCE_INSTALL" == false ]] && return
    log_info "Creating project.mk..."
    local default_name=$(basename "$(pwd)")
    local default_repo_hub="mycompany"
    if git remote get-url origin >/dev/null 2>&1; then
        local url=$(git remote get-url origin)
        [[ "$url" =~ github.com[:/]([^/]+) ]] && default_repo_hub="${BASH_REMATCH[1]}"
    fi
    cat > "project.mk" << EOF
# === Created by Universal Makefile System Installer ===
REPO_HUB = $default_repo_hub
NAME = $default_name
VERSION = v1.0.0

MAIN_BRANCH = main
DEVELOP_BRANCH = develop

DOCKERFILE_PATH = Dockerfile
DOCKER_BUILD_ARGS =

COMPOSE_FILE = docker-compose.yml
DEV_COMPOSE_FILE = docker-compose.dev.yml
PROD_COMPOSE_FILE = docker-compose.prod.yml
MAKEFILE_DIR = $MAKEFILE_DIR
EOF
    log_success "project.mk created"
}

update_gitignore() {
    log_info "Updating .gitignore..."
    local entries=(
        "# Universal Makefile System"
        ".project.local.mk"
        ".NEW_VERSION.tmp"
        ".env"
        "environments/*.local.mk"
    )
    [[ ! -f .gitignore ]] && touch .gitignore
    for e in "${entries[@]}"; do
        grep -qxF "$e" .gitignore || echo "$e" >> .gitignore
    done
    log_success ".gitignore updated"
}

create_environments() {
    [[ -d "environments" && "$FORCE_INSTALL" == false ]] && return
    log_info "Creating environments/..."
    mkdir -p environments
    cat > environments/development.mk << 'EOF'
# === Created by Universal Makefile System Installer ===
DEBUG = true
DOCKER_BUILD_OPTION += --progress=plain
COMPOSE_FILE = docker-compose.dev.yml
EOF
    cat > environments/production.mk << 'EOF'
# === Created by Universal Makefile System Installer ===
DEBUG = false
DOCKER_BUILD_OPTION += --no-cache
COMPOSE_FILE = docker-compose.prod.yml
EOF
    log_success "Environment configs created"
}

create_sample_compose() {
    [[ -f "docker-compose.dev.yml" && "$FORCE_INSTALL" == false ]] && return
    log_info "Creating docker-compose.dev.yml..."
    cat > docker-compose.dev.yml << 'EOF'
# === Created by Universal Makefile System Installer ===
#version: '3.8'
services:
  app:
    image: ${REPO_HUB}/${NAME}:${TAGNAME}
    ports:
      - "3000:3000"
    environment:
      - NODE_ENV=production
    restart: unless-stopped
EOF
    log_success "Sample docker-compose.dev.yml created"
}

show_completion_message() {
    echo ""
    log_success "🎉 Universal Makefile System installation completed!"
    echo "${BLUE}Next steps:${RESET}"
    echo "  make help                # Show all commands"
    echo "  make build               # Build the application"
    echo "  make getting-started     # Guide"
    [[ "$INSTALLATION_TYPE" == "submodule" ]] && echo "  make update-makefile-system  # Update system (submodule)"
    echo ""
}

show_changelog() {
    local repo_dir=$1
    local old_commit="$2"
    local new_commit="$3"

    if [[ -n "$old_commit" && "$old_commit" != "$new_commit" ]]; then
        echo ""
        log_info "Universal Makefile System: Updates applied ($old_commit..$new_commit):"
        git --no-pager -C "$repo_dir" log --oneline "$old_commit..$new_commit"
        echo ""
    fi
}

safe_rm() {
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[dry-run] Would remove: $*"
    else
        [[ "$BACKUP" == true ]] && cp -r "$@" "$backup_dir/" 2>/dev/null || true
        rm -rf "$@"
        log_info "Removed $*"
    fi
}

uninstall() {
    echo "${BLUE}Uninstalling Universal Makefile System...${RESET}"

    if [[ "$FORCE_INSTALL" != true && "$YES" != true && "$DRY_RUN" != true ]]; then
        read -rp "Proceed with uninstall? This will remove generated files. [y/N]: " yn
        [[ "$yn" =~ ^[Yy]$ ]] || { log_warn "Aborted by user."; exit 0; }
    fi

    local backup_dir=""
    if [[ "$BACKUP" == true ]]; then
        backup_dir=".backup_universal_makefile_$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$backup_dir"
        log_info "Backup enabled. Files will be backed up to $backup_dir"
    fi

    for f in Makefile Makefile.universal project.mk; do
        if has_universal_id "$f"; then
            safe_rm "$f"
            log_info "Removed $f"
        fi
    done

    [[ -f .project.local.mk ]] && safe_rm .project.local.mk
    [[ -f .NEW_VERSION.tmp ]] && safe_rm .NEW_VERSION.tmp
    [[ -f .env ]] && safe_rm .env
    [[ -d environments ]] && safe_rm environments
    [[ -d makefiles ]] && safe_rm makefiles
    [[ -d scripts ]] && safe_rm scripts
    [[ -d templates ]] && safe_rm templates

    if [[ -d "$MAKEFILE_DIR" ]]; then
        # Submodule vs plain directory 판단
        if command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1 \
           && git config --file .gitmodules --get "submodule.$MAKEFILE_DIR.path" >/dev/null 2>&1; then
            # Submodule로 설치된 경우
            if [[ "$FORCE_INSTALL" == true ]]; then
                git submodule deinit -f "$MAKEFILE_DIR" || true
                git rm -f "$MAKEFILE_DIR" || true
                rm -rf ".git/modules/$MAKEFILE_DIR" "$MAKEFILE_DIR"
                log_info "Removed submodule directory ($MAKEFILE_DIR)"
            else
                log_warn "Submodule directory ($MAKEFILE_DIR) not removed. Use --force option to remove."
            fi
        else
            # 릴리스/복사 등 일반 디렉토리로 존재하는 경우 바로 제거
            safe_rm "$MAKEFILE_DIR"
            log_info "Removed directory $MAKEFILE_DIR"
        fi
    fi

    sed -i.bak '/Universal Makefile System/d;/.project.local.mk/d;/\.env/d' .gitignore 2>/dev/null || true
    rm -f .gitignore.bak

    [[ -f docker-compose.yml ]] && log_warn "docker-compose.yml is not removed (user/project file)."
    [[ -f project.mk ]] && ! has_universal_id project.mk && log_warn "project.mk is not removed (user/project file)."

    log_warn "User project files such as docker-compose.yml are not removed for safety."
    log_success "Uninstallation complete"
}

check_token_validity() {
    if [[ -z "${GITHUB_TOKEN:-}" ]]; then
        log_error "GITHUB_TOKEN is not set or is empty. Aborting."
        return 1
    fi

    log_info "Download failed with a GITHUB_TOKEN. Running automatic authentication check..."

    local owner; owner=$(echo "${REPO_URL}" | sed -E 's|https?://github.com/([^/]+)/.*|\1|')
    local repo; repo=$(echo "${REPO_URL}" | sed -E 's|https?://github.com/[^/]+/([^/]+)|\1|')

    local http_code; http_code=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer ${GITHUB_TOKEN}" https://api.github.com/user)
    if [[ "$http_code" == "401" ]]; then
        log_error "GITHUB_TOKEN Check Failed: HTTP ${http_code} - Bad credentials."
        log_warn "The token is invalid, expired, or has been revoked. Please generate a new token."
        return
    elif [[ "$http_code" != "200" ]]; then
        log_error "Token Check Failed: Received HTTP ${http_code} when checking token validity."
        return
    fi
    log_success "Token Check OK: Token is valid."

    http_code=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer ${GITHUB_TOKEN}" "https://api.github.com/repos/${owner}/${repo}")
    if [[ "$http_code" == "404" ]]; then
        log_error "Permission Check Failed: HTTP ${http_code} - Not Found."
        log_warn "The GITHUB_TOKEN is valid, but it does not have permission to access the '${owner}/${repo}' repository."
        log_warn "Please ensure the GITHUB_TOKEN has the correct 'repo' scope (for Classic PAT) or has been granted access to the repository (for Fine-grained PAT)."
        log_warn "If this is an organization repository, ensure SSO has been authorized for the token."
    elif [[ "$http_code" != "200" ]]; then
        log_error "Permission Check Failed: Received HTTP ${http_code} when checking repository access."
    else
        log_success "Permission Check OK: GITHUB_TOKEN has access to the repository."
        log_warn "All checks passed, but download still failed. There might be a temporary network issue or a problem with the file path/branch name."
    fi
}


self_update_script() {
    log_info "Updating installer script itself..."
    local tmp_script; tmp_script=$(mktemp)
    local curl_args=("-fsSL" "-L" "-H" "Cache-Control: no-cache")
    local wget_args=("-q" "--no-cache")

    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        log_info "GITHUB_TOKEN is set. Adding authentication header."
        local auth_header="Authorization: Bearer ${GITHUB_TOKEN}"
        curl_args+=(-H "${auth_header}")
        wget_args+=(--header="${auth_header}")
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
        chmod +x "$tmp_script"
        mv "$tmp_script" "$0"
        log_success "Installer script updated successfully!"
    else
        rm -f "$tmp_script"
        log_error "Failed to download installer script."        
        if [[ -n "${GITHUB_TOKEN:-}" ]]; then
            check_token_validity
        else
            log_warn "If this is a private repository, please set the GITHUB_TOKEN environment variable."
        fi
        exit 1
    fi
}


show_diff() {
    echo ""
    log_info "Debug mode enabled. Showing local changes that are blocking the update:"
    git --no-pager -C "$MAKEFILE_DIR" diff --color=always
    echo ""
}

# update_makefile_system 함수 전체를 이 코드로 교체

update_makefile_system() {
    log_info "Updating Universal Makefile System..."
    log_info "Detecting installation type..."
    local installed_type=""
    if grep -q "path = ${MAKEFILE_DIR}" .gitmodules 2>/dev/null; then
        installed_type="submodule"
    elif git log --grep="git-subtree-dir: ${MAKEFILE_DIR}" --oneline | grep -q .; then
        installed_type="subtree"
    elif [[ -d "makefiles" ]]; then
        installed_type="copy"
    else
        log_error "Universal Makefile System installation not found. Cannot update."
        exit 1
    fi
    log_info "-> Installation type detected as: ${installed_type}"
    echo ""

    case "$installed_type" in
        submodule)
            local old_commit
            old_commit=$(git -C "$MAKEFILE_DIR" rev-parse HEAD 2>/dev/null || echo "")

            log_info "Fetching latest changes for submodule..."
            git -C "$MAKEFILE_DIR" fetch origin "$MAIN_BRANCH"

            if [[ "$FORCE_INSTALL" == true ]]; then
                log_warn "Forcibly updating submodule to the latest version..."
                git -C "$MAKEFILE_DIR" reset --hard "origin/$MAIN_BRANCH"
                log_success "Submodule forcibly updated to latest commit from remote."
            else
                log_info "Attempting to merge latest changes..."
                if ! git -C "$MAKEFILE_DIR" merge "origin/$MAIN_BRANCH"; then
                    echo ""
                    log_error "Merge conflict occurred in submodule."
                    log_warn "This usually means you have local changes in '${MAKEFILE_DIR}'."
                    if [[ "$DEBUG_MODE" == true ]]; then
                        show_diff
                    else
                        log_info "To see the conflicting changes, run again with the --debug flag."
                    fi
                    echo ""
                    log_warn "You can resolve conflicts manually, or run update again with --force to overwrite."
                    exit 1
                fi
                log_success "Submodule updated with merge."
            fi

            local new_commit
            new_commit=$(git -C "$MAKEFILE_DIR" rev-parse HEAD 2>/dev/null || echo "")
            show_changelog "$MAKEFILE_DIR" "$old_commit" "$new_commit"
            echo "👉 Don't forget to run 'git add ${MAKEFILE_DIR}' and commit the new submodule version!"
            ;;

        subtree)
       
            log_info "Pulling latest changes into git subtree..."
            if ! git subtree pull --prefix="$MAKEFILE_DIR" "$REPO_URL" "$MAIN_BRANCH" --squash; then
                log_error "Failed to pull git subtree."
                exit 1
            fi
            log_success "Git subtree pulled successfully."
            ;;

        copy)
            log_info "Updating by re-copying latest files..."
            local temp_dir
            temp_dir=$(mktemp -d)
            trap "rm -rf $temp_dir" EXIT
            log_info "Cloning latest version from $REPO_URL"
            git clone "$REPO_URL" "$temp_dir/universal-makefile"

            cp -r "$temp_dir/universal-makefile/makefiles" .
            cp -r "$temp_dir/universal-makefile/scripts" . 2>/dev/null || true
            cp -r "$temp_dir/universal-makefile/templates" . 2>/dev/null || true
            [[ -f "$temp_dir/universal-makefile/VERSION" ]] && cp "$temp_dir/universal-makefile/VERSION" .
            log_success "Copied latest files from remote."
            ;;
    esac
}

is_universal_makefile_installed() {
    local ok=true

    if [[ ! -d "${MAKEFILE_DIR}" && ! -d "makefiles" ]]; then
        log_error "Universal Makefile System directory (.makefile-system or makefiles) not found."
        ok=false
    fi

    if [[ ! -f "Makefile.universal" ]]; then
        log_error "Makefile.universal not found."
        ok=false
    fi

    if [[ ! -f "project.mk" ]]; then
        log_error "project.mk not found."
        ok=false
    fi

    if [[ ! -d "environments" || -z "$(ls environments/*.mk 2>/dev/null)" ]]; then
        log_error "No environments/*.mk files found."
        ok=false
    fi

    if [[ -f Makefile ]]; then
        echo ""
        if ! grep -q '^[[:space:]]*include[[:space:]]\+Makefile\.universal' Makefile; then
            log_warn "Makefile does NOT include 'include Makefile.universal'."
            log_info "Add this line to your Makefile to enable Universal Makefile System:"
            echo -e "${YELLOW}include Makefile.universal${RESET} \n\n"
        fi
    fi

    if [[ "$ok" == true ]]; then
        log_success "Universal Makefile System is properly installed 🎉"
        return 0
    else
        log_warn "Universal Makefile System is NOT fully installed."
        return 1
    fi
}


install_github_workflow() {
    log_info "Installing GitHub Actions workflow..."
    mkdir -p .github/workflows

    local src_dir="$MAKEFILE_DIR/github/workflows"
    shopt -s nullglob
    local files=("$src_dir"/*)
    shopt -u nullglob

    if [[ ${#files[@]} -eq 0 ]]; then
        log_warn "No workflows to install in $src_dir"
        return 0
    fi

    log_info "Copying the following workflow files:"
    for f in "${files[@]}"; do
        echo "  - $f"
    done

    cp -rf "${files[@]}" .github/workflows/
    log_success "GitHub Actions workflow installed"
}

setup_app_example() {
    local app_type="${1:-}"

    local examples_dir="$MAKEFILE_DIR/examples"
    [[ ! -d "$examples_dir" ]] && log_error "examples directory not found!" && exit 1

    if [[ -z "$app_type" ]]; then
        echo ""
        log_info "Available example apps:"
        local apps=()
        local i=1
        for dir in "$examples_dir"/*/; do
            local app_name=$(basename "$dir")
            [[ "$app_name" == "environments" ]] && continue
            apps+=("$app_name")
            echo "  $i) $app_name"
            ((i++))
        done
        if [[ ${#apps[@]} -eq 0 ]]; then
            log_warn "No app examples found!"
            exit 1
        fi
        echo ""
        if [[ "$YES" == true ]]; then
            choice=1
            log_info "--yes provided; selecting first example: ${apps[0]}"
        else
            read -rp "Select example to setup (1-${#apps[@]}) [q to quit]: " choice
        fi
        [[ "$choice" == "q" || "$choice" == "Q" ]] && log_warn "Aborted by user." && exit 0
        [[ "$choice" =~ ^[0-9]+$ ]] || { log_error "Invalid input"; exit 1; }
        app_type="${apps[$((choice-1))]}"
        [[ -z "$app_type" ]] && log_error "Invalid selection" && exit 1
    fi

    local template_dir="$examples_dir/$app_type"
    [[ ! -d "$template_dir" ]] && log_error "No template directory for '$app_type'" && exit 1

    log_info "Setting up example for '$app_type'..."

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

show_status() {
    log_info "Checking status of the installed Universal Makefile System..."
    echo ""

    if [[ -d "$MAKEFILE_DIR" ]] && (cd "$MAKEFILE_DIR" && git rev-parse --is-inside-work-tree >/dev/null 2>&1); then
        local git_dir="$MAKEFILE_DIR"
        local remote; remote=$(git -C "$git_dir" remote get-url origin 2>/dev/null || echo "N/A")
        local branch; branch=$(git -C "$git_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "N/A")
        local commit; commit=$(git -C "$git_dir" rev-parse --short HEAD 2>/dev/null || echo "N/A")
        local status; status=$(git -C "$git_dir" status --porcelain 2>/dev/null)

        echo "  Installation Type : Submodule"
        echo "  Path              : ${git_dir}"
        echo "  Remote URL        : ${remote}"
        echo "  Branch            : ${branch}"
        echo "  Commit            : ${commit}"
        
        if [[ -n "$status" ]]; then
            log_warn "Status            : Modified (Local changes detected in system files)"
            if [[ "$DEBUG_MODE" == "true" ]]; then
                echo ""
                log_info "Showing local modifications (--debug enabled):"
                git --no-pager -C "$git_dir" diff --color=always
            fi
        else
            log_success "  Status            : Clean"
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


main() {
    local cmd=${1:-install}
    shift || true

    case "$cmd" in
        install)
            CURRENT_CMD="install"
            parse_install_args "$@"
            check_requirements            
            check_existing_installation
            case "$INSTALLATION_TYPE" in
                submodule) install_submodule ;;
                copy) install_copy ;;
                subtree) install_subtree ;;
                release) install_release ;;
                *) log_error "Invalid installation type: $INSTALLATION_TYPE"; exit 1 ;;
            esac
            create_main_makefile
            create_project_config
            update_gitignore
            create_environments
            [[ "$EXISTING_PROJECT" == false ]] && create_sample_compose
            install_github_workflow
            show_completion_message
            ;;
        app|setup-app)
            local app_type="${1:-}"
            parse_common_args "${@:2}"
            check_requirements
            setup_app_example "$app_type"
            ;;
        status)
            parse_common_args "$@"
            show_status
            ;;            
        update|pull)            
            CURRENT_CMD="update"
            parse_update_args "$@"
            check_requirements
            show_status
            update_makefile_system
            ;;
        uninstall)
            CURRENT_CMD="uninstall"
            parse_uninstall_args "$@"
            check_requirements
            uninstall
            ;;
        update-script|self-update-script)
            self_update_script
            ;;
        check)
            is_universal_makefile_installed
            ;;
        diff)
            show_diff
            ;;
        help|-h|--help|'')
            usage
            ;;
        *)
            log_error "Unknown command: $cmd"
            usage
            exit 1
            ;;
    esac
}


if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
