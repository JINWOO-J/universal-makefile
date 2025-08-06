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
APP_IMAGE_NAME := $(REPO_HUB)/$(NAME)
FULL_TAG := $(APP_IMAGE_NAME):$(TAGNAME)
LATEST_TAG := $(APP_IMAGE_NAME):latest

# Docker 빌드 옵션
DOCKER_BUILDKIT ?= 1
BUILDKIT_INLINE_CACHE ?= 1
DOCKER_BUILD_OPTION ?= --rm=true

ARGS := $(filter-out self-update,$(MAKECMDGOALS))


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
	ECHO_OPTION = ""
else
	SED = sed -i
	ECHO_OPTION = "-e"
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

define warn_echo
if [ -n "$(YELLOW)" ]; then \
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

define error_echo
if [ -n "$(RED)" ]; then \
    echo "$(RED)❌ $(1)$(RESET)" >&2; \
else \
    echo "ERROR: $(1)" >&2; \
fi
endef


# 성공 메시지 함수
define success_echo
if [ -n "$(GREEN)" ]; then \
    echo "$(GREEN)✅ $(1)$(RESET)"; \
else \
    echo "SUCCESS: $(1)"; \
fi
endef

# 시간 측정 함수
# define timed_command
# @echo "⏰ Starting: $(1) -> $(2)"; \
# echo "------------------------------------------------------------";\
# start_time=$$(date +%s); \
# $(2); \
# end_time=$$(date +%s); \
# duration=$$((end_time - start_time)); \
# echo "------------------------------------------------------------";\
# $(call success_echo, Completed '$(1)' in $$duration s)
# endef

define task_echo
	echo "\n$(YELLOW)🚀  $(1)$(RESET)"
endef

# define timed_command
# @$(call task_echo, Starting task: $(1)); \
# echo ">-----------------------------------------------------------------"; \
# start_time=$$(date +%s); \
# if $(2); then \
#     end_time=$$(date +%s); \
#     duration=$$((end_time - start_time)); \
#     echo "-----------------------------------------------------------------<"; \
#     $(call success_echo, Completed '$(1)' in $$duration s); \
# else \
#     end_time=$$(date +%s); \
#     duration=$$((end_time - start_time)); \
#     echo "-----------------------------------------------------------------<"; \
#     $(call error_echo, Task '$(1)' failed after $$duration s); \
#     exit 1; \
# fi
# endef

define timed_command
	@$(call task_echo, Starting task: $(1)); \
	echo "----------------------------------------------------------------------------"; \
	start_time=$$(date +%s); \
	if $(2); then \
		end_time=$$(date +%s); \
		duration=$$((end_time - start_time)); \
		minutes=$$((duration / 60)); \
		seconds=$$((duration % 60)); \
		time_str=""; \
		if [ $$minutes -gt 0 ]; then \
			time_str=$$(printf "%dm %ds" $$minutes $$seconds); \
		else \
			time_str=$$(printf "%ds" $$seconds); \
		fi; \
		\
		echo "----------------------------------------------------------------------------"; \
		printf "$(GREEN)✅ Task '$(1)' completed $(BLUE) ⏱️  Elapsed time: $(YELLOW)%s$(BLUE)$(RESET)\n" "$$time_str"; \
	else \
		end_time=$$(date +%s); \
		duration=$$((end_time - start_time)); \
		minutes=$$((duration / 60)); \
		seconds=$$((duration % 60)); \
		time_str=""; \
		if [ $$minutes -gt 0 ]; then \
			time_str=$$(printf "%dm %ds" $$minutes $$seconds); \
		else \
			time_str=$$(printf "%ds" $$seconds); \
		fi; \
		\
		echo "----------------------------------------------------------------------------"; \
		printf "$(RED)❌ Task '$(1)' failed $(BLUE) ⏱️  after $(YELLOW)%s$(BLUE)$(RESET)\n" "$$time_str"; \
		exit 1; \
	fi
endef

# 필수 명령어 확인 함수
define check_command
@command -v $(1) >/dev/null 2>&1 || ($(call error_echo, "$(1) is required but not installed") && exit 1)
endef

# Docker 실행 상태 확인
define check_docker
@docker info >/dev/null 2>&1 || ($(call error_echo, "Docker is not running") && exit 1)
endef

define check_docker_command
@docker info >/dev/null 2>&1 || ( $(call error_echo, "Docker is not running") ; exit 1 )
endef


# Git 작업 디렉토리 정리 상태 확인
define check_git_clean
@git diff --quiet || ( $(call warn_echo, "Working directory has uncommitted changes") && exit 1 )
endef

# Git 브랜치 확인
define check_branch
@CURRENT=$$(git rev-parse --abbrev-ref HEAD 2>/dev/null); \
if [ "$$CURRENT" != "$(1)" ]; then \
    $(call error_echo, "You must be on '$(1)' branch (currently on '$$CURRENT')"); \
    exit 1; \
fi
endef

define newline

endef

BUILD_ARG_VARS := \
    REPO_HUB \
    NAME \
    VERSION \
    TAGNAME \
    ENV


BUILD_ARGS_CONTENT := $(foreach var,$(BUILD_ARG_VARS),--build-arg $(var)='$($(var))'$(newline))
DEBUG_ARGS_CONTENT := $(BUILD_ARGS_CONTENT)
# ================================================================
# 기본 검증 타겟들
# ================================================================

.PHONY: check-deps check-docker check-git-clean make_debug_mode make_build_args
check-check:
	$(call success, "All required tools are available")
	$(call check_docker_command)
	$(call success, "All required tools are available")

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


make-debug-mode:
	@$(call colorecho, $(BLUE), "", "----- DEBUG Environment -----")
	@# DEBUG_VARS 목록을 순회하며 각 변수와 값을 보기 좋게 출력합니다.
	@for var_name in $(DEBUG_VARS); do \
		printf "  %-20s = %s\n" "$$var_name" "$($(var_name))"; \
	done
	@echo ""
	@# 미리 생성된 내용을 DEBUG_ARGS 파일에 한 번에 씁니다.
	@echo '$(DEBUG_ARGS_CONTENT)' > DEBUG_ARGS
	@$(call success, "DEBUG_ARGS file generated successfully.")
	@echo "Content of DEBUG_ARGS:"
	@cat DEBUG_ARGS

make-build-args:
	@$(call success, ----- Generating Docker Build Arguments (using foreach) -----)
	@$(call yellow, BUILD_ARGS = $(BUILD_ARGS_CONTENT) \n)
	@printf '%s' '$(BUILD_ARGS_CONTENT)' > BUILD_ARGS
	@$(call success, "BUILD_ARGS file generated successfully.")


# ================================================================
# universal makefile 설정
# ================================================================


self-update:
	@$(call colorecho, ----- Updating Makefile System -----)
	# $(shell ...)을 제거하고 스크립트를 직접 호출합니다.
	@$(MAKEFILE_DIR)/install.sh update $(ARGS)
	@$(call success, "Makefile System updated successfully.")

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
	@echo "  BUILD_ARGS: $(BUILD_ARGS_CONTENT)"
	@echo "  DEBUG_ARGS: $(DEBUG_ARGS_CONTENT)"
	@echo ""
	@echo "$(BLUE)Environment:$(RESET)"
	@echo "  ENV: $(ENV)"
	@echo "  CI: $(CI)"
	@echo "  DEBUG: $(DEBUG)"
	@echo "  FORCE_REBUILD: $(FORCE_REBUILD)"
