#!/bin/bash

# ================================================================
# Universal Makefile System - Installation Script
# ================================================================

set -euo pipefail

# 색상 정의
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    BLUE=$(tput setaf 4)
    RESET=$(tput sgr0)
else
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    RESET=""
fi

# 로깅 함수들
log_info() {
    echo "${BLUE}ℹ️  $1${RESET}"
}

log_success() {
    echo "${GREEN}✅ $1${RESET}"
}

log_warn() {
    echo "${YELLOW}⚠️  $1${RESET}"
}

log_error() {
    echo "${RED}❌ $1${RESET}" >&2
}

# 설치 설정
REPO_URL="https://github.com/company/universal-makefile"
MAKEFILE_DIR=".makefile-system"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
INSTALLATION_TYPE=""
FORCE_INSTALL=false
EXISTING_PROJECT=false

# 사용법 표시
usage() {
    cat << EOF
Universal Makefile System Installation Script

Usage: $0 [OPTIONS]

OPTIONS:
    --submodule         Install as git submodule (recommended)
    --copy              Install by copying files
    --existing-project  Setup in existing project (preserve existing files)
    --force             Force installation (overwrite existing files)
    -h, --help          Show this help message

EXAMPLES:
    # New project with submodule (recommended)
    $0 --submodule

    # Existing project setup
    $0 --submodule --existing-project

    # Copy files instead of submodule
    $0 --copy

    # Force reinstall
    $0 --force --copy

For more information, visit: $REPO_URL
EOF
}

# 명령행 인수 처리
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --submodule)
                INSTALLATION_TYPE="submodule"
                shift
                ;;
            --copy)
                INSTALLATION_TYPE="copy"
                shift
                ;;
            --existing-project)
                EXISTING_PROJECT=true
                shift
                ;;
            --force)
                FORCE_INSTALL=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    # 기본값 설정
    if [[ -z "$INSTALLATION_TYPE" ]]; then
        if git rev-parse --git-dir >/dev/null 2>&1; then
            INSTALLATION_TYPE="submodule"
            log_info "Git repository detected, defaulting to submodule installation"
        else
            INSTALLATION_TYPE="copy"
            log_info "No git repository, defaulting to copy installation"
        fi
    fi
}

# 사전 요구사항 확인
check_requirements() {
    log_info "Checking requirements..."

    # Git 확인 (submodule 방식인 경우)
    if [[ "$INSTALLATION_TYPE" == "submodule" ]]; then
        if ! command -v git >/dev/null 2>&1; then
            log_error "Git is required for submodule installation"
            exit 1
        fi

        if ! git rev-parse --git-dir >/dev/null 2>&1; then
            log_error "Not in a git repository. Initialize git first or use --copy option"
            exit 1
        fi
    fi

    # Docker 확인 (선택사항이지만 권장)
    if ! command -v docker >/dev/null 2>&1; then
        log_warn "Docker not found. The makefile system works best with Docker"
    fi

    # Make 확인
    if ! command -v make >/dev/null 2>&1; then
        log_error "Make is required"
        exit 1
    fi

    log_success "Requirements check passed"
}

# 기존 설치 확인
check_existing_installation() {
    local has_existing=false

    if [[ -d "$MAKEFILE_DIR" ]]; then
        log_warn "Submodule installation detected at $MAKEFILE_DIR"
        has_existing=true
    fi

    if [[ -d "makefiles" ]]; then
        log_warn "Copy installation detected (makefiles/ directory exists)"
        has_existing=true
    fi

    if [[ -f "Makefile" && ! "$EXISTING_PROJECT" == true ]]; then
        log_warn "Existing Makefile detected"
        has_existing=true
    fi

    if [[ "$has_existing" == true && "$FORCE_INSTALL" == false && "$EXISTING_PROJECT" != true ]]; then
        echo ""
        log_warn "Existing installation detected. Options:"
        echo "  1. Use --force to overwrite"
        echo "  2. Use --existing-project to preserve existing files"
        echo "  3. Manually remove existing files first"
        exit 1
    fi

}

# Submodule 방식 설치
install_submodule() {
    log_info "Installing as git submodule..."

    # 기존 submodule 제거 (force 모드인 경우)
    if [[ "$FORCE_INSTALL" == true && -d "$MAKEFILE_DIR" ]]; then
        log_info "Removing existing submodule..."
        git submodule deinit -f "$MAKEFILE_DIR" 2>/dev/null || true
        git rm -f "$MAKEFILE_DIR" 2>/dev/null || true
        rm -rf ".git/modules/$MAKEFILE_DIR" 2>/dev/null || true
        rm -rf "$MAKEFILE_DIR" 2>/dev/null || true
    fi

    # Submodule 추가
    if ! git submodule add "$REPO_URL" "$MAKEFILE_DIR" 2>/dev/null; then
        # 이미 서브모듈이 있는지 확인
        if git config --file .gitmodules --get "submodule.$MAKEFILE_DIR.url" >/dev/null 2>&1; then
            log_info "Submodule already exists, continuing with installation..."
        else
            log_error "Failed to add submodule. Repository might not exist."
            exit 1
        fi
    fi


    # Submodule 초기화 및 업데이트
    git submodule update --init --recursive

    log_success "Submodule installation completed"
}

# Copy 방식 설치
install_copy() {
    log_info "Installing by copying files..."

    # 임시 디렉토리 생성
    local temp_dir=$(mktemp -d)
    trap "rm -rf $temp_dir" EXIT

    # 소스 결정 (현재 스크립트가 repo에서 실행되는 경우 vs 원격에서 다운로드하는 경우)
    if [[ -f "$SCRIPT_DIR/makefiles/core.mk" ]]; then
        # 로컬 repo에서 실행
        log_info "Using local repository files"
        local source_dir="$SCRIPT_DIR"
    else
        # 원격에서 다운로드
        log_info "Downloading from $REPO_URL"
        if command -v git >/dev/null 2>&1; then
            git clone "$REPO_URL" "$temp_dir/universal-makefile"
            local source_dir="$temp_dir/universal-makefile"
        else
            log_error "Git is required to download the repository"
            exit 1
        fi
    fi

    # 파일 복사
    if [[ "$FORCE_INSTALL" == true || ! -d "makefiles" ]]; then
        log_info "Copying makefiles..."
        cp -r "$source_dir/makefiles" .
    fi

    if [[ "$FORCE_INSTALL" == true || ! -d "scripts" ]]; then
        log_info "Copying scripts..."
        cp -r "$source_dir/scripts" . 2>/dev/null || true
    fi

    if [[ "$FORCE_INSTALL" == true || ! -d "templates" ]]; then
        log_info "Copying templates..."
        cp -r "$source_dir/templates" . 2>/dev/null || true
    fi

    # 버전 파일 복사
    if [[ -f "$source_dir/VERSION" ]]; then
        cp "$source_dir/VERSION" .
    fi

    log_success "Copy installation completed"
}

# 메인 Makefile 생성
create_main_makefile() {
    local makefile_content

    if [[ "$EXISTING_PROJECT" == true && -f "Makefile" ]]; then
        log_info "Existing Makefile detected, creating Makefile.universal as backup"
        local target_file="Makefile.universal"
    else
        local target_file="Makefile"
    fi

    log_info "Creating $target_file..."

    # Makefile 내용 생성
    cat > "$target_file" << 'EOF'
# ================================================================
# Universal Makefile System - Main Entry Point
# ================================================================

.DEFAULT_GOAL := help

# 설치 방식 자동 감지
ifneq (,$(wildcard .makefile-system/))
    # Submodule 방식
    MAKEFILE_DIR := .makefile-system
    MAKEFILE_TYPE := submodule
else ifneq (,$(wildcard makefiles/core.mk))
    # Script 설치 방식
    MAKEFILE_DIR := .
    MAKEFILE_TYPE := script
else
    $(error Universal Makefile System not found. Please run install script first.)
endif

# 프로젝트 설정 로드 (필수)
ifeq (,$(wildcard project.mk))
    $(error project.mk not found. Please create it from template: cp $(MAKEFILE_DIR)/templates/project.mk.template project.mk)
endif
include project.mk

# 환경별 설정 로드 (선택)
ENV ?= development
-include environments/$(ENV).mk

# 로컬 개발자 설정 로드 (선택, 최고 우선순위)
-include .project.local.mk

# 공통 모듈들 로드 (순서 중요!)
include $(MAKEFILE_DIR)/makefiles/core.mk
include $(MAKEFILE_DIR)/makefiles/help.mk
include $(MAKEFILE_DIR)/makefiles/version.mk
include $(MAKEFILE_DIR)/makefiles/docker.mk
include $(MAKEFILE_DIR)/makefiles/compose.mk
include $(MAKEFILE_DIR)/makefiles/git-flow.mk
include $(MAKEFILE_DIR)/makefiles/cleanup.mk

# 메인 타겟들 정의
.PHONY: all release

all: env update-version build ## 🎯 Build everything (env + version + build)
release: all push tag-latest ## 🚀 Full release process (build + push + tag latest)

# 시스템 관리 타겟들
update-makefile-system: ## 🔧 Update makefile system
ifeq ($(MAKEFILE_TYPE),submodule)
	@$(call colorecho, "🔄 Updating makefile system via git submodule...")
	@git submodule update --remote $(MAKEFILE_DIR)
	@$(call colorecho, "✅ Makefile system updated successfully")
else
	@$(call colorecho, "⚠️  Script installation detected. Please run install.sh manually to update")
endif

show-makefile-info: ## 🔧 Show makefile system information
	@echo "$(BLUE)Makefile System Information:$(RESET)"
	@echo "  Installation Type: $(MAKEFILE_TYPE)"
	@echo "  Makefile Directory: $(MAKEFILE_DIR)"
	@echo "  System Version: $(shell cat $(MAKEFILE_DIR)/VERSION 2>/dev/null || echo 'unknown')"
	@echo "  Project: $(NAME) v$(VERSION)"

# 프로젝트별 커스텀 타겟들은 여기 아래에 추가
# 예시:
# custom-deploy: ## 🚀 Deploy to custom infrastructure
# 	@echo "Custom deployment for $(NAME)..."
EOF

    log_success "$target_file created"
}

# 프로젝트 설정 파일 생성
create_project_config() {
    if [[ -f "project.mk" && "$FORCE_INSTALL" == false ]]; then
        log_info "project.mk already exists, skipping..."
        return
    fi

    log_info "Creating project.mk..."

    # 현재 디렉토리 이름을 기본 프로젝트명으로 사용
    local default_name=$(basename "$(pwd)")

    # Git 원격 URL에서 정보 추출 시도
    local default_repo_hub="mycompany"
    if git remote get-url origin >/dev/null 2>&1; then
        local remote_url=$(git remote get-url origin)
        if [[ "$remote_url" =~ github.com[:/]([^/]+) ]]; then
            default_repo_hub="${BASH_REMATCH[1]}"
        elif [[ "$remote_url" =~ ([^/]+)/[^/]+\.git$ ]]; then
            default_repo_hub="${BASH_REMATCH[1]}"
        fi
    fi

    cat > "project.mk" << EOF
# ================================================================
# Project-specific configuration
# ================================================================

# 프로젝트 기본 정보 (필수)
REPO_HUB = $default_repo_hub
NAME = $default_name
VERSION = v1.0.0

# Git 브랜치 설정
MAIN_BRANCH = main
DEVELOP_BRANCH = develop

# Docker 설정
DOCKERFILE_PATH = Dockerfile
DOCKER_BUILD_ARGS =

# Docker Compose 설정
COMPOSE_FILE = docker-compose.yml
DEV_COMPOSE_FILE = docker-compose.dev.yml
PROD_COMPOSE_FILE = docker-compose.prod.yml

# 프로젝트별 커스텀 타겟들
# custom-deploy: ## 🚀 Deploy to custom infrastructure
# 	@echo "Deploying \$(NAME) to custom infrastructure..."
# 	# 프로젝트별 배포 로직 추가

# custom-test: ## 🧪 Run project-specific tests
# 	@echo "Running custom tests for \$(NAME)..."
# 	# 프로젝트별 테스트 로직 추가
EOF

    log_success "project.mk created with defaults"
    log_info "Please edit project.mk to match your project configuration"
}

# .gitignore 업데이트
update_gitignore() {
    log_info "Updating .gitignore..."

    local gitignore_entries=(
        "# Universal Makefile System"
        ".project.local.mk"
        ".NEW_VERSION.tmp"
        ".env"
        "environments/*.local.mk"
    )

    if [[ ! -f .gitignore ]]; then
        log_info "Creating .gitignore..."
        touch .gitignore
    fi

    for entry in "${gitignore_entries[@]}"; do
        if ! grep -q "^$entry$" .gitignore 2>/dev/null; then
            echo "$entry" >> .gitignore
        fi
    done

    log_success ".gitignore updated"
}

# 환경 디렉토리 생성
create_environments() {
    if [[ -d "environments" && "$FORCE_INSTALL" == false ]]; then
        log_info "environments/ directory already exists, skipping..."
        return
    fi

    log_info "Creating environments directory..."
    mkdir -p environments

    # 개발 환경 설정
    cat > "environments/development.mk" << 'EOF'
# ================================================================
# Development environment configuration
# ================================================================

# 개발환경 전용 설정
DEBUG = true
DOCKER_BUILD_OPTION += --progress=plain

# 개발용 Docker Compose 파일
COMPOSE_FILE = docker-compose.dev.yml

# 개발환경 전용 타겟들
dev-watch: ### Watch for changes and rebuild
	@$(call colorecho, "👀 Watching for changes...")
	@while inotifywait -r -e modify,create,delete .; do \
		make build; \
	done
EOF

    # 프로덕션 환경 설정
    cat > "environments/production.mk" << 'EOF'
# ================================================================
# Production environment configuration
# ================================================================

# 프로덕션 설정
DEBUG = false
DOCKER_BUILD_OPTION += --no-cache

# 프로덕션용 Docker Compose 파일
COMPOSE_FILE = docker-compose.prod.yml

# 프로덕션 검증 타겟들
prod-deploy: check-git-clean build test ## 🚀 Production deployment
	@echo "Deploying to production..."
	# 프로덕션 배포 로직 추가
EOF

    log_success "Environment configurations created"
}

# 샘플 Docker Compose 파일 생성
create_sample_compose() {
    if [[ -f "docker-compose.yml" && "$FORCE_INSTALL" == false ]]; then
        log_info "docker-compose.yml already exists, skipping..."
        return
    fi

    log_info "Creating sample docker-compose.yml..."

    cat > "docker-compose.yml" << 'EOF'
version: '3.8'

services:
  app:
    build: .
    ports:
      - "3000:3000"
    environment:
      - NODE_ENV=production
    restart: unless-stopped

  # 추가 서비스들을 여기에 정의
  # db:
  #   image: postgres:13
  #   environment:
  #     POSTGRES_DB: myapp
  #     POSTGRES_USER: user
  #     POSTGRES_PASSWORD: password
  #   volumes:
  #     - postgres_data:/var/lib/postgresql/data

# volumes:
#   postgres_data:
EOF

    log_success "Sample docker-compose.yml created"
}

# 설치 완료 메시지
show_completion_message() {
    echo ""
    log_success "🎉 Universal Makefile System installation completed!"
    echo ""
    echo "${BLUE}Next steps:${RESET}"
    echo "  1. Edit project.mk to configure your project"
    echo "  2. Create/update your Dockerfile if needed"
    echo "  3. Run 'make help' to see available commands"
    echo "  4. Run 'make getting-started' for a quick guide"
    echo ""
    echo "${BLUE}Quick start:${RESET}"
    echo "  make help                 # Show all available commands"
    echo "  make build                # Build your application"
    echo "  make getting-started      # Show detailed getting started guide"
    echo ""

    if [[ "$INSTALLATION_TYPE" == "submodule" ]]; then
        echo "${BLUE}Submodule management:${RESET}"
        echo "  make update-makefile-system  # Update to latest version"
        echo "  git submodule update --remote .makefile-system  # Manual update"
        echo ""
    fi

    if [[ "$EXISTING_PROJECT" == true ]]; then
        log_warn "Existing project detected:"
        echo "  - Original Makefile preserved (if it existed)"
        echo "  - New system available as Makefile.universal (if applicable)"
        echo "  - Please merge any existing make targets into the new system"
        echo ""
    fi

    echo "${YELLOW}Documentation: $REPO_URL${RESET}"
}

# 메인 실행 함수
main() {
    echo ""
    echo "${BLUE}🔧 Universal Makefile System Installer${RESET}"
    echo ""

    parse_args "$@"
    check_requirements
    check_existing_installation

    case "$INSTALLATION_TYPE" in
        "submodule")
            install_submodule
            ;;
        "copy")
            install_copy
            ;;
        *)
            log_error "Invalid installation type: $INSTALLATION_TYPE"
            exit 1
            ;;
    esac

    create_main_makefile
    create_project_config
    update_gitignore
    create_environments

    # 샘플 파일들 (기존 프로젝트가 아닌 경우에만)
    if [[ "$EXISTING_PROJECT" == false ]]; then
        create_sample_compose
    fi

    show_completion_message
}

# 스크립트 실행
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
