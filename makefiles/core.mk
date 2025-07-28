# ================================================================
# Core Functions and Variables
# ================================================================

# 기본 변수들 (project.mk에서 오버라이드 가능)
REPO_HUB ?= defaultrepo
NAME ?= defaultapp
VERSION ?= v1.0.0
TAGNAME ?= $(VERSION)

# Git 브랜치 설정 (project.mk에서 오버라이드 가능)
MAIN_BRANCH ?= main
DEVELOP_BRANCH ?= develop

# 계산된 변수들
CURRENT_BRANCH := $(shell git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
IMAGE_NAME := $(REPO_HUB)/$(NAME)
APP_IMAGE_NAME := $(REPO_HUB)/$(NAME)-app
FULL_TAG := $(APP_IMAGE_NAME):$(TAGNAME)
LATEST_TAG := $(APP_IMAGE_NAME):latest

# Docker 빌드 옵션
DOCKER_BUILDKIT ?= 1
BUILDKIT_INLINE_CACHE ?= 1
DOCKER_BUILD_OPTION ?= --rm=true

# 조건부 빌드 옵션
ifeq ($(DEBUG), true)
    DOCKER_BUILD_OPTION += --progress=plain
endif

ifeq ($(FORCE_REBUILD), true)
    DOCKER_BUILD_OPTION += --no-cache
endif

# Docker 파일 경로 (project.mk에서 오버라이드 가능)
DOCKERFILE_PATH ?= docker/Dockerfile.app

# 색상 설정 (CI 환경 고려)
ifeq ($(CI),true)
    GREEN :=
    YELLOW :=
    BLUE :=
    RED :=
    RESET :=
else
    GREEN := $(shell tput setaf 2 2>/dev/null || echo "")
    YELLOW := $(shell tput setaf 3 2>/dev/null || echo "")
    BLUE := $(shell tput setaf 4 2>/dev/null || echo "")
    RED := $(shell tput setaf 1 2>/dev/null || echo "")
    RESET := $(shell tput sgr0 2>/dev/null || echo "")
endif

# 플랫폼별 SED 설정
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
	SED = sed -E -i ''
else
	SED = sed -i
endif

# ================================================================
# 공통 함수들
# ================================================================

# 색상 출력 함수
define colorecho
@if [ -n "$(GREEN)" ]; then \
    echo "$(GREEN)$(1)$(RESET)"; \
else \
    echo "--- $(1) ---"; \
fi
endef

# 경고 메시지 함수
define warn
@if [ -n "$(YELLOW)" ]; then \
    echo "$(YELLOW)⚠️  $(1)$(RESET)"; \
else \
    echo "WARNING: $(1)"; \
fi
endef

# 에러 메시지 함수
define error
@if [ -n "$(RED)" ]; then \
    echo "$(RED)❌ $(1)$(RESET)" >&2; \
else \
    echo "ERROR: $(1)" >&2; \
fi
endef

# 성공 메시지 함수
define success
@if [ -n "$(GREEN)" ]; then \
    echo "$(GREEN)✅ $(1)$(RESET)"; \
else \
    echo "SUCCESS: $(1)"; \
fi
endef

# 시간 측정 함수
define timed_command
@echo "⏰ Starting: $(1)"; \
start_time=$$(date +%s); \
$(2); \
end_time=$$(date +%s); \
duration=$$((end_time - start_time)); \
$(call success, "Completed '$(1)' in $${duration}s")
endef

# 필수 명령어 확인 함수
define check_command
@command -v $(1) >/dev/null 2>&1 || ($(call error, "$(1) is required but not installed") && exit 1)
endef

# Docker 실행 상태 확인
define check_docker
@docker info >/dev/null 2>&1 || ($(call error, "Docker is not running") && exit 1)
endef

# Git 작업 디렉토리 정리 상태 확인
define check_git_clean
@git diff --quiet || ($(call warn, "Working directory has uncommitted changes") && exit 1)
endef

# Git 브랜치 확인
define check_branch
@CURRENT=$$(git rev-parse --abbrev-ref HEAD 2>/dev/null); \
if [ "$$CURRENT" != "$(1)" ]; then \
    $(call error, "You must be on '$(1)' branch (currently on '$$CURRENT')"); \
    exit 1; \
fi
endef

# ================================================================
# 기본 검증 타겟들
# ================================================================

.PHONY: check-deps check-docker check-git-clean

check-deps: ## 🔧 Check if required tools are installed
	$(call check_command, docker)
	$(call check_command, git)
	@$(call success, "All required tools are available")

check-docker: ## 🔧 Check if Docker is running
	$(call check_docker)
	@$(call success, "Docker is running")

check-git-clean: ## 🔧 Check if working directory is clean
	$(call check_git_clean)
	@$(call success, "Working directory is clean")

# ================================================================
# 디버깅 타겟들
# ================================================================

debug-vars: ## 🔧 Show all Makefile variables
	@echo "$(BLUE)Core Variables:$(RESET)"
	@echo "  REPO_HUB: $(REPO_HUB)"
	@echo "  NAME: $(NAME)"
	@echo "  VERSION: $(VERSION)"
	@echo "  TAGNAME: $(TAGNAME)"
	@echo "  IMAGE_NAME: $(IMAGE_NAME)"
	@echo "  APP_IMAGE_NAME: $(APP_IMAGE_NAME)"
	@echo "  FULL_TAG: $(FULL_TAG)"
	@echo "  LATEST_TAG: $(LATEST_TAG)"
	@echo ""
	@echo "$(BLUE)Git Configuration:$(RESET)"
	@echo "  CURRENT_BRANCH: $(CURRENT_BRANCH)"
	@echo "  MAIN_BRANCH: $(MAIN_BRANCH)"
	@echo "  DEVELOP_BRANCH: $(DEVELOP_BRANCH)"
	@echo ""
	@echo "$(BLUE)Docker Configuration:$(RESET)"
	@echo "  DOCKERFILE_PATH: $(DOCKERFILE_PATH)"
	@echo "  DOCKER_BUILD_OPTION: $(DOCKER_BUILD_OPTION)"
	@echo "  DOCKER_BUILDKIT: $(DOCKER_BUILDKIT)"
	@echo ""
	@echo "$(BLUE)Environment:$(RESET)"
	@echo "  ENV: $(ENV)"
	@echo "  CI: $(CI)"
	@echo "  DEBUG: $(DEBUG)"
	@echo "  FORCE_REBUILD: $(FORCE_REBUILD)"