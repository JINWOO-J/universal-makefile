SHELL := /bin/bash
# ================================================================
# Core Functions and Variables
# ================================================================

include $(MAKEFILE_DIR)/makefiles/colors.mk

# 기본 변수들 (project.mk에서 오버라이드 가능)
REPO_HUB ?= defaultrepo
NAME ?= defaultapp
VERSION ?= v1.0.0

# 버전 파일 설정 (선택적)
VERSION_FILE ?=

# Git 브랜치 설정 (project.mk에서 오버라이드 가능)
MAIN_BRANCH ?= main
DEVELOP_BRANCH ?= develop
FORCE ?= false

SOURCE_DIR ?= $(CURDIR)/source
SOURCE_REPO ?= ""

# UMF_MODE에 따라 버전 자동 파싱
ifeq ($(UMF_MODE),global)
  ifneq ($(VERSION_FILE),)
    _VERSION_FILE_PATH := $(SOURCE_DIR)/$(VERSION_FILE)
    ifneq ($(wildcard $(_VERSION_FILE_PATH)),)
      # VERSION_FILE이 존재하면 파싱
      _PARSED_VERSION := $(shell bash $(MAKEFILE_DIR)/scripts/parse_version.sh "$(_VERSION_FILE_PATH)" 2>/dev/null)
      ifneq ($(_PARSED_VERSION),)
        # v 접두사가 없으면 추가
        ifeq ($(findstring v,$(_PARSED_VERSION)),)
          override VERSION := v$(_PARSED_VERSION)
        else
          override VERSION := $(_PARSED_VERSION)
        endif
        $(info [INFO] VERSION 자동 파싱: $(VERSION) (from $(VERSION_FILE)))
      endif
    endif
  endif
endif

# Universal Makfile 실행 모드 = local: project와 함께 or global: 외부 clone으로 동작
UMF_MODE ?= local 

# UMF_MODE에 따라 Git 작업 디렉토리 결정
ifeq ($(UMF_MODE),global)
    GIT_WORK_DIR := $(SOURCE_DIR)
else
    GIT_WORK_DIR := $(CURDIR)
endif

# 현재 짧은/긴 커밋 해시 (TAGNAME 계산 전에 필요)
CURRENT_COMMIT_SHORT := $(shell cd $(GIT_WORK_DIR) 2>/dev/null && git rev-parse --short HEAD 2>/dev/null | tr -d ' ' || echo "unknown")
CURRENT_COMMIT_LONG := $(shell cd $(GIT_WORK_DIR) 2>/dev/null && git rev-parse HEAD 2>/dev/null | tr -d ' ' || echo "unknown")

# 날짜(브랜치 태그 구성에 필요)
DATE ?= $(shell date -u +%Y%m%d)

# 계산된 변수들
CURRENT_BRANCH := $(shell cd $(GIT_WORK_DIR) 2>/dev/null && git rev-parse --abbrev-ref HEAD 2>/dev/null | tr ' ' '-' || echo "unknown")
ifeq ($(CURRENT_BRANCH),HEAD)
    CURRENT_BRANCH := detached
endif

_ORIGINAL_TAGNAME := $(TAGNAME)

ifeq ($(CURRENT_BRANCH),$(MAIN_BRANCH))
    _SOURCE_FOR_SANITIZE = $(or $(_ORIGINAL_TAGNAME), $(VERSION))
else
    SAFE_BRANCH := $(shell echo "$(CURRENT_BRANCH)" | sed 's/[^a-zA-Z0-9._-]/-/g; s/-+/-/g')
    # 브랜치에서는 version-branch-date-sha 형태
    _SOURCE_FOR_SANITIZE = $(or $(_ORIGINAL_TAGNAME), $(VERSION)-$(SAFE_BRANCH)-$(DATE)-$(CURRENT_COMMIT_SHORT))
endif

_SAFE_TAGNAME := $(shell echo '$(_SOURCE_FOR_SANITIZE)' | sed 's/[^a-zA-Z0-9_.-]/-/g')

override TAGNAME := $(_SAFE_TAGNAME)

ifneq ($(_SOURCE_FOR_SANITIZE),$(TAGNAME))
$(info ⚠️  Warning: Original tag '$(_SOURCE_FOR_SANITIZE)' contained invalid characters. Sanitized to '$(TAGNAME)'.)
endif

COMMIT_TAG := $(CURRENT_COMMIT_SHORT)$(GIT_DIRTY_SUFFIX)
BUILD_REVISION := $(CURRENT_BRANCH)-$(CURRENT_COMMIT_SHORT)$(GIT_DIRTY_SUFFIX)

IMAGE_NAME := $(REPO_HUB)/$(NAME)
APP_IMAGE_NAME := $(REPO_HUB)/$(NAME)
FULL_TAG := $(APP_IMAGE_NAME):$(TAGNAME)
LATEST_TAG := $(APP_IMAGE_NAME):latest

# Git 워킹 디렉토리의 상태를 확인 (커밋되지 않은 변경사항이 있으면 출력 내용이 생김)
GIT_STATUS := $(shell cd $(GIT_WORK_DIR) 2>/dev/null && git status --porcelain 2>/dev/null)

ifeq ($(strip $(GIT_STATUS)),)
	GIT_DIRTY_SUFFIX :=
else
	GIT_DIRTY_SUFFIX := -dirty
endif

COMMIT_TAG := $(CURRENT_COMMIT_SHORT)$(GIT_DIRTY_SUFFIX)
BUILD_REVISION := $(CURRENT_BRANCH)-$(CURRENT_COMMIT_SHORT)$(GIT_DIRTY_SUFFIX)

IMAGE_NAME := $(REPO_HUB)/$(NAME)
APP_IMAGE_NAME := $(REPO_HUB)/$(NAME)
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
DOCKERFILE_PATH ?= docker/Dockerfile
DOCKERFILE_CONTEXT ?= $(SOURCE_DIR)

# 색상 설정 (CI 환경 고려)
ifeq ($(CI),true)
    GREEN :=
    YELLOW :=
    BLUE :=
    RED :=
    RESET :=
	NC :=
else
    GREEN := $(shell tput setaf 2 2>/dev/null || echo "")
    YELLOW := $(shell tput setaf 3 2>/dev/null || echo "")
    BLUE := $(shell tput setaf 4 2>/dev/null || echo "")
    RED := $(shell tput setaf 1 2>/dev/null || echo "")
    RESET := $(shell tput sgr0 2>/dev/null || echo "")
    NC := $(shell tput sgr0 2>/dev/null || echo "")
endif

# 플랫폼별 SED 설정
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
	SED = sed -E -i ''
	# ECHO_OPTION =
# ECHO_CMD = echo $(ECHO_OPTION)
else
	SED = sed -i
# ECHO_OPTION = -e
	ECHO_CMD = echo $(ECHO_OPTION)
endif

PYTHON_GET_NANO_CMD := python -c '\''import time; print(int(time.time() * 10**9))'\''
GET_NANO_CMD := if command -v gdate >/dev/null; then gdate +%s%N; else $(PYTHON_GET_NANO_CMD); fi

PRINTF_B := printf '%b\n'  # \n 같은 이스케이프 해석
ECHO_CMD := $(PRINTF_B)

# ECHO_CMD = printf '%b\n'   # escape 해석
# SAY      = printf '%s\n'   # 리터럴 그대로


ENV_VARS_BASE := REPO_HUB NAME ROLE VERSION TAGNAME ENV IMAGE_NAME APP_IMAGE_NAME FULL_TAG LATEST_TAG
ENV_VARS_GIT  := CURRENT_BRANCH MAIN_BRANCH DEVELOP_BRANCH CURRENT_COMMIT_SHORT CURRENT_COMMIT_LONG COMMIT_TAG BUILD_REVISION
ENV_VARS_DKR  := DOCKERFILE_PATH DOCKER_BUILD_OPTION DOCKER_BUILDKIT BUILDKIT_INLINE_CACHE
ENV_VARS_DEFAULT := $(ENV_VARS_BASE) $(ENV_VARS_GIT)
ENV_VARS_ALL     := $(ENV_VARS_BASE) $(ENV_VARS_GIT) $(ENV_VARS_DKR)
ENV_VARS_PASSTHROUGH := DEBUG FORCE FORCE ARGS MAKEFILE_DIR BACKUP DRY_RUN

# export variables so shell recipes can read them via printenv
export $(ENV_VARS_ALL) $(ENV_VARS_PASSTHROUGH)

# ================================================================
# 공통 함수들
# ================================================================


TIMER_SCRIPT := $(MAKEFILE_DIR)/scripts/timed_run_script.sh

sh_quote = $(subst ','\'',$(1))

# 공통 실행 코어
define run_core
	@TIMED_TASK_NAME='$(call sh_quote,$(strip $(1)))' \
	TIMED_DEBUG="$(DEBUG)" \
	TIMED_MODE="$(2)" \
	$(TIMER_SCRIPT) $(3)
endef

# auto (기본)
define run_auto
	$(call run_core,$(1),$(or $(3),$(TIMED_MODE)),$(2))
endef

# pipe 고정
define run_pipe
	$(call run_core,$(1),pipe,$(2))
endef

# quiet 고정
define run_quiet
	$(call run_core,$(1),quiet,$(2))
endef

# interactive 고정
define run_interactive
	$(call run_core,$(1),interactive,$(2))
endef


# PYTHON_GET_NANO_CMD := python -c 'import time; print(int(time.time() * 10**9))'
# GET_NANO_CMD := if command -v gdate >/dev/null 2>&1; then gdate +%s%N; else $(PYTHON_GET_NANO_CMD); fi

# ================================================================
# 안전한 통합 timed_run 함수
# ================================================================
# 사용법:
#   $(call timed_run, 작업명, 명령어)                    # 기본 (자동 감지)
#   $(call timed_run, 작업명, 명령어, interactive)       # 강제 대화식 모드
#   $(call timed_run, 작업명, 명령어, piped)            # 강제 파이프 모드
#   $(call timed_run, 작업명, 명령어, quiet)            # 조용한 모드 (박스 없음)
# ================================================================
define timed_run
	@export TIMED_MODE='$(3)'; \
	export TIMED_CMD_NAME='$(1)'; \
	bash -c ' \
		set -o pipefail; \
		_MODE="$$TIMED_MODE"; \
		_CMD_NAME="$$TIMED_CMD_NAME"; \
		\
		format_duration() { \
			local duration_ns=$$1; \
			if [ $$duration_ns -lt 1000000000 ]; then \
				duration_ms=$$((duration_ns / 1000000)); \
				printf "%dms" $$duration_ms; \
			else \
				duration_s=$$((duration_ns / 1000000000)); \
				minutes=$$((duration_s / 60)); \
				seconds=$$((duration_s % 60)); \
				if [ $$minutes -gt 0 ]; then \
					printf "%dm %ds" $$minutes $$seconds; \
				else \
					printf "%ds" $$seconds; \
				fi; \
			fi; \
		}; \
		\
		run_command() { \
			$(2); \
		}; \
		\
		if [ "$$_MODE" = "quiet" ]; then \
			printf "$(YELLOW)⏱️  Starting: %s$(RESET)\n" "$$_CMD_NAME"; \
			_START_TIME_NS=$$( $(GET_NANO_CMD) ); \
			if run_command; then \
				_END_TIME_NS=$$( $(GET_NANO_CMD) ); \
				_DURATION_NS=$$((_END_TIME_NS - _START_TIME_NS)); \
				_TIME_STR=$$(format_duration $$_DURATION_NS); \
				printf "$(GREEN)✅ Completed in %s$(RESET)\n" "$$_TIME_STR"; \
			else \
				_EXIT_CODE=$$?; \
				_END_TIME_NS=$$( $(GET_NANO_CMD) ); \
				_DURATION_NS=$$((_END_TIME_NS - _START_TIME_NS)); \
				_TIME_STR=$$(format_duration $$_DURATION_NS); \
				printf "$(RED)❌ Failed after %s (exit code: %d)$(RESET)\n" "$$_TIME_STR" "$$_EXIT_CODE" >&2; \
				exit $$_EXIT_CODE; \
			fi; \
		else \
			_START_MSG="🚀 Executing: $$_CMD_NAME"; \
			_PADDING_LEN=$$(( 70 - $${#_START_MSG} )); \
			[ $$_PADDING_LEN -lt 0 ] && _PADDING_LEN=0; \
			_PADDING=$$(printf "─%.0s" $$(seq 1 $$_PADDING_LEN 2>/dev/null || :)); \
			printf "\n$(YELLOW)┌── %s %s────┐$(RESET)\n" "$$_START_MSG" "$$_PADDING"; \
			printf "$(YELLOW)│$(RESET)\n"; \
			\
			_START_TIME_NS=$$( $(GET_NANO_CMD) ); \
			\
			if [ "$$_MODE" = "interactive" ] || { [ -z "$$_MODE" ] && [ -t 0 ] && [ -t 1 ]; }; then \
				if run_command; then \
					_EXIT_CODE=0; \
				else \
					_EXIT_CODE=$$?; \
				fi; \
			else \
				TEMP_FILE=$$(mktemp); \
				trap "rm -f $$TEMP_FILE" EXIT; \
				{ run_command 2>&1; echo $$? > $$TEMP_FILE; } | \
				while IFS= read -r line; do \
					printf "$(YELLOW)│$(RESET) %s\n" "$$line"; \
				done; \
				_EXIT_CODE=$$(cat $$TEMP_FILE 2>/dev/null || echo 1); \
				rm -f $$TEMP_FILE; \
			fi; \
			\
			_END_TIME_NS=$$( $(GET_NANO_CMD) ); \
			_DURATION_NS=$$((_END_TIME_NS - _START_TIME_NS)); \
			_TIME_STR=$$(format_duration $$_DURATION_NS); \
			\
			printf "$(YELLOW)│$(RESET)\n"; \
			if [ "$$_EXIT_CODE" = "0" ] || [ "$$_EXIT_CODE" = "" ]; then \
				_END_MSG="✅ SUCCESS (in $$_TIME_STR)"; \
				_PADDING_LEN=$$(( 70 - $${#_END_MSG} )); \
				[ $$_PADDING_LEN -lt 0 ] && _PADDING_LEN=0; \
				_PADDING=$$(printf "─%.0s" $$(seq 1 $$_PADDING_LEN 2>/dev/null || :)); \
				printf "$(GREEN)└── %s %s────┘$(RESET)\n\n" "$$_END_MSG" "$$_PADDING"; \
			else \
				_END_MSG="❌ FAILED (after $$_TIME_STR, code $$_EXIT_CODE)"; \
				_PADDING_LEN=$$(( 70 - $${#_END_MSG} )); \
				[ $$_PADDING_LEN -lt 0 ] && _PADDING_LEN=0; \
				_PADDING=$$(printf "─%.0s" $$(seq 1 $$_PADDING_LEN 2>/dev/null || :)); \
				printf "$(RED)└── %s %s────┘$(RESET)\n\n" "$$_END_MSG" "$$_PADDING" >&2; \
				exit $$_EXIT_CODE; \
			fi; \
		fi \
	'
endef


define timed_command
	$(call timed_run,$(1),$(2), pipe)
endef

define timed_simple
	$(call timed_run,$(1),$(2))
endef


# 명시적 대화식 모드 (install.sh 같은 대화식 스크립트용)
define timed_interactive
	$(call timed_run,$(1),$(2),interactive)
endef

# 파이프 모드 강제 (출력을 꾸미고 싶을 때)
define timed_piped
	$(call timed_run,$(1),$(2),piped)
endef

# 조용한 모드 (박스 없이 간단한 출력만)
define timed_quiet
	$(call timed_run,$(1),$(2),quiet)
endef

# 기존 timed_run_with_interactive 대체 (하위 호환성)
define timed_run_with_interactive
	$(call timed_run,$(1),$(2),interactive)
endef


define print_var
	@printf "     $(BOLD)$(BLUE)%-20s$(RESET) : $(YELLOW)%s$(RESET)\n" "$(1)" "$(2)"
endef

# 필수 명령어 확인 함수
define check_command
@command -v $(1) >/dev/null 2>&1 || ($(call error_echo, $(1) is required but not installed) && exit 1)
endef

# Docker 실행 상태 확인
define check_docker
@docker info >/dev/null 2>&1 || ($(call error_echo, Docker is not running) && exit 1)
endef

define check_docker_command
@docker info >/dev/null 2>&1 || ( $(call error_echo, Docker is not running) ; exit 1 )
endef


# Git 작업 디렉토리 정리 상태 확인
define check_git_clean
@git diff --quiet || ( $(call warn_echo, Working directory has uncommitted changes) && exit 1 )
endef

# Git 브랜치 확인
define check_branch
@CURRENT=$$(git rev-parse --abbrev-ref HEAD 2>/dev/null); \
if [ "$$CURRENT" != "$(1)" ]; then \
    $(call error_echo, You must be on '$(1)' branch (currently on '$$CURRENT')); \
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
    BUILD_REVISION \
    ENV


BUILD_ARGS_CONTENT := $(foreach var,$(BUILD_ARG_VARS),--build-arg $(var)='$($(var))'$(newline))
DEBUG_ARGS_CONTENT := $(BUILD_ARGS_CONTENT)
# ================================================================
# 기본 검증 타겟들
# ================================================================

.PHONY: check-deps check-docker check-git-clean make_debug_mode make_build_args \
	env-keys env-get env-show env-file env env-pretty env-github


# env-keys: ## 🔧 사용 가능한 env-show 기본 키 목록 출력
# 	@echo "$(ENV_VARS_DEFAULT)"

# env-get: ## 🔧 지정 변수 값만 출력 (사용법: make env-get VAR=NAME)
# 	@[ -n "$(VAR)" ] || { echo "VAR is required (e.g., make env-get VAR=NAME)" >&2; exit 1; }
# 	@printf "%s\n" "$($(VAR))"

# env-show: env ## 🔧 key=value 형식으로 환경 변수 출력 (VARS 또는 ENV_VARS로 키 선택 가능)
# 	@$(foreach k,$(or $(strip $(VARS)),$(strip $(ENV_VARS)),$(ENV_VARS_DEFAULT)), printf "%s=%s\n" "$(k)" "$($(k))" ; )

print-test:
	@$(call print_color, $(BLUE), print_color test)
	@$(call colorecho, 🐚 colorecho test)
	@$(call success_silent, 🐚 success_silent test)
	@$(call warn_silent, 🐚 warn_silent test)
	@$(call error_silent, 🐚 error_silent test)
	@$(call blue_silent, 🐚 blue_silent test)
	@$(call green_silent, 🐚 green_silent test)
	@$(call yellow_silent, 🐚 yellow_silent test)
	@$(call red_silent, 🐚 red_silent test)
	@$(call success, 🐚 success test)
	@$(call warn_echo, 🐚 warn test)
	@$(call error_echo, 🐚 error test)
	@$(call success_echo, 🐚 success_echo)
	@$(call task_echo, 🐚 task_echo completed)
	@$(call print_color, $(BLUE), print_color)
	@$(call print_error, print_error)
	@$(call success, success)
	@$(call warn, warn)
	@$(call blue, blue)



check-check:
	$(call success, All required tools are available)
	$(call check_docker_command)
	$(call success, All required tools are available)

check-deps: ## 🔧 Check if required tools are installed
	$(call check_command, docker)
	$(call check_command, git)
	@$(call success, All required tools are available)

check-docker: ## 🔧 Check if Docker is running
	$(call check_docker)
	@$(call success, Docker is running)

check-git-clean: ## 🔧 Check if working directory is clean
	$(call check_git_clean)
	@$(call success, Working directory is clean)


make-debug-mode:
	@$(call colorecho, $(BLUE), "", "----- DEBUG Environment -----")
	@# DEBUG_VARS 목록을 순회하며 각 변수와 값을 보기 좋게 출력합니다.
	@for var_name in $(DEBUG_VARS); do \
		printf "  %-20s = %s\n" "$$var_name" "$($(var_name))"; \
	done
	@echo ""
	@# 미리 생성된 내용을 DEBUG_ARGS 파일에 한 번에 씁니다.
	@echo '$(DEBUG_ARGS_CONTENT)' > DEBUG_ARGS
	@$(call success, DEBUG_ARGS file generated successfully.)
	@echo "Content of DEBUG_ARGS:"
	@cat DEBUG_ARGS

make-build-args:
	@$(call success, ----- Generating Docker Build Arguments (using foreach) -----)
	@$(call yellow, BUILD_ARGS = $(BUILD_ARGS_CONTENT) \n)
	@printf '%s' '$(BUILD_ARGS_CONTENT)' > BUILD_ARGS
	@$(call success, BUILD_ARGS file generated successfully.)


# ================================================================
# universal makefile 설정
# ================================================================
self-install:   ## ✨ Run 'install' command from install.sh
self-update:    ## ✨ Run 'update' command from install.sh
self-check:     ## ✨ Run 'check' command from install.sh
self-help:      ## ✨ Run 'help' command from install.sh
self-uninstall: ## ✨ Run 'uninstall' command from install.sh
self-app:       ## ✨ Run 'app' command from install.sh

# 'self-'로 시작하는 모든 타겟을 처리하는 패턴 규칙
# 예: 'make self-install'은 이 규칙을 통해 실행됩니다.
self-%:
	@$(call colorecho, ----- Updating Makefile System -----)
	# '$*' 자동 변수는 '%'에 매칭된 부분 (install, update 등)을 가리킵니다.
	# 이 값을 install.sh의 첫 번째 인자로 전달합니다.
	# ARGS 변수를 통해 추가 인자(--force 등)도 전달할 수 있습니다.
	#
	@export DEBUG
	@echo "DEBUG variable is: [$(DEBUG)]"
	@export FORCE
	@echo "FORCE variable is: [$(FORCE)]"
	@$(call run_interactive, Executing '$(MAKEFILE_DIR)/install.sh $(*) $(ARGS)', \
		FORCE=$(FORCE) MAKEFILE_DIR="$(MAKEFILE_DIR)" $(MAKEFILE_DIR)/install.sh $(*) $(ARGS) \
	)


# self-update:
# 	# $(shell ...)을 제거하고 스크립트를 직접 호출합니다.
# 	@$(MAKEFILE_DIR)/install.sh update $(ARGS)
# 	@$(call success, "Makefile System updated successfully.")

debug-vars: ## 🔧 Show all Makefile variables in a structured way
	@$(ECHO_CMD) "$(MAGENTA)🐰 Core Variables:$(RESET)"
	
	@$(call print_var, SOURCE_REPO, $(SOURCE_REPO))
	@$(call print_var, SOURCE_DIR, $(SOURCE_DIR))

	@$(call print_var, REPO_HUB, $(REPO_HUB))
	@$(call print_var, NAME, $(NAME))
	@$(call print_var, VERSION, $(VERSION))
	@$(call print_var, TAGNAME, $(TAGNAME))
	@$(call print_var, IMAGE_NAME, $(IMAGE_NAME))
	@$(call print_var, APP_IMAGE_NAME, $(APP_IMAGE_NAME))
	@$(call print_var, FULL_TAG, $(FULL_TAG))
	@$(call print_var, LATEST_TAG, $(LATEST_TAG))
	@$(ECHO_CMD) ""
	@$(ECHO_CMD) "$(MAGENTA)🐰 Git Configuration:$(RESET)"
	@$(call print_var, GIT_WORK_DIR, $(GIT_WORK_DIR))
	@$(call print_var, CURRENT_BRANCH, $(CURRENT_BRANCH))
	@$(call print_var, MAIN_BRANCH, $(MAIN_BRANCH))
	@$(call print_var, DEVELOP_BRANCH, $(DEVELOP_BRANCH))
	@$(call print_var, CURRENT_COMMIT_SHORT, $(CURRENT_COMMIT_SHORT))
	@$(call print_var, CURRENT_COMMIT_LONG, $(CURRENT_COMMIT_LONG))
	@$(call print_var, GIT_STATUS, $(GIT_STATUS))
	@$(call print_var, COMMIT_TAG, $(COMMIT_TAG))
	@$(call print_var, BUILD_REVISION, $(BUILD_REVISION))
	@$(ECHO_CMD) ""
	@$(ECHO_CMD) "$(MAGENTA)🐰 Docker Configuration:$(RESET)"
	@$(call print_var, DOCKERFILE_PATH, $(DOCKERFILE_PATH))
	@$(call print_var, DOCKERFILE_CONTEXT, $(DOCKERFILE_CONTEXT))
	@$(call print_var, DOCKER_BUILD_OPTION, $(DOCKER_BUILD_OPTION))
	@$(call print_var, BUILD_ARGS, $(BUILD_ARGS_CONTENT))
	@$(call print_var, DEBUG_ARGS, $(DEBUG_ARGS_CONTENT))
	@$(ECHO_CMD) ""
	@$(ECHO_CMD) "$(MAGENTA)🐰 Environment:$(RESET)"
	@$(call print_var, ENV, $(ENV))
	@$(call print_var, CI, $(CI))
	@$(call print_var, DEBUG, $(DEBUG))
	@$(call print_var, FORCE_REBUILD, $(FORCE_REBUILD))
	@$(call print_var, VERSION, $(VERSION))
	
	@$(ECHO_CMD) ""
	@$(MAKE) show-umf-version


info: debug-vars

# ================================================================
# GitHub Actions 워크플로우 관리
# ================================================================

list-workflows: ## � 사용 가능한 워크플로c우 목록 보기
	@echo "$(BLUE)📋 사용 가능한 워크플로우:$(RESET)"
	@echo ""
	@if [ -d "$(MAKEFILE_DIR)/github/workflows" ]; then \
		for file in $(MAKEFILE_DIR)/github/workflows/*.yml $(MAKEFILE_DIR)/github/workflows/*.yaml; do \
			if [ -f "$$file" ]; then \
				name=$$(basename "$$file"); \
				desc=$$(grep -m1 "^name:" "$$file" 2>/dev/null | sed 's/name:[[:space:]]*//'); \
				installed=""; \
				if [ -f ".github/workflows/$$name" ]; then \
					installed="$(GREEN)[설치됨]$(RESET)"; \
				else \
					installed="$(GRAY)[미설치]$(RESET)"; \
				fi; \
				printf "  $(CYAN)%-30s$(RESET) %s %s\n" "$$name" "$$desc" "$$installed"; \
			fi; \
		done; \
	else \
		echo "$(RED)워크플로우 디렉토리를 찾을 수 없습니다.$(RESET)"; \
	fi
	@echo ""
	@echo "$(YELLOW)💡 사용법:$(RESET)"
	@echo "  make install-workflow WORKFLOW=dispatch-deploy.yml"
	@echo "  make install-workflow WORKFLOW=\"dispatch-deploy.yml build-dev.yml\""

install-workflow: ## 🔧 워크플로우 설치 (사용법: make install-workflow WORKFLOW=파일명)
	@if [ -z "$(WORKFLOW)" ]; then \
		echo "$(RED)❌ WORKFLOW 변수가 필요합니다.$(RESET)"; \
		echo ""; \
		echo "$(YELLOW)사용법:$(RESET)"; \
		echo "  make install-workflow WORKFLOW=dispatch-deploy.yml"; \
		echo "  make install-workflow WORKFLOW=\"dispatch-deploy.yml build-dev.yml\""; \
		echo ""; \
		echo "$(CYAN)사용 가능한 워크플로우 목록:$(RESET)"; \
		$(MAKE) --no-print-directory list-workflows; \
		exit 1; \
	fi; \
	mkdir -p .github/workflows; \
	installed=0; \
	skipped=0; \
	for wf in $(WORKFLOW); do \
		source="$(MAKEFILE_DIR)/github/workflows/$$wf"; \
		target=".github/workflows/$$wf"; \
		if [ ! -f "$$source" ]; then \
			echo "$(RED)❌ 파일을 찾을 수 없습니다: $$wf$(RESET)"; \
			continue; \
		fi; \
		if [ -f "$$target" ]; then \
			echo "$(YELLOW)⚠️  이미 존재합니다: $$wf$(RESET)"; \
			read -p "   덮어쓰시겠습니까? (y/N): " -n 1 -r; \
			echo ""; \
			if [[ ! $$REPLY =~ ^[Yy]$$ ]]; then \
				echo "$(CYAN)   → 건너뜀$(RESET)"; \
				skipped=$$((skipped + 1)); \
				continue; \
			fi; \
		fi; \
		cp "$$source" "$$target"; \
		echo "$(GREEN)✓ 설치 완료: $$wf$(RESET)"; \
		installed=$$((installed + 1)); \
	done; \
	echo ""; \
	echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)"; \
	echo "$(GREEN)✅ 완료!$(RESET) 설치: $${installed} 개, 건너뜀: $${skipped} 개"
