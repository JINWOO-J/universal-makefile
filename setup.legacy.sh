#!/bin/bash
# A smart setup script for the Universal Makefile System.
# - When run via 'curl | bash', it clones the project.
# - When run locally, it prepares dependencies and executes 'make'.

set -euo pipefail

# --- 설정 (프로젝트에 맞게 수정) ---
GITHUB_OWNER="jinwoo-j"
GITHUB_REPO="universal-makefile" # 여기에 실제 사용할 '부모' 프로젝트 리포지토리 이름을 넣습니다.
MAIN_BRANCH="main"
MAKEFILE_SYSTEM_DIR=".makefile-system"


if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
    RED=$(tput setaf 1); GREEN=$(tput setaf 2); YELLOW=$(tput setaf 3); BLUE=$(tput setaf 4); RESET=$(tput sgr0)
else
    RED=""; GREEN=""; YELLOW=""; BLUE=""; RESET=""
fi
log_info()    { echo -e "${BLUE}ℹ️  $1${RESET}"; }
log_success() { echo -e "${GREEN}✅ $1${RESET}"; }
log_warn()    { echo -e "${YELLOW}⚠️  $1${RESET}"; }


CURL_RETRY_MAX=${CURL_RETRY_MAX:-3}
CURL_RETRY_DELAY_SEC=${CURL_RETRY_DELAY_SEC:-2}


FORCE_UPDATE=${FORCE_UPDATE:-false}
CLI_VERSION=""

is_true() { case "${1:-}" in true|1|yes|on|Y|y) return 0;; *) return 1;; esac; }

prompt_confirm() {
    local msg="$1"
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

parse_cli_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force|-f)
                FORCE_UPDATE=true; shift ;;
            --version|-v)
                shift || true
                CLI_VERSION="${1:-}"
                if [ -z "${CLI_VERSION}" ]; then
                    echo "--version requires a value" >&2
                    exit 2
                fi
                shift ;;
            --)
                shift
                break ;;
            *)
                break ;;
        esac
    done
}

makefile_includes_universal() { # helper to detect whether user's Makefile includes system
    if [ ! -f "Makefile" ]; then
        return 1
    fi
    if grep -Eq '^[[:space:]]*include[[:space:]]+Makefile\.universal' Makefile; then
        return 0
    fi
    if grep -Eq '^[[:space:]]*include[[:space:]]+\$\(MAKEFILE_DIR\)/makefiles/core\.mk' Makefile; then
        return 0
    fi
    return 1
}

verify_sha256() {
    local file_path="$1"
    local expected="$2"
    if [ -z "$expected" ]; then
        return 2
    fi
    if command -v sha256sum >/dev/null 2>&1; then
        echo "${expected}  ${file_path}" | sha256sum -c --status
        return $?
    elif command -v shasum >/dev/null 2>&1; then
        # macOS
        echo "${expected}  ${file_path}" | shasum -a 256 -c --status
        return $?
    else
        return 3
    fi
}

fetch_latest_release_tag() {
    # Returns latest release tag via GitHub API, falls back to ls-remote tags
    local api_url="https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/releases/latest"
    local auth_args=()
    [[ -n "${GITHUB_TOKEN:-}" ]] && auth_args=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
    # Try API
    local tag
    tag=$(curl -fsSL "${auth_args[@]}" "$api_url" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1 || true)
    if [ -n "$tag" ]; then
        echo "$tag"
        return 0
    fi
    # Fallback: sort tags semver-desc using git ls-remote
    if command -v git >/dev/null 2>&1; then
        tag=$(git ls-remote --tags --refs "https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}.git" 2>/dev/null \
            | awk '{print $2}' | sed 's@refs/tags/@@' \
            | sort -Vr | head -n1)
        if [ -n "$tag" ]; then
            echo "$tag"
            return 0
        fi
    fi
    return 1
}

install_from_release() {
    # $1: desired version tag (e.g., v1.2.3)
    local desired="$1"
    log_warn "Makefile system is missing or out of date. Installing version ${desired}..."
    # 준비: 임시 작업 디렉토리
    TMPDIR="$(mktemp -d)" || { log_warn "Failed to create temp directory"; exit 1; }
    cleanup_tmp() { rm -rf "${TMPDIR}" >/dev/null 2>&1 || true; }
    trap cleanup_tmp EXIT INT TERM

    # 토큰 인증(API tarball) 우선: 프라이빗 레포 지원
    local auth_args=()
    local PRIMARY_URL=""
    local MIRROR_URL=""
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        PRIMARY_URL="https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/tarball/${desired}"
        MIRROR_URL="${PRIMARY_URL}"
        auth_args=(-H "Authorization: Bearer ${GITHUB_TOKEN}" -H "X-GitHub-Api-Version: 2022-11-28" -H "Accept: application/vnd.github+json")
    else
        PRIMARY_URL="https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}/archive/refs/tags/${desired}.tar.gz"
        MIRROR_URL="https://codeload.github.com/${GITHUB_OWNER}/${GITHUB_REPO}/tar.gz/refs/tags/${desired}"
        auth_args=()
    fi
    TARBALL_PATH="${TMPDIR}/umf.tar.gz"

    # 재시도 포함 다운로드 (기본 URL → 미러 URL)
    success=0
    for src in primary mirror; do
        url="$([ "$src" = "primary" ] && echo "${PRIMARY_URL}" || echo "${MIRROR_URL}")"
        for attempt in $(seq 1 ${CURL_RETRY_MAX}); do
            log_info "Downloading (${src} try ${attempt}/${CURL_RETRY_MAX}): ${url}"
            if curl -fSL --connect-timeout 10 --max-time 300 "${auth_args[@]}" -o "${TARBALL_PATH}" "${url}"; then
                if [ -s "${TARBALL_PATH}" ]; then
                    success=1
                    break
                fi
            fi
            sleep $((CURL_RETRY_DELAY_SEC * (2 ** (attempt - 1)))) || sleep ${CURL_RETRY_DELAY_SEC}
        done
        [ "$success" = "1" ] && break
    done

    if [ "$success" != "1" ]; then
        log_warn "Failed to download release tarball for ${desired}."
        exit 1
    fi

    # 선택적 SHA256 검증: 환경변수 또는 .ums-version.sha256 사용
    EXPECTED_SHA256="${UMS_TARBALL_SHA256:-}"
    if [ -z "${EXPECTED_SHA256}" ] && [ -f ".ums-version.sha256" ]; then
        EXPECTED_SHA256="$(cat .ums-version.sha256 | tr -d ' \n\r')"
    fi
    if [ -n "${EXPECTED_SHA256}" ]; then
        if verify_sha256 "${TARBALL_PATH}" "${EXPECTED_SHA256}"; then
            log_success "SHA256 checksum verified."
        else
            log_warn "SHA256 checksum mismatch or verification unavailable. Aborting."
            exit 1
        fi
    else
        log_warn "No SHA256 provided (.ums-version.sha256 or UMS_TARBALL_SHA256). Skipping integrity verification."
    fi

    # 기존 디렉토리 제거 후 전개
    rm -rf "${MAKEFILE_SYSTEM_DIR}"
    tar -xzf "${TARBALL_PATH}" -C "${TMPDIR}"
    VERSION_DIR_NAME="${GITHUB_REPO}-${desired#v}"
    if [ ! -d "${TMPDIR}/${VERSION_DIR_NAME}" ]; then
        # 혹시 다른 아카이브 구조 대비: 첫 번째 디렉토리를 추정
        set +o pipefail
        VERSION_DIR_NAME_FALLBACK="$(tar -tzf "${TARBALL_PATH}" 2>/dev/null | head -n1 | cut -d/ -f1 || true)"
        set -o pipefail
        if [ -n "${VERSION_DIR_NAME_FALLBACK}" ] && [ -d "${TMPDIR}/${VERSION_DIR_NAME_FALLBACK}" ]; then
            VERSION_DIR_NAME="${VERSION_DIR_NAME_FALLBACK}"
        else
            log_warn "Extracted directory not found. Aborting."
            exit 1
        fi
    fi
    mv "${TMPDIR}/${VERSION_DIR_NAME}" "${MAKEFILE_SYSTEM_DIR}"
    echo "${desired}" > "${MAKEFILE_SYSTEM_DIR}/.version"
    log_success "Makefile system version ${desired} is now ready."
}

install_repo_from_release() {
    # $1: desired version tag (e.g., v1.2.3)
    local desired="$1"
    log_info "Bootstrap mode: initializing from release-archive"
    log_info "Selected version: ${desired}"

    local target_dir="${GITHUB_REPO}"
    if [ -e "${target_dir}" ]; then
        log_warn "Target directory '${target_dir}' already exists. Aborting to avoid overwrite."
        exit 1
    fi

    # Auth & URLs
    local auth_args=()
    local DOWNLOAD_URL_PRIMARY=""
    local DOWNLOAD_URL_MIRROR=""

    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        # 핵심: API tarball 엔드포인트 사용 (리다이렉트 후 서명 URL로 내려감)
        DOWNLOAD_URL_PRIMARY="https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/tarball/${desired}"
        # 미러는 의미 없지만, 네트워크 이슈 대비 동일 URL 재시도 구조를 유지
        DOWNLOAD_URL_MIRROR="${DOWNLOAD_URL_PRIMARY}"
        auth_args=(-H "Authorization: Bearer ${GITHUB_TOKEN}" -H "X-GitHub-Api-Version: 2022-11-28" -H "Accept: application/vnd.github+json")
    else
        # 퍼블릭 레포 전제
        DOWNLOAD_URL_PRIMARY="https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}/archive/refs/tags/${desired}.tar.gz"
        DOWNLOAD_URL_MIRROR="https://codeload.github.com/${GITHUB_OWNER}/${GITHUB_REPO}/tar.gz/refs/tags/${desired}"
        auth_args=()  # 무인증
    fi

    TMPDIR="$(mktemp -d)" || { log_warn "Failed to create temp directory"; exit 1; }
    cleanup_tmp_bootstrap() { rm -rf "${TMPDIR}" >/dev/null 2>&1 || true; }
    trap cleanup_tmp_bootstrap EXIT INT TERM

    local TARBALL_PATH="${TMPDIR}/repo.tar.gz"
    local success=0

    for src in primary mirror; do
        local url="$([ "$src" = "primary" ] && echo "${DOWNLOAD_URL_PRIMARY}" || echo "${DOWNLOAD_URL_MIRROR}")"
        for attempt in $(seq 1 ${CURL_RETRY_MAX}); do
            log_info "Downloading repository (${src} try ${attempt}/${CURL_RETRY_MAX}): ${url}"
            # 주의: -L은 유지하되, API tarball 경로는 같은 호스트에서 서명 URL을 주므로 헤더 손실 문제가 없음
            if curl -fSL --connect-timeout 10 --max-time 300 \
                "${auth_args[@]}" \
                -o "${TARBALL_PATH}" "${url}"; then
                if [ -s "${TARBALL_PATH}" ]; then
                    success=1
                    break
                fi
            fi
            sleep $((CURL_RETRY_DELAY_SEC * (2 ** (attempt - 1)))) || sleep ${CURL_RETRY_DELAY_SEC}
        done
        [ "${success}" = "1" ] && break
    done
    if [ "${success}" != "1" ]; then
        log_warn "Failed to download repository release tarball for ${desired}."
        [[ -n "${GITHUB_TOKEN:-}" ]] && log_warn "If this is a private repo, check token scopes (Contents: Read) and SSO authorization."
        exit 1
    fi

    # Optional checksum verification
    local EXPECTED_SHA256="${UMS_TARBALL_SHA256:-}"
    if [ -z "${EXPECTED_SHA256}" ] && [ -f ".ums-version.sha256" ]; then
        EXPECTED_SHA256="$(tr -d ' \n\r' < .ums-version.sha256)"
    fi
    if [ -n "${EXPECTED_SHA256}" ]; then
        if verify_sha256 "${TARBALL_PATH}" "${EXPECTED_SHA256}"; then
            log_success "SHA256 checksum verified."
        else
            log_warn "SHA256 checksum mismatch or verification unavailable. Aborting."
            exit 1
        fi
    fi

    # Extract & move
    tar -xzf "${TARBALL_PATH}" -C "${TMPDIR}"
    # API tarball의 루트 디렉터리명은 커밋 SHA 기반으로 가변적일 수 있으므로 반드시 1번째 엔트리로 판별
    local ROOT_DIR_NAME
    set +o pipefail
    ROOT_DIR_NAME="$(tar -tzf "${TARBALL_PATH}" 2>/dev/null | head -n1 | cut -d/ -f1 || true)"
    set -o pipefail
    if [ -z "${ROOT_DIR_NAME}" ] || [ ! -d "${TMPDIR}/${ROOT_DIR_NAME}" ]; then
        log_warn "Extracted directory not found. Aborting."
        exit 1
    fi

    mv "${TMPDIR}/${ROOT_DIR_NAME}" "${target_dir}"
    # 설치 버전 기록: 다음 비교에 사용
    echo "${desired}" > "${target_dir}/.ums-release-version" || true
    # 내부 시스템 핀(없을 때만 설정)
    if [ ! -f "${target_dir}/.ums-version" ]; then
        echo "${desired}" > "${target_dir}/.ums-version" || true
    fi
    log_success "Project downloaded to '${target_dir}' from release ${desired}."
}

update_repo_from_release() {
    # $1: desired version tag (e.g., v1.2.3)
    local desired="$1"
    local target_dir="${GITHUB_REPO}"
    log_info "Updating existing '${target_dir}' to ${desired} (release archive)..."

    local auth_args=()
    local DOWNLOAD_URL_PRIMARY=""
    local DOWNLOAD_URL_MIRROR=""
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        DOWNLOAD_URL_PRIMARY="https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/tarball/${desired}"
        DOWNLOAD_URL_MIRROR="${DOWNLOAD_URL_PRIMARY}"
        auth_args=(-H "Authorization: Bearer ${GITHUB_TOKEN}" -H "X-GitHub-Api-Version: 2022-11-28" -H "Accept: application/vnd.github+json")
    else
        DOWNLOAD_URL_PRIMARY="https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}/archive/refs/tags/${desired}.tar.gz"
        DOWNLOAD_URL_MIRROR="https://codeload.github.com/${GITHUB_OWNER}/${GITHUB_REPO}/tar.gz/refs/tags/${desired}"
    fi

    local TMPDIR
    TMPDIR="$(mktemp -d)" || { log_warn "Failed to create temp directory"; exit 1; }
    cleanup_tmp_update() { rm -rf "${TMPDIR}" >/dev/null 2>&1 || true; }
    trap cleanup_tmp_update EXIT INT TERM

    local TARBALL_PATH="${TMPDIR}/repo.tar.gz"
    local success=0
    for src in primary mirror; do
        local url="$([ "$src" = "primary" ] && echo "${DOWNLOAD_URL_PRIMARY}" || echo "${DOWNLOAD_URL_MIRROR}")"
        for attempt in $(seq 1 ${CURL_RETRY_MAX}); do
            log_info "Downloading repository (${src} try ${attempt}/${CURL_RETRY_MAX}): ${url}"
            if curl -fSL --connect-timeout 10 --max-time 300 \
                "${auth_args[@]}" \
                -o "${TARBALL_PATH}" "${url}"; then
                if [ -s "${TARBALL_PATH}" ]; then success=1; break; fi
            fi
            sleep $((CURL_RETRY_DELAY_SEC * (2 ** (attempt - 1)))) || sleep ${CURL_RETRY_DELAY_SEC}
        done
        [ "${success}" = "1" ] && break
    done
    [ "${success}" != "1" ] && log_warn "Failed to download release tarball for ${desired}." && exit 1

    tar -xzf "${TARBALL_PATH}" -C "${TMPDIR}"
    local ROOT_DIR_NAME
    set +o pipefail
    ROOT_DIR_NAME="$(tar -tzf "${TARBALL_PATH}" 2>/dev/null | head -n1 | cut -d/ -f1 || true)"
    set -o pipefail
    [ -z "${ROOT_DIR_NAME}" ] && log_warn "Extracted directory not found." && exit 1

    # 파괴적 업데이트: 기존 디렉토리 교체
    rm -rf "${target_dir}"
    mv "${TMPDIR}/${ROOT_DIR_NAME}" "${target_dir}"
    echo "${desired}" > "${target_dir}/.ums-release-version" || true
    if [ ! -f "${target_dir}/.ums-version" ]; then
        echo "${desired}" > "${target_dir}/.ums-version" || true
    fi
    log_success "Project updated to '${desired}'."
}

scaffold_project_files() {
    # Ensure minimal files so that `make help` works in a fresh directory
    local mf_dir="${MAKEFILE_SYSTEM_DIR:-.makefile-system}"
    if [ ! -f "Makefile.universal" ]; then
        cat > Makefile.universal << 'EOF'
# === Created by setup.sh (scaffold) ===

# System dir variables
MAKEFILE_SYSTEM_DIR ?= .makefile-system
MAKEFILE_DIR ?= $(MAKEFILE_SYSTEM_DIR)

# 1. Project config
-include project.mk
-include .project.local.mk

# 2. Environments
ENV ?= development
-include environments/$(ENV).mk
-include .project.local.mk

# 3. Core system modules
include $(MAKEFILE_DIR)/makefiles/core.mk
include $(MAKEFILE_DIR)/makefiles/help.mk
include $(MAKEFILE_DIR)/makefiles/version.mk
include $(MAKEFILE_DIR)/makefiles/docker.mk
include $(MAKEFILE_DIR)/makefiles/compose.mk
include $(MAKEFILE_DIR)/makefiles/git-flow.mk
include $(MAKEFILE_DIR)/makefiles/cleanup.mk
include $(MAKEFILE_DIR)/makefiles/git-file.mk
EOF
        log_success "Makefile.universal scaffolded"
    fi

    if [ ! -f "Makefile" ]; then
        cat > Makefile << 'EOF'
# === Created by setup.sh (scaffold) ===
MAKEFILE_SYSTEM_DIR := .makefile-system
MAKEFILE_DIR := $(MAKEFILE_SYSTEM_DIR)
include Makefile.universal
EOF
        log_success "Makefile scaffolded"
    fi

    if [ ! -f "project.mk" ]; then
        if [ -f "${mf_dir}/templates/project.mk.template" ]; then
            cp "${mf_dir}/templates/project.mk.template" project.mk
            log_success "project.mk created from template"
        else
            cat > project.mk << 'EOF'
# === Created by setup.sh (scaffold) ===
NAME = $(notdir $(CURDIR))
MAKEFILE_DIR = .makefile-system
EOF
            log_success "project.mk scaffolded (minimal)"
        fi
    fi
}


# 현재 디렉토리가 Git 리포지토리인지 확인
parse_cli_args "$@"

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # === 로컬 실행 모드 ===
    # 이미 프로젝트가 clone된 상태에서 실행된 경우
    
    log_info "Project repository found. Verifying Makefile system..."

    # 1. GitHub Release 방식인지 확인 (버전 파일 존재 여부)
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
        LATEST_TAG="$(fetch_latest_release_tag || true)"
        if [ -n "${LATEST_TAG}" ]; then
            log_info "Version status: current=${CURRENT_VERSION:-none}, desired=${DESIRED_VERSION}, latest=${LATEST_TAG}"
        else
            log_info "Version status: current=${CURRENT_VERSION:-none}, desired=${DESIRED_VERSION}"
        fi
        if [[ "${CURRENT_VERSION}" != "${DESIRED_VERSION}" ]]; then
            if [ -z "${CURRENT_VERSION}" ]; then
                log_warn "Makefile system is missing. Installing version ${DESIRED_VERSION}..."
                install_from_release "${DESIRED_VERSION}"
            else
                if ! is_true "${FORCE_UPDATE}"; then
                    if ! prompt_confirm "New version available (${CURRENT_VERSION} → ${DESIRED_VERSION}). Update now?"; then
                        log_info "Skipped update by user choice."
                        DESIRED_VERSION="${CURRENT_VERSION}"
                    fi
                fi
                install_from_release "${DESIRED_VERSION}"
            fi
        else
            if [ -n "${LATEST_TAG:-}" ] && [ "${DESIRED_VERSION}" = "${LATEST_TAG}" ]; then
                log_success "Up to date (latest: ${LATEST_TAG})."
            else
                log_success "Up to date (pinned: ${DESIRED_VERSION}${LATEST_TAG:+, latest: ${LATEST_TAG}})."
            fi
        fi

    # 2. Submodule 방식인지 확인 (.gitmodules 파일 존재 여부)
    elif [ -f ".gitmodules" ] && grep -q "path = ${MAKEFILE_SYSTEM_DIR}" .gitmodules; then
        if [ ! -f "${MAKEFILE_SYSTEM_DIR}/Makefile.universal" ]; then
            log_warn "Submodule is not initialized. Running 'git submodule update'..."
            git submodule update --init --recursive
            log_success "Submodule initialized successfully."
        else
            log_success "Submodule is already initialized."
        fi

    # 3. Subtree 방식은 clone 시 이미 포함되므로 별도 작업 불필요
    elif git log --grep="git-subtree-dir: ${MAKEFILE_SYSTEM_DIR}" --oneline | grep -q .; then
        log_success "Subtree is present."

    # 4. 그 외: 버전 명시가 없다면 최신 릴리즈로 동기화 (기본 동작)
    else
        LATEST_TAG="$(fetch_latest_release_tag || true)"
        if [ -z "${LATEST_TAG}" ]; then
            log_warn "Unable to resolve latest release tag from GitHub."
        else
            DESIRED_VERSION="${LATEST_TAG}"
            # 현재 버전과 비교 (있다면)
            if [ -f "${MAKEFILE_SYSTEM_DIR}/.version" ]; then
                CURRENT_VERSION="$(cat "${MAKEFILE_SYSTEM_DIR}/.version")"
            else
                CURRENT_VERSION=""
            fi
            log_info "Version status: current=${CURRENT_VERSION:-none}, latest=${DESIRED_VERSION}"
            if [[ "${CURRENT_VERSION}" != "${DESIRED_VERSION}" ]]; then
                if [ -z "${CURRENT_VERSION}" ]; then
                    log_warn "Makefile system not found. Installing ${DESIRED_VERSION}..."
                    install_from_release "${DESIRED_VERSION}"
                else
                    if ! is_true "${FORCE_UPDATE}"; then
                        if ! prompt_confirm "New release found (${CURRENT_VERSION} → ${DESIRED_VERSION}). Update now?"; then
                            log_info "Skipped update by user choice."
                            DESIRED_VERSION="${CURRENT_VERSION}"
                        fi
                    fi
                    install_from_release "${DESIRED_VERSION}"
                fi
            else
                log_success "Already up to date (latest: ${DESIRED_VERSION})."
            fi
        fi
    fi

    # 설치 위임 대신 직접 통합은 이미 위에서 처리됨. 중복 작업 방지 위해 위임 생략

    # 최소 스캐폴드 생성 (없을 때만)
    if [ ! -f "project.mk" ] || [ ! -f "Makefile" ]; then
        scaffold_project_files
    fi

    # If user already has a Makefile but it doesn't include the system, print guidance and exit gracefully
    if [ -f "Makefile" ] && ! makefile_includes_universal; then
        log_warn "Existing 'Makefile' detected but it does not include 'Makefile.universal'."
        echo ""
        echo "Add the following line to your Makefile and re-run ./setup.sh:"
        echo ""
        echo "  include Makefile.universal"
        echo ""
        echo "Alternatively, ensure it includes '\$(MAKEFILE_DIR)/makefiles/*.mk' via 'Makefile.universal'."
        exit 0
    fi

    # make 인자 정규화: '--' 제거, 비어있으면 'help'
    make_args=()
    for arg in "$@"; do
        [ "$arg" = "--" ] && continue
        make_args+=("$arg")
    done
    if [ "${#make_args[@]}" -eq 0 ]; then
        make_args=(help)
    fi

    log_info "Handing over to make: make ${make_args[*]}"
    echo "------------------------------------------------------------"
    exec make "${make_args[@]}"

else
    # === 원격 실행 (부트스트랩) 모드 ===
    # 프로젝트가 없는 상태에서 'curl | bash'로 실행된 경우
    log_info "Bootstrap mode detected (no git repo)"
    # 우선 .ums-version이 있다면 그 버전을, 없다면 최신 릴리즈를 사용
    DESIRED_VERSION=""
    if [ -f ".ums-version" ]; then
        DESIRED_VERSION="$(cat .ums-version)"
        log_info "Found .ums-version: ${DESIRED_VERSION}"
    else
        DESIRED_VERSION="$(fetch_latest_release_tag || true)"
        if [ -z "${DESIRED_VERSION}" ]; then
            log_warn "Could not resolve latest release via API. Falling back to main branch archive."
            DESIRED_VERSION="${MAIN_BRANCH}"
            # main snapshot URL path differs slightly; handled below by special-case
        else
            log_info "Resolved latest release tag: ${DESIRED_VERSION}"
        fi
    fi

    if [ -n "${CLI_VERSION}" ]; then
        DESIRED_VERSION="${CLI_VERSION}"
        log_info "CLI version specified: ${DESIRED_VERSION}"
    fi

    if [ "${DESIRED_VERSION}" = "${MAIN_BRANCH}" ]; then
        # Main snapshot fallback
        log_info "Initializing from branch snapshot: ${MAIN_BRANCH} (not a tagged release)"
        TMPDIR="$(mktemp -d)" || { log_warn "Failed to create temp directory"; exit 1; }
        cleanup_tmp_branch() { rm -rf "${TMPDIR}" >/dev/null 2>&1 || true; }
        trap cleanup_tmp_branch EXIT INT TERM
        # 토큰이 있으면 API tarball을 사용하여 private 레포에서도 동작하도록 함
        auth_args=()
        if [[ -n "${GITHUB_TOKEN:-}" ]]; then
            SNAP_PRIMARY="https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/tarball/${MAIN_BRANCH}"
            SNAP_MIRROR="${SNAP_PRIMARY}"
            auth_args=(-H "Authorization: Bearer ${GITHUB_TOKEN}" -H "X-GitHub-Api-Version: 2022-11-28" -H "Accept: application/vnd.github+json")
        else
            SNAP_PRIMARY="https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}/archive/refs/heads/${MAIN_BRANCH}.tar.gz"
            SNAP_MIRROR="https://codeload.github.com/${GITHUB_OWNER}/${GITHUB_REPO}/tar.gz/refs/heads/${MAIN_BRANCH}"
        fi
        TARBALL_PATH="${TMPDIR}/repo.tar.gz"
        success=0
        for src in primary mirror; do
            url="$([ "$src" = "primary" ] && echo "${SNAP_PRIMARY}" || echo "${SNAP_MIRROR}")"
            for attempt in $(seq 1 ${CURL_RETRY_MAX}); do
                log_info "Downloading snapshot (${src} try ${attempt}/${CURL_RETRY_MAX}): ${url}"
                if curl -fSL --connect-timeout 10 --max-time 300 "${auth_args[@]}" -o "${TARBALL_PATH}" "${url}"; then
                    if [ -s "${TARBALL_PATH}" ]; then success=1; break; fi
                fi
                sleep $((CURL_RETRY_DELAY_SEC * (2 ** (attempt - 1)))) || sleep ${CURL_RETRY_DELAY_SEC}
            done
            [ "$success" = "1" ] && break
        done
        [ "$success" != "1" ] && log_warn "Failed to download branch snapshot." && exit 1
        tar -xzf "${TARBALL_PATH}" -C "${TMPDIR}"
        set +o pipefail
        ROOT_DIR_NAME_FALLBACK="$(tar -tzf "${TARBALL_PATH}" 2>/dev/null | head -n1 | cut -d/ -f1 || true)"
        set -o pipefail
        [ -z "${ROOT_DIR_NAME_FALLBACK}" ] && log_warn "Extracted directory not found." && exit 1
        if [ -e "${GITHUB_REPO}" ]; then
            # 이미 존재하면 현재/최신 버전 로그만
            current_bootstrap=""
            if [ -f "${GITHUB_REPO}/.ums-release-version" ]; then
                current_bootstrap="$(cat "${GITHUB_REPO}/.ums-release-version")"
            elif [ -f "${GITHUB_REPO}/VERSION" ]; then
                current_bootstrap="$(tr -d '\n\r' < "${GITHUB_REPO}/VERSION")"
            fi
            log_warn "Target directory '${GITHUB_REPO}' already exists."
            [ -n "${current_bootstrap}" ] && log_info "Current installed release: ${current_bootstrap}"
            log_info "Latest available release: ${DESIRED_VERSION}"
            if is_true "${FORCE_UPDATE}"; then
                log_info "--force specified: updating in place..."
                update_repo_from_release "${DESIRED_VERSION}"
            else
                log_warn "Run with --force to overwrite/update the existing directory."
            fi
            exit 1
        fi
        mv "${TMPDIR}/${ROOT_DIR_NAME_FALLBACK}" "${GITHUB_REPO}"
        log_success "Project downloaded to '${GITHUB_REPO}' from branch ${MAIN_BRANCH}."
        # 내부 install.sh 대신 현재 스크립트의 설치 함수로 .makefile-system 통합
        (
          cd "${GITHUB_REPO}" &&
          DESIRED_SYS_TAG="$(fetch_latest_release_tag || true)"
          if [ -n "${DESIRED_SYS_TAG}" ]; then
            log_info "Installing Makefile system via release ${DESIRED_SYS_TAG}..."
            install_from_release "${DESIRED_SYS_TAG}"
            scaffold_project_files
          else
            log_warn "Failed to resolve latest release for Makefile system; skipping integration."
          fi
        )
    else
        # Release-archive bootstrap
        if [ -e "${GITHUB_REPO}" ]; then
            current_bootstrap=""
            if [ -f "${GITHUB_REPO}/.ums-release-version" ]; then
                current_bootstrap="$(cat "${GITHUB_REPO}/.ums-release-version")"
            elif [ -f "${GITHUB_REPO}/VERSION" ]; then
                current_bootstrap="$(tr -d '\n\r' < "${GITHUB_REPO}/VERSION")"
            fi
            log_warn "Target directory '${GITHUB_REPO}' already exists."
            [ -n "${current_bootstrap}" ] && log_info "Current installed release: ${current_bootstrap}"
            log_info "Desired release: ${DESIRED_VERSION}"
            if is_true "${FORCE_UPDATE}"; then
                log_info "--force specified: updating in place..."
                update_repo_from_release "${DESIRED_VERSION}"
            else
                if prompt_confirm "Overwrite existing directory with release ${DESIRED_VERSION}?"; then
                    update_repo_from_release "${DESIRED_VERSION}"
                else
                    log_info "Skipping update."
                fi
            fi
        else
            install_repo_from_release "${DESIRED_VERSION}"
            # 내부 install.sh 대신 현재 스크립트의 설치 함수로 .makefile-system 통합
            (
              cd "${GITHUB_REPO}" &&
              log_info "Installing Makefile system via release ${DESIRED_VERSION}..."
              install_from_release "${DESIRED_VERSION}"
              scaffold_project_files
            )
        fi

        # 안전망: 상위에서 한 번 더 스캐폴드 보장
        if [ -d "${GITHUB_REPO}" ]; then
            (
              cd "${GITHUB_REPO}" &&
              [ -f "project.mk" ] || scaffold_project_files
            )
        fi
    fi

    echo ""
    log_info "Next steps:"
    echo "1. cd ${GITHUB_REPO}"
    echo "2. make help"
fi



# #!/bin/bash
# set -e
# MAKEFILE_SYSTEM_CHECK_FILE=".makefile-system/Makefile.universal"
# if [ ! -f "${MAKEFILE_SYSTEM_CHECK_FILE}" ]; then
#     echo "⚠️  Makefile system not found. Initializing submodule..."
#     git submodule update --init --recursive
# fi
# exec make "$@"