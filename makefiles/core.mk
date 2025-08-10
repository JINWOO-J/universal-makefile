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

# 현재 짧은/긴 커밋 해시
CURRENT_COMMIT_SHORT := $(shell git rev-parse --short HEAD 2>/dev/null || echo "unknown")
CURRENT_COMMIT_LONG := $(shell git rev-parse HEAD 2>/dev/null || echo "unknown")

# Git 워킹 디렉토리의 상태를 확인 (커밋되지 않은 변경사항이 있으면 출력 내용이 생김)
GIT_STATUS := $(shell git status --porcelain 2>/dev/null)

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
	ECHO_CMD = echo $(ECHO_OPTION)
	GET_NANO_CMD := if command -v gdate >/dev/null; then gdate +%s%N; else python -c 'import time; print(int(time.time() * 10**9))'; fi
else
	SED = sed -i
	ECHO_OPTION = "-e"
	ECHO_CMD = echo $(ECHO_OPTION)
	GET_NANO_CMD := date +%s%N

endif

ENV_VARS_BASE := REPO_HUB NAME ROLE VERSION TAGNAME ENV IMAGE_NAME APP_IMAGE_NAME FULL_TAG LATEST_TAG
ENV_VARS_GIT  := CURRENT_BRANCH MAIN_BRANCH DEVELOP_BRANCH CURRENT_COMMIT_SHORT CURRENT_COMMIT_LONG COMMIT_TAG BUILD_REVISION
ENV_VARS_DKR  := DOCKERFILE_PATH DOCKER_BUILD_OPTION DOCKER_BUILDKIT BUILDKIT_INLINE_CACHE
ENV_VARS_DEFAULT := $(ENV_VARS_BASE) $(ENV_VARS_GIT)
ENV_VARS_ALL     := $(ENV_VARS_BASE) $(ENV_VARS_GIT) $(ENV_VARS_DKR)

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


define timed_command
	@$(call task_echo, Starting task: $(1)); \
	echo "----------------------------------------------------------------------------"; \
	start_time_ns=$$( $(GET_NANO_CMD) ); \
	if $(2); then \
		end_time_ns=$$( $(GET_NANO_CMD) ); \
		duration_ns=$$((end_time_ns - start_time_ns)); \
		time_str=""; \
		\
		if [ $$duration_ns -lt 1000000000 ]; then \
			duration_ms=$$((duration_ns / 1000000)); \
			time_str=$$(printf "%dms" $$duration_ms); \
		else \
			duration_s=$$((duration_ns / 1000000000)); \
			minutes=$$((duration_s / 60)); \
			seconds=$$((duration_s % 60)); \
			if [ $$minutes -gt 0 ]; then \
				time_str=$$(printf "%dm %ds" $$minutes $$seconds); \
			else \
				time_str=$$(printf "%ds" $$seconds); \
			fi; \
		fi; \
		\
		echo "----------------------------------------------------------------------------"; \
		printf "$(GREEN)✅ Task '$(1)' completed $(BLUE)(⏱️  Elapsed time: $(YELLOW)%s$(BLUE))$(RESET)\n" "$$time_str"; \
	else \
		end_time_ns=$$( $(GET_NANO_CMD) ); \
		duration_ns=$$((end_time_ns - start_time_ns)); \
		time_str=""; \
		\
		if [ $$duration_ns -lt 1000000000 ]; then \
			duration_ms=$$((duration_ns / 1000000)); \
			time_str=$$(printf "%dms" $$duration_ms); \
		else \
			duration_s=$$((duration_ns / 1000000000)); \
			minutes=$$((duration_s / 60)); \
			seconds=$$((duration_s % 60)); \
			if [ $$minutes -gt 0 ]; then \
				time_str=$$(printf "%dm %ds" $$minutes $$seconds); \
			else \
				time_str=$$(printf "%ds" $$seconds); \
			fi; \
		fi; \
		\
		echo "----------------------------------------------------------------------------"; \
		printf "$(RED)❌ Task '$(1)' failed $(BLUE)(⏱️  after $(YELLOW)%s$(BLUE))$(RESET)\n" "$$time_str"; \
		exit 1; \
	fi
endef

define print_var
	@printf "     $(BOLD)$(BLUE)%-20s$(RESET) : $(YELLOW)%s$(RESET)\n" "$(1)" "$(2)"
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
    BUILD_REVISION \
    ENV


BUILD_ARGS_CONTENT := $(foreach var,$(BUILD_ARG_VARS),--build-arg $(var)='$($(var))'$(newline))
DEBUG_ARGS_CONTENT := $(BUILD_ARGS_CONTENT)
# ================================================================
# 기본 검증 타겟들
# ================================================================

.PHONY: check-deps check-docker check-git-clean make_debug_mode make_build_args env-keys env-get env-show


# env-keys: ## 🔧 사용 가능한 env-show 기본 키 목록 출력
# 	@echo "$(ENV_VARS_DEFAULT)"

# env-get: ## 🔧 지정 변수 값만 출력 (사용법: make env-get VAR=NAME)
# 	@[ -n "$(VAR)" ] || { echo "VAR is required (e.g., make env-get VAR=NAME)" >&2; exit 1; }
# 	@printf "%s\n" "$($(VAR))"

# env-show: env ## 🔧 key=value 형식으로 환경 변수 출력 (VARS 또는 ENV_VARS로 키 선택 가능)
# 	@$(foreach k,$(or $(strip $(VARS)),$(strip $(ENV_VARS)),$(ENV_VARS_DEFAULT)), printf "%s=%s\n" "$(k)" "$($(k))" ; )


env-keys: ## 🔧 env-show 기본/전체 키 목록 출력
	@echo "DEFAULT: $(ENV_VARS_DEFAULT)"
	@echo "ALL:     $(ENV_VARS_ALL)"

env-get: ## 🔧 지정 변수 값만 출력 (사용법: make env-get VAR=NAME)
	@[ -n "$(VAR)" ] || { echo "VAR is required (e.g., make env-get VAR=NAME)" >&2; exit 1; }
	@printf "%s\n" "$($(VAR))"

# 사용법 예:
#  - make env-show -s >> $$GITHUB_ENV
#  - make env-show FORMAT=kv
#  - make env-show VARS="REPO_HUB NAME ROLE"
#  - make env-show PREFIX=DOCKER_
#  - make env-show ALL=true SKIP_EMPTY=true
#  - make env-show SHOW_SECRETS=true
env-show: ## 🔧 key=value 형식 출력(FORMAT=kv|dotenv|github, VARS/ENV_VARS/PREFIX/ALL/SKIP_EMPTY/SHOW_SECRETS)
	@{ \
		# 선택 키 결정
		list="$(strip $(VARS))"; \
		[ -z "$$list" ] && list="$(strip $(ENV_VARS))"; \
		[ -z "$$list" ] && list="$(strip $(ENV_VARS_DEFAULT))"; \
		[ "$(ALL)" = "true" ] && list="$(strip $(ENV_VARS_ALL))"; \
		# PREFIX 필터
		if [ -n "$(PREFIX)" ]; then \
			filt=""; \
			for k in $$list; do case "$$k" in $(PREFIX)*) filt="$$filt $$k";; esac; done; \
			list="$$filt"; \
		fi; \
		# 포맷/옵션
		fmt="$(FORMAT)"; [ -z "$$fmt" ] && fmt="dotenv"; \
		skip="$(SKIP_EMPTY)"; [ -z "$$skip" ] && skip="false"; \
		show="$(SHOW_SECRETS)"; [ -z "$$show" ] && show="false"; \
		# 출력
		first_json=1; \
		[ "$$fmt" = "json" ] && printf "{"; \
		for k in $$list; do \
			# 값 읽기 (환경에서) — 위에서 export했으므로 사용 가능
			v="$${!k}"; \
			# 빈값 스킵
			if [ "$$skip" = "true" ] && [ -z "$$v" ]; then continue; fi; \
			# 시크릿 마스킹
			case "$$k" in *TOKEN*|*PASSWORD*|*SECRET*|*KEY*|*WEBHOOK*) \
				[ "$$show" = "true" ] || v="****";; \
			esac; \
			case "$$fmt" in \
				kv|dotenv) \
					esc=$$(printf '%s' "$$v" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\n/\\n/g'); \
					printf '%s="%s"\n' "$$k" "$$esc";; \
				github) \
					# GITHUB_ENV는 단일 라인 key=value 사용 권장
					one=$$(printf '%s' "$$v" | tr '\n' ' '); \
					printf '%s=%s\n' "$$k" "$$one";; \
				json) \
					# 간단 JSON 객체 구성
					VAL="$$v"; jv=$$(python -c 'import json,os; print(json.dumps(os.environ.get("VAL","")))'); \
					if [ $$first_json -eq 0 ]; then printf ","; fi; \
					first_json=0; \
					printf '"%s":%s' "$$k" "$$jv";; \
				yaml) \
					esc=$$(printf '%s' "$$v" | sed -e "s/'/''/g"); \
					printf '%s: ''%s''\n' "$$k" "$$esc";; \
				*) \
					esc=$$(printf '%s' "$$v" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\n/\\n/g'); \
					printf '%s="%s"\n' "$$k" "$$esc";; \
			esac; \
		done; \
		[ "$$fmt" = "json" ] && printf "}"; \
	}
	

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
	@$(call timed_command, Executing '$(MAKEFILE_DIR)/install.sh $(*) $(ARGS)', \
		$(MAKEFILE_DIR)/install.sh $(*) $(ARGS) \
	)


# self-update:
# 	# $(shell ...)을 제거하고 스크립트를 직접 호출합니다.
# 	@$(MAKEFILE_DIR)/install.sh update $(ARGS)
# 	@$(call success, "Makefile System updated successfully.")

# ================================================================
# 디버깅 타겟들
# ================================================================
# debug-vars: ## 🔧 Show all Makefile variables
# 	@echo "$(BLUE)Core Variables:$(RESET)"
# 	@echo "  REPO_HUB: $(REPO_HUB)"
# 	@echo "  NAME: $(NAME)"
# 	@echo "  VERSION: $(VERSION)"
# 	@echo "  TAGNAME: $(TAGNAME)"
# 	@echo "  IMAGE_NAME: $(IMAGE_NAME)"
# 	@echo "  APP_IMAGE_NAME: $(APP_IMAGE_NAME)"
# 	@echo "  FULL_TAG: $(FULL_TAG)"
# 	@echo "  LATEST_TAG: $(LATEST_TAG)"
# 	@echo ""
# 	@echo "$(BLUE)Git Configuration:$(RESET)"
# 	@echo "  CURRENT_BRANCH: $(CURRENT_BRANCH)"
# 	@echo "  MAIN_BRANCH: $(MAIN_BRANCH)"
# 	@echo "  DEVELOP_BRANCH: $(DEVELOP_BRANCH)"
# 	@echo "  CURRENT_COMMIT_SHORT: $(CURRENT_COMMIT_SHORT)"
# 	@echo "  CURRENT_COMMIT_LONG: $(CURRENT_COMMIT_LONG)"
# 	@echo "  GIT_STATUS: $(GIT_STATUS)"
# 	@echo "  COMMIT_TAG: $(COMMIT_TAG)"
# 	@echo ""
# 	@echo "$(BLUE)Docker Configuration:$(RESET)"
# 	@echo "  DOCKERFILE_PATH: $(DOCKERFILE_PATH)"
# 	@echo "  DOCKER_BUILD_OPTION: $(DOCKER_BUILD_OPTION)"
# 	@echo "  BUILD_ARGS: $(BUILD_ARGS_CONTENT)"
# 	@echo "  DEBUG_ARGS: $(DEBUG_ARGS_CONTENT)"
# 	@echo ""
# 	@echo "$(BLUE)Environment:$(RESET)"
# 	@echo "  ENV: $(ENV)"
# 	@echo "  CI: $(CI)"
# 	@echo "  DEBUG: $(DEBUG)"
# 	@echo "  FORCE_REBUILD: $(FORCE_REBUILD)"

# debug-vars 타겟에서 사용할 변수 목록

debug-vars: ## 🔧 Show all Makefile variables in a structured way
	@$(ECHO_CMD) "$(MAGENTA)🐰 Core Variables:$(RESET)"
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
	@$(call print_var, DOCKER_BUILD_OPTION, $(DOCKER_BUILD_OPTION))
	@$(call print_var, BUILD_ARGS, $(BUILD_ARGS_CONTENT))
	@$(call print_var, DEBUG_ARGS, $(DEBUG_ARGS_CONTENT))
	@$(ECHO_CMD) ""
	@$(ECHO_CMD) "$(MAGENTA)🐰 Environment:$(RESET)"
	@$(call print_var, ENV, $(ENV))
	@$(call print_var, CI, $(CI))
	@$(call print_var, DEBUG, $(DEBUG))
	@$(call print_var, FORCE_REBUILD, $(FORCE_REBUILD))


info: debug-vars
