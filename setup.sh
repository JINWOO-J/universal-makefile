#!/bin/bash
# A smart setup script for the Universal Makefile System.
# - When run via 'curl | bash', it clones the project.
# - When run locally, it prepares dependencies and executes 'make'.

set -euo pipefail

# --- 설정 (프로젝트에 맞게 수정) ---
GITHUB_OWNER="jinwoo-j"
GITHUB_REPO="universal-makefile" # 여기에 실제 사용할 '부모' 프로젝트 리포지토리 이름을 넣습니다.
MAIN_BRANCH="master"
MAKEFILE_SYSTEM_DIR=".makefile-system"

# --- 로깅 함수 ---
# (이전 스크립트와 동일한 log_info, log_success 등을 여기에 포함)
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
    RED=$(tput setaf 1); GREEN=$(tput setaf 2); YELLOW=$(tput setaf 3); BLUE=$(tput setaf 4); RESET=$(tput sgr0)
else
    RED=""; GREEN=""; YELLOW=""; BLUE=""; RESET=""
fi
log_info()    { echo -e "${BLUE}ℹ️  $1${RESET}"; }
log_success() { echo -e "${GREEN}✅ $1${RESET}"; }
log_warn()    { echo -e "${YELLOW}⚠️  $1${RESET}"; }

# --- 핵심 로직 ---

# --- 다운로드/검증 유틸 ---
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
        # macOS
        echo "${expected}  ${file_path}" | shasum -a 256 -c --status
        return $?
    else
        return 3
    fi
}

# 현재 디렉토리가 Git 리포지토리인지 확인
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # === 로컬 실행 모드 ===
    # 이미 프로젝트가 clone된 상태에서 실행된 경우
    
    log_info "Project repository found. Verifying Makefile system..."

    # 1. GitHub Release 방식인지 확인 (버전 파일 존재 여부)
    if [ -f ".ums-version" ]; then
        DESIRED_VERSION=$(cat .ums-version)
        if [ -f "${MAKEFILE_SYSTEM_DIR}/.version" ]; then
            CURRENT_VERSION="$(cat "${MAKEFILE_SYSTEM_DIR}/.version")"
        else
            CURRENT_VERSION=""
        fi
        if [[ "${CURRENT_VERSION}" != "${DESIRED_VERSION}" ]]; then
            log_warn "Makefile system is missing or out of date. Installing version ${DESIRED_VERSION}..."
            # 준비: 임시 작업 디렉토리
            TMPDIR="$(mktemp -d)" || {
                log_warn "Failed to create temp directory"; exit 1;
            }
            cleanup_tmp() { rm -rf "${TMPDIR}" >/dev/null 2>&1 || true; }
            trap cleanup_tmp EXIT INT TERM

            PRIMARY_URL="https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}/archive/refs/tags/${DESIRED_VERSION}.tar.gz"
            MIRROR_URL="https://codeload.github.com/${GITHUB_OWNER}/${GITHUB_REPO}/tar.gz/refs/tags/${DESIRED_VERSION}"
            TARBALL_PATH="${TMPDIR}/umf.tar.gz"

            # 재시도 포함 다운로드 (기본 URL → 미러 URL)
            success=0
            for src in primary mirror; do
                url="$([ "$src" = "primary" ] && echo "${PRIMARY_URL}" || echo "${MIRROR_URL}")"
                for attempt in $(seq 1 ${CURL_RETRY_MAX}); do
                    log_info "Downloading (${src} try ${attempt}/${CURL_RETRY_MAX}): ${url}"
                    if curl -fSL --connect-timeout 10 --max-time 300 -o "${TARBALL_PATH}" "${url}"; then
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
                log_warn "Failed to download release tarball for ${DESIRED_VERSION}."
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
            VERSION_DIR_NAME="${GITHUB_REPO}-${DESIRED_VERSION#v}"
            if [ ! -d "${TMPDIR}/${VERSION_DIR_NAME}" ]; then
                # 혹시 다른 아카이브 구조 대비: 첫 번째 디렉토리를 추정
                VERSION_DIR_NAME_FALLBACK="$(tar -tzf "${TARBALL_PATH}" | head -1 | cut -d/ -f1)"
                if [ -n "${VERSION_DIR_NAME_FALLBACK}" ] && [ -d "${TMPDIR}/${VERSION_DIR_NAME_FALLBACK}" ]; then
                    VERSION_DIR_NAME="${VERSION_DIR_NAME_FALLBACK}"
                else
                    log_warn "Extracted directory not found. Aborting."
                    exit 1
                fi
            fi
            mv "${TMPDIR}/${VERSION_DIR_NAME}" "${MAKEFILE_SYSTEM_DIR}"
            echo "${DESIRED_VERSION}" > "${MAKEFILE_SYSTEM_DIR}/.version"
            log_success "Makefile system version ${DESIRED_VERSION} is now ready."
        else
            log_success "Makefile system version ${DESIRED_VERSION} is up to date."
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
    fi

    log_info "Handing over to make: make $@"
    echo "------------------------------------------------------------"
    exec make "$@"

else
    # === 원격 실행 (부트스트랩) 모드 ===
    # 프로젝트가 없는 상태에서 'curl | bash'로 실행된 경우
    
    log_info "Project not found. Cloning from GitHub..."
    
    # 여기서 프로젝트의 기본 설치 방식에 따라 clone 명령어를 선택할 수 있습니다.
    # 예: Submodule을 기본으로 할 경우
    git clone --recurse-submodules "https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}.git"
    
    log_success "Project cloned successfully into '${GITHUB_REPO}' directory."
    echo ""
    log_info "Next steps:"
    echo "1. cd ${GITHUB_REPO}"
    echo "2. ./setup.sh"
fi



# #!/bin/bash
# set -e
# MAKEFILE_SYSTEM_CHECK_FILE=".makefile-system/Makefile.universal"
# if [ ! -f "${MAKEFILE_SYSTEM_CHECK_FILE}" ]; then
#     echo "⚠️  Makefile system not found. Initializing submodule..."
#     git submodule update --init --recursive
# fi
# exec make "$@"