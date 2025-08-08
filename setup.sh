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

# 현재 디렉토리가 Git 리포지토리인지 확인
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # === 로컬 실행 모드 ===
    # 이미 프로젝트가 clone된 상태에서 실행된 경우
    
    log_info "Project repository found. Verifying Makefile system..."

    # 1. GitHub Release 방식인지 확인 (버전 파일 존재 여부)
    if [ -f ".ums-version" ]; then
        DESIRED_VERSION=$(cat .ums-version)
        CURRENT_VERSION=$([ -f "${MAKEFILE_SYSTEM_DIR}/.version" ] && cat "${MAKEFILE_SYSTEM_DIR}/.version")
        if [[ "${CURRENT_VERSION}" != "${DESIRED_VERSION}" ]]; then
            log_warn "Makefile system is missing or out of date. Installing version ${DESIRED_VERSION}..."
            rm -rf "${MAKEFILE_SYSTEM_DIR}"
            local ARCHIVE_URL="https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}/archive/refs/tags/${DESIRED_VERSION}.tar.gz"
            curl -fsSL "${ARCHIVE_URL}" | tar -xz
            mv "${GITHUB_REPO}-${DESIRED_VERSION:1}" "${MAKEFILE_SYSTEM_DIR}"
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