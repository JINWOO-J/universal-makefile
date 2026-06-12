# ================================================================
# Docker Build and Registry Operations
# ================================================================

.PHONY: build push tag-latest bash docker-clean docker-info

# ================================================================
# Build Hooks
# ================================================================

# Internal hook: calls prepare-build if it exists in project Makefile
_prepare-build-hook:
	@if $(MAKE) -n prepare-build >/dev/null 2>&1; then \
		echo "$(BLUE)🔧 Running prepare-build hook...$(RESET)"; \
		$(MAKE) prepare-build; \
	fi

# ================================================================
# 메인 Docker 타겟들
# ================================================================

# 캐시 스코프 - 브랜치명을 안전한 Docker 태그로 변환
empty :=
space := $(empty) $(empty)
CACHE_SCOPE ?= $(shell echo "$(or $(SCOPE),$(shell git rev-parse --abbrev-ref HEAD))" | sed 's/[^a-zA-Z0-9-]/-/g')
CACHE_TAG ?= cache # 기본값 설정
CACHE_TAG := $(strip $(CACHE_TAG))
REPO_HUB := $(strip $(REPO_HUB))
NAME     := $(strip $(NAME))

# ---- Tag listing (script wrapper) ----
LIST_TAGS_SCRIPT ?= $(MAKEFILE_DIR)/scripts/registry-list-tags.sh
PRIVATE ?= 1
PAGE_SIZE ?= 10
AUTHFILE ?= $(HOME)/.docker/config.json


# 간단한 캐시 전략: 각 브랜치마다 고유 캐시 + main 캐시를 fallback으로 사용
ifeq ($(DISABLE_CACHE),true)
  # 캐시 완전 비활성화
  CACHE_FROM :=
  CACHE_TO   :=
else ifeq ($(CI),true)
  # CI 환경 - Registry 캐시 사용
  CACHE_IMAGE := $(REPO_HUB)/$(NAME):$(CACHE_TAG)-$(CACHE_SCOPE)
  CACHE_IMAGE_MAIN := $(REPO_HUB)/$(NAME):$(CACHE_TAG)-main
  CACHE_FROM := --cache-from=type=registry,ref=$(CACHE_IMAGE) --cache-from=type=registry,ref=$(CACHE_IMAGE)-deps --cache-from=type=registry,ref=$(CACHE_IMAGE_MAIN) --cache-from=type=registry,ref=$(CACHE_IMAGE_MAIN)-deps
  CACHE_TO := --cache-to=type=registry,ref=$(CACHE_IMAGE),mode=max --cache-to=type=registry,ref=$(CACHE_IMAGE)-deps,mode=max
else
  # 로컬 환경
  ifneq ($(REPO_HUB),)
     CACHE_IMAGE := $(REPO_HUB)/$(NAME):$(CACHE_TAG)-$(CACHE_SCOPE)
     CACHE_IMAGE_MAIN := $(REPO_HUB)/$(NAME):$(CACHE_TAG)-main
     CACHE_FROM := --cache-from=type=registry,ref=$(CACHE_IMAGE) --cache-from=type=registry,ref=$(CACHE_IMAGE)-deps --cache-from=type=registry,ref=$(CACHE_IMAGE_MAIN) --cache-from=type=registry,ref=$(CACHE_IMAGE_MAIN)-deps
     CACHE_TO := --cache-to=type=registry,ref=$(CACHE_IMAGE),mode=max --cache-to=type=registry,ref=$(CACHE_IMAGE)-deps,mode=max
  else
    CACHE_FROM :=
    CACHE_TO   :=
  endif
endif


# buildx 출력 방식
BUILD_OUTPUT := --load
ifeq ($(PUSH),1)
BUILD_OUTPUT := --push
endif

BUILDX_DRIVER := $(shell docker buildx inspect 2>/dev/null | awk '/Driver:/ {print $$2}')

# ... 기존 CACHE_FROM/CACHE_TO 계산 이후, 마지막에 안전 가드 추가
ifeq ($(BUILDX_DRIVER),docker)
  # docker 드라이버는 registry cache export 미지원 → 로컬 export만 비활성화
  CACHE_TO :=  
endif

# buildx 플래그
ifeq ($(FORCE_REBUILD),true)
  BUILDX_FLAGS := $(BUILD_OUTPUT) --progress=plain --no-cache
else
  BUILDX_FLAGS := $(CACHE_FROM) $(CACHE_TO) $(BUILD_OUTPUT) --progress=plain
endif


# ================================================================
# 빌드 타겟
# ================================================================
COMPUTE_TAG_SCRIPT ?= $(MAKEFILE_DIR)/scripts/compute_build_tag.sh

ensure-source: ## 🔧 소스 코드 확인 및 자동 fetch (UMF_MODE=global일 때, SKIP_FETCH=true로 비활성화 가능)
	@if [ "$(SKIP_FETCH)" = "true" ]; then \
		echo "$(GRAY)ℹ️  SKIP_FETCH=true, 자동 fetch 건너뜀$(NC)"; \
	elif [ "$(UMF_MODE)" = "global" ]; then \
		if [ ! -d "$(SOURCE_DIR)" ] || [ ! -d "$(SOURCE_DIR)/.git" ]; then \
			echo "$(YELLOW)📥 소스 코드가 없습니다. git-fetch 실행 중...$(NC)"; \
			$(MAKE) git-fetch SOURCE_REPO=$(SOURCE_REPO) REF=$(REF) SYNC_MODE=$(SYNC_MODE) FETCH_ALL=$(FETCH_ALL); \
		else \
			cd $(SOURCE_DIR) && \
			case "$(SYNC_MODE)" in \
				clone) \
					echo "$(YELLOW)🗑️  SYNC_MODE=clone: 강제 재다운로드$(NC)"; \
					cd - > /dev/null; \
					$(MAKE) git-fetch SOURCE_REPO=$(SOURCE_REPO) REF=$(REF) SYNC_MODE=clone FETCH_ALL=$(FETCH_ALL); \
					;; \
				keep) \
					echo "$(BLUE)🔍 SYNC_MODE=keep: 로컬 우선 모드$(NC)"; \
					TARGET_REF="$(REF)"; \
					CURRENT_HASH=$$(git rev-parse HEAD 2>/dev/null || echo ""); \
					TARGET_HASH=$$(git rev-parse "$$TARGET_REF" 2>/dev/null || echo ""); \
					if [ -z "$$CURRENT_HASH" ]; then \
						echo "$(RED)❌ 현재 커밋을 확인할 수 없습니다$(NC)"; \
						cd - > /dev/null; \
						exit 1; \
					fi; \
					if [ -z "$$TARGET_HASH" ]; then \
						echo "$(YELLOW)⚠️  로컬에 $$TARGET_REF가 없습니다. fetch 필요$(NC)"; \
						cd - > /dev/null; \
						$(MAKE) git-fetch SOURCE_REPO=$(SOURCE_REPO) REF=$(REF) SYNC_MODE=keep FETCH_ALL=$(FETCH_ALL); \
					elif [ "$$CURRENT_HASH" != "$$TARGET_HASH" ]; then \
						CURRENT_SHORT=$$(echo "$$CURRENT_HASH" | cut -c1-7); \
						TARGET_SHORT=$$(echo "$$TARGET_HASH" | cut -c1-7); \
						echo "$(YELLOW)🔄 커밋 불일치: $$CURRENT_SHORT → $$TARGET_SHORT$(NC)"; \
						cd - > /dev/null; \
						$(MAKE) git-fetch SOURCE_REPO=$(SOURCE_REPO) REF=$(REF) SYNC_MODE=keep FETCH_ALL=$(FETCH_ALL); \
					else \
						CURRENT_SHORT=$$(echo "$$CURRENT_HASH" | cut -c1-7); \
						CURRENT_BRANCH=$$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "detached"); \
						echo "$(GREEN)✓ 로컬 소스 유지 (브랜치: $$CURRENT_BRANCH, 커밋: $$CURRENT_SHORT)$(NC)"; \
						cd - > /dev/null; \
						$(MAKE) --no-print-directory git-log GIT_TARGET=source COUNT=5 GRAPH=false; \
					fi; \
					;; \
				reset|pull|*) \
					echo "$(BLUE)🔄 SYNC_MODE=$(SYNC_MODE): remote 동기화 필요$(NC)"; \
					git fetch origin --prune 2>/dev/null || true; \
					TARGET_REF="$(REF)"; \
					CURRENT_HASH=$$(git rev-parse HEAD 2>/dev/null || echo ""); \
					REMOTE_HASH=$$(git rev-parse "origin/$$TARGET_REF" 2>/dev/null || git rev-parse "$$TARGET_REF" 2>/dev/null || echo ""); \
					if [ -z "$$CURRENT_HASH" ] || [ -z "$$REMOTE_HASH" ]; then \
						echo "$(YELLOW)⚠️  해시 확인 불가, fetch 실행$(NC)"; \
						cd - > /dev/null; \
						$(MAKE) git-fetch SOURCE_REPO=$(SOURCE_REPO) REF=$(REF) SYNC_MODE=$(SYNC_MODE) FETCH_ALL=$(FETCH_ALL); \
					elif [ "$$CURRENT_HASH" != "$$REMOTE_HASH" ]; then \
						CURRENT_SHORT=$$(echo "$$CURRENT_HASH" | cut -c1-7); \
						REMOTE_SHORT=$$(echo "$$REMOTE_HASH" | cut -c1-7); \
						echo "$(YELLOW)🔄 remote 업데이트 감지: $$CURRENT_SHORT → $$REMOTE_SHORT$(NC)"; \
						cd - > /dev/null; \
						$(MAKE) git-fetch SOURCE_REPO=$(SOURCE_REPO) REF=$(REF) SYNC_MODE=$(SYNC_MODE) FETCH_ALL=$(FETCH_ALL); \
					else \
						CURRENT_SHORT=$$(echo "$$CURRENT_HASH" | cut -c1-7); \
						CURRENT_BRANCH=$$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "detached"); \
						echo "$(GREEN)✓ 이미 최신 상태 (브랜치: $$CURRENT_BRANCH, 커밋: $$CURRENT_SHORT)$(NC)"; \
						cd - > /dev/null; \
						$(MAKE) --no-print-directory git-log GIT_TARGET=source COUNT=5 GRAPH=false; \
					fi; \
					;; \
			esac; \
		fi; \
	else \
		echo "$(GRAY)ℹ️  UMF_MODE=local, 소스 fetch 건너뜀$(NC)"; \
	fi

validate-dockerfile: ## 🔧 Validate Dockerfile exists and is readable
	@if [ -z "$(strip $(DOCKERFILE_PATH))" ]; then \
		echo "[ERROR] DOCKERFILE_PATH가 비어 있습니다. 예: DOCKERFILE_PATH=./Dockerfile"; \
		exit 1; \
	fi
	@if [ ! -f "$(strip $(DOCKERFILE_PATH))" ]; then \
		echo "[ERROR] Dockerfile을 찾을 수 없습니다: $(strip $(DOCKERFILE_PATH))"; \
		exit 1; \
	else \
		$(call print_color, $(BLUE),🔎 Using Dockerfile: $(strip $(DOCKERFILE_PATH))); \
	fi

build: ensure-source validate-dockerfile check-docker make-build-args _compute-build-tag _prepare-build-hook ## 🎯 Build the Docker image
	@$(call print_color,$(BLUE),🔨 Building Docker image with tag: $(BUILD_TAG_COMPUTED))
	@echo "$(BLUE)🔍 Cache Debug Info:$(RESET)"
	@echo "  Environment: $(if $(CI),GitHub Actions,Local)"
	@echo "  CACHE_SCOPE: $(CACHE_SCOPE)"
	@echo "  DISABLE_CACHE: $(DISABLE_CACHE)"
	@echo "  BUILD_ARGS_CONTENT: $(BUILD_ARGS_CONTENT)"
	@$(if $(DISABLE_CACHE),echo "  CACHE: DISABLED",echo "  CACHE_IMAGE: $(CACHE_IMAGE)")
	@$(if $(DISABLE_CACHE),echo "  CACHE_FALLBACK: $(CACHE_IMAGE_MAIN)")
	@echo ""
	$(if $(filter true,$(CI)),$(call run_quiet, Image Build $(BUILD_TAG_COMPUTED), \
		DOCKER_BUILDKIT=$(DOCKER_BUILDKIT) docker buildx build \
			$(DOCKER_BUILD_OPTION) \
			$(BUILD_ARGS_CONTENT) \
			-f $(DOCKERFILE_PATH) \
			-t $(BUILD_TAG_COMPUTED) \
			$(BUILDX_FLAGS) \
			$(DOCKERFILE_CONTEXT) \
	),$(call run_interactive, Image Build $(BUILD_TAG_COMPUTED), \
		DOCKER_BUILDKIT=$(DOCKER_BUILDKIT) docker buildx build \
			$(DOCKER_BUILD_OPTION) \
			$(BUILD_ARGS_CONTENT) \
			-f $(DOCKERFILE_PATH) \
			-t $(BUILD_TAG_COMPUTED) \
			$(BUILDX_FLAGS) \
			$(DOCKERFILE_CONTEXT) \
	))
	@echo ""
	@$(call print_color, $(BLUE),--- Image Details ---)
	@docker images $(BUILD_TAG_COMPUTED)
	@echo "$(BUILD_TAG_COMPUTED)" > .build-info
	@$(call print_color, $(GREEN),✓ 빌드 정보 저장됨: .build-info)
	@if [ "$(AUTO_UPDATE_DEPLOY)" = "true" ]; then \
		echo ""; \
		$(call print_color, $(BLUE),🔄 배포 정보 자동 업데이트 중...); \
		$(MAKE) prepare-deploy ENVIRONMENT=$(ENVIRONMENT) 2>/dev/null || true; \
	else \
		$(call print_color, $(GRAY),💡 배포 정보 업데이트: make prepare-deploy ENVIRONMENT=$(ENVIRONMENT)); \
		$(call print_color, $(GRAY),💡 자동 업데이트: make build AUTO_UPDATE_DEPLOY=true ENVIRONMENT=$(ENVIRONMENT)); \
	fi

_compute-build-tag:
	@# UMF_MODE=global일 때 스크립트로 동적 태그 계산
	@# core.mk가 계산한 정식 값(SAFE_BRANCH/DATE/COMMIT_SHORT)을 전달해
	@# ENV(TAGNAME 등)와 실제 이미지 태그가 항상 같은 규칙을 쓰도록 한다.
	@# 단, make 파싱 시점에 source가 없어 unknown이면 스크립트가 직접 계산하도록 넘기지 않는다.
	$(eval BUILD_TAG_COMPUTED := $(shell \
		if [ "$(UMF_MODE)" = "global" ]; then \
			$(if $(filter-out unknown,$(SAFE_BRANCH)),UMF_BRANCH="$(SAFE_BRANCH)") \
			UMF_DATE="$(DATE)" \
			$(if $(filter-out unknown,$(CURRENT_COMMIT_SHORT)),UMF_SHA="$(CURRENT_COMMIT_SHORT)") \
			bash $(MAKEFILE_DIR)/scripts/compute_build_tag.sh \
				"$(SOURCE_DIR)" \
				"$(REF)" \
				"$(IMAGE_NAME)" \
				"$(SERVICE_KIND)" \
				"$(VERSION)" \
				"$(TAG_SUFFIX)"; \
		else \
			echo "$(FULL_TAG)"; \
		fi \
	))
	@echo "$(BLUE)🔍 Build Info:$(RESET)"
	@echo "  Mode: $(UMF_MODE)"
	@echo "  Tag: $(BUILD_TAG_COMPUTED)"
	@echo ""

docker-build:   ## 🎯 소스 fetch 후 Docker 명령어로 직접 빌드
	$(call log_info,"Docker 직접 빌드 시작...")

	@if [ ! -d "$(SOURCE_DIR)" ]; then \
		$(call sh_log_error,소스 디렉토리가 없습니다. 먼저 'make fetch'를 실행하세요.); \
		exit 1; \
	fi

	@echo ""
	@echo "=== 빌드 정보 ==="
	@echo "Dockerfile 모드: $(DOCKERFILE_MODE)"
	@echo "선택된 Dockerfile: $(DOCKERFILE_SELECTED)"
	@echo "선택된 Context: $(CONTEXT_SELECTED)"
	@echo ""

	@if [ ! -f "$(DOCKERFILE_SELECTED)" ]; then \
		$(call sh_log_error,Dockerfile을 찾을 수 없습니다: $(DOCKERFILE_SELECTED)); \
		exit 1; \
	fi

	@if [ ! -d "$(CONTEXT_SELECTED)" ]; then \
		$(call sh_log_error,빌드 컨텍스트 디렉토리가 없습니다: $(CONTEXT_SELECTED)); \
		exit 1; \
	fi

	@{ \
	  $(compute_build_vars); \
	  CACHE_FLAG=$$( [ "$(NO_CACHE)" = "true" ] && echo "--no-cache" ); \
	  echo "=== 생성된 이미지 태그 ==="; \
	  echo "$$IMAGE_TAG"; \
	  echo ""; \
	  echo "=== Docker 빌드 시작 ==="; \
	  echo ""; \
	  echo "🔍 실행할 명령어:"; \
	  echo "DOCKER_BUILDKIT=1 docker build $$CACHE_FLAG --build-arg NODE_VERSION=$(NODE_VERSION) --progress=plain -f $(DOCKERFILE_SELECTED) -t $$IMAGE_TAG $(CONTEXT_SELECTED)"; \
	  echo ""; \
	  DOCKER_BUILDKIT=1 docker build $$CACHE_FLAG \
	    --build-arg NODE_VERSION="$(NODE_VERSION)" \
	    --progress=plain \
	    -f "$(DOCKERFILE_SELECTED)" \
	    -t "$$IMAGE_TAG" \
	    "$(CONTEXT_SELECTED)" \
	  || { \
	    echo ""; \
	    printf "$(RED)============================================================$(NC)\n"; \
	    printf "$(RED)❌ Docker 빌드 실패$(NC)\n"; \
	    printf "$(RED)============================================================$(NC)\n"; \
	    exit 1; \
	  }; \
	  echo ""; \
	  printf "$(GREEN)============================================================$(NC)\n"; \
	  printf "$(GREEN)✅ Docker 빌드 성공: %s$(NC)\n" "$$IMAGE_TAG"; \
	  printf "$(GREEN)============================================================$(NC)\n"; \
	  echo ""; \
	  echo "이미지 정보: $$IMAGE_TAG"; \
	  docker images "$$IMAGE_TAG_NO_REGISTRY" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"; \
	}

	$(call log_success,"Docker 직접 빌드 완료")



build-clean: ## 🎯 Build without cache
	@$(call print_color, $(BLUE),🔨Building Docker image without cache)
	@$(MAKE) build FORCE_REBUILD=true

build-local: ## 🎯 Build locally without any cache (for testing)
	@$(call print_color, $(BLUE),🔨Building Docker image locally without cache)
	@DOCKER_BUILDKIT=$(DOCKER_BUILDKIT) docker buildx build \
		$(DOCKER_BUILD_OPTION) \
		$(BUILD_ARGS_CONTENT) \
		--no-cache \
		-f $(DOCKERFILE_PATH) \
		-t $(FULL_TAG) \
		--load \
		--progress=plain \
		.
	@echo ""
	@$(call print_color, $(BLUE),--- Image Details ---)
	@docker images $(FULL_TAG)


build-legacy: check-docker make-build-args ## 🎯 Build the Docker image
	@$(call print_color, $(BLUE),🔨Building Docker image with tag: $(TAGNAME))
	$(call run_pipe, Image Build $(FULL_TAG), \
		DOCKER_BUILDKIT=$(DOCKER_BUILDKIT) docker buildx build \
			$(DOCKER_BUILD_OPTION) \
			$(BUILD_ARGS_CONTENT) \
			$(BUILD_NO_CACHE) \
			-f $(DOCKERFILE_PATH) \
			-t $(FULL_TAG) \
			$(BUILDX_FLAGS) \
			. \
	)
	@echo ""
	@$(call print_color, $(BLUE),--- Image Details ---)
	@docker images $(FULL_TAG)



ensure-image: prepare-env ## 🔧 Ensure Docker image exists for operations
	$(eval FULL_TAG := $(shell grep '^DEPLOY_IMAGE=' .env 2>/dev/null | cut -d= -f2 || echo $(FULL_TAG)))
	@echo "🔍 Using image: $(FULL_TAG)"
	@docker image inspect $(FULL_TAG) >/dev/null 2>&1 || { \
		echo "❌ image not found: $(FULL_TAG). Run 'make build' first."; exit 1; }

tag-latest: build ## 🚀 Tag image as 'latest' and push
	@$(call colorecho, 🏷️  Tagging images as 'latest'...)
	@docker tag $(FULL_TAG) $(LATEST_TAG)
	@$(call timed_command, Push latest tag, \
		docker push $(LATEST_TAG))
	@$(call success, Tagged and pushed as 'latest')

push: ensure-image ## 🚀 Push image to registry
	@$(call print_color, $(BLUE),📦 Pushing image to registry...)
	@$(call run_pipe, "Docker push", docker push $(FULL_TAG))
	@$(call success, Successfully pushed '$(FULL_TAG)')

build-push: build push ## 🚀 Build then push

push-latest: ensure-image ## 🚀 Push 'latest' tag only
	$(call run_pipe, Docker push $(LATEST_TAG), docker push $(LATEST_TAG))

publish-all: build tag-latest push push-latest ## 🚀 Publish versioned + latest

# ================================================================
# 개발 및 디버깅 타겟들
# ================================================================

bash: ensure-image ## 🔧 Run bash in the container
	@$(call colorecho, 🐚 Starting bash in container...)
	@docker run -it --rm --entrypoint sh --name $(NAME)-debug $(FULL_TAG)

run: ensure-image ## 🔧 Run the container interactively
	@$(call colorecho, 🚀 Running container interactively...)
	@docker run -it --rm --name $(NAME)-run $(FULL_TAG)

exec: ensure-image  ## 🔧 Execute command in running container
	@$(call colorecho, 🔧 Executing in running container...)
	@docker exec -it $(NAME) sh

# ================================================================
# 멀티 플랫폼 빌드 (buildx 사용)
# ================================================================

build-multi: check-docker ## 🎯 Build multi-platform image (amd64, arm64)
	@$(call colorecho, 🏗️  Building multi-platform image...)
	@docker buildx create --use --name multi-builder 2>/dev/null || docker buildx use multi-builder
	@$(call timed_command, "Multi-platform build", \
		docker buildx build $(DOCKER_BUILD_OPTION) \
		--platform linux/amd64,linux/arm64 \
		--build-arg VERSION=$(TAGNAME) \
		-f $(DOCKERFILE_PATH) \
		-t $(FULL_TAG) \
		--push .)
	@$(call success, Multi-platform build completed)

# ================================================================
# Docker 정보 및 관리
# ================================================================

docker-info: ## 🔧 Show Docker and image information
	@echo "$(BLUE)Docker Information:$(RESET)"
	@echo "  Docker Version: $$(docker --version)"
	@echo "  Image Name: $(FULL_TAG)"
	@echo "  Latest Tag: $(LATEST_TAG)"
	@echo "  Dockerfile: $(DOCKERFILE_PATH)"
	@echo "  Build Options: $(DOCKER_BUILD_OPTION)"
	@echo ""
	@echo "$(BLUE)Local Images:$(RESET)"
	@docker images | grep $(APP_IMAGE_NAME) || echo "  No images found for $(APP_IMAGE_NAME)"
	@echo ""
	@echo "$(BLUE)Running Containers:$(RESET)"
	@docker ps | grep $(NAME) || echo "  No running containers for $(NAME)"

docker-clean: ## 🧹 Clean Docker resources (containers, images, volumes)
	@$(call colorecho, 🧹 Cleaning Docker resources...)
	@echo "Stopping containers..."
	@docker ps -q --filter "name=$(NAME)" | xargs -r docker stop
	@echo "Removing containers..."
	@docker ps -aq --filter "name=$(NAME)" | xargs -r docker rm
	@echo "Removing images..."
	@docker images -q $(APP_IMAGE_NAME) | xargs -r docker rmi -f
	@echo "Pruning system..."
	@docker system prune -f
	@$(call success, Docker cleanup completed)

docker-deep-clean: ## 🧹 Deep clean Docker (DANGEROUS - removes all unused resources)
	@$(call warn, This will remove ALL unused Docker resources)
	@echo "Continue? [y/N] " && read ans && [ $${ans:-N} = y ]
	@$(call colorecho, 🧹 Performing deep Docker cleanup...)
	@docker system prune -af --volumes
	@docker builder prune -af
	@$(call success, Deep Docker cleanup completed)

# ================================================================
# Docker Compose 통합 (compose.mk와 연동)
# ================================================================

docker-logs: ## 🔧 Show Docker container logs
	@docker logs -f $(NAME) 2>/dev/null || \
		docker-compose logs -f 2>/dev/null || \
		echo "No running containers found"

# ================================================================
# 보안 스캔 (선택적)
# ================================================================

security-scan: build ## � RRun security scan on the image
	@$(call colorecho, 🔒 Running security scan...)
	@if command -v trivy >/dev/null 2>&1; then \
		trivy image $(FULL_TAG); \
	elif command -v docker-security-scan >/dev/null 2>&1; then \
		docker-security-scan $(FULL_TAG); \
	else \
		$(call warn, No security scanner found. Install trivy or docker-security-scan); \
	fi

# ================================================================
# 배포 정보 관리
# ================================================================

prepare-deploy: ## 🚀 현재 빌드된 이미지로 배포 정보 업데이트
	@if [ ! -f .build-info ]; then \
		echo "❌ 빌드 정보가 없습니다. 먼저 'make build'를 실행하세요."; \
		exit 1; \
	fi
	@IMAGE_TAG=$$(cat .build-info); \
	CURRENT_USER=$$(whoami); \
	echo "🔄 배포 정보 업데이트 중..."; \
	echo "  이미지: $$IMAGE_TAG"; \
	echo "  환경: $(ENVIRONMENT)"; \
	echo "  배포자: $$CURRENT_USER"; \
	python3 $(MAKEFILE_DIR)/scripts/env_manager.py update \
		--environment $(ENVIRONMENT) \
		--image "$$IMAGE_TAG" \
		--ref "$(CURRENT_BRANCH)" \
		--version "$(VERSION)" \
		--commit-sha "$(CURRENT_COMMIT_LONG)" \
		--deployed-by "$$CURRENT_USER"
	@$(call print_color, $(GREEN),✓ 배포 정보가 .env.$(ENVIRONMENT)에 업데이트되었습니다)

update-deploy-info: ## 🔧 수동으로 배포 정보 업데이트 (IMAGE, REF, VERSION, COMMIT_SHA, DEPLOYED_BY 필요)
	@if [ -z "$(IMAGE)" ] || [ -z "$(REF)" ] || [ -z "$(VERSION)" ] || [ -z "$(COMMIT_SHA)" ] || [ -z "$(DEPLOYED_BY)" ]; then \
		echo "❌ 필수 변수가 누락되었습니다."; \
		echo "사용법: make update-deploy-info IMAGE=mycompany/app:v1.0.0 REF=main VERSION=v1.0.0 COMMIT_SHA=abc123 DEPLOYED_BY=jinwoo"; \
		exit 1; \
	fi
	@echo "🔄 수동 배포 정보 업데이트 중..."; \
	python3 $(MAKEFILE_DIR)/scripts/env_manager.py update \
		--environment $(ENVIRONMENT) \
		--image "$(IMAGE)" \
		--ref "$(REF)" \
		--version "$(VERSION)" \
		--commit-sha "$(COMMIT_SHA)" \
		--deployed-by "$(DEPLOYED_BY)"
	@$(call print_color, $(GREEN),✓ 배포 정보가 수동으로 업데이트되었습니다)

deploy-status: ## � 현재재 배포 상태 조회
	@echo "📊 $(ENVIRONMENT) 환경 배포 상태:"
	@python3 $(MAKEFILE_DIR)/scripts/env_manager.py status --environment $(ENVIRONMENT)

deploy-history: ## � 배포포 히스토리 조회 (Git 로그 기반)
	@echo "📈 최근 배포 히스토리:"
	@git log --oneline --grep="deploy:" -10 || echo "배포 관련 커밋이 없습니다."

build-and-prepare: build prepare-deploy ## 🎯 빌드 후 배포 정보 자동 업데이트

update-deploy-from-image: ## 🔧 이미지 태그에서 배포 정보 자동 추출 및 업데이트 (IMAGE=이미지태그 필요)
	@if [ -z "$(IMAGE)" ]; then \
		echo "❌ IMAGE 변수가 필요합니다."; \
		echo "사용법: make update-deploy-from-image IMAGE=mycompany/app:be-v0.0.0-develop-20251106-fbc4d2f8 ENVIRONMENT=prod"; \
		exit 1; \
	fi
	@echo "🔍 이미지 태그에서 정보 추출 중: $(IMAGE)"; \
	TAG_PART=$$(echo "$(IMAGE)" | cut -d: -f2); \
	COMMIT_SHA=$$(echo "$$TAG_PART" | grep -oE '[a-f0-9]{8}$$' || echo "unknown"); \
	VERSION=$$(echo "$$TAG_PART" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' || echo "v0.0.0"); \
	REF=$$(echo "$$TAG_PART" | grep -oE '(main|develop|stage|test)' || echo "unknown"); \
	DEPLOYED_BY=$$(whoami); \
	echo "  버전: $$VERSION"; \
	echo "  브랜치: $$REF"; \
	echo "  커밋: $$COMMIT_SHA"; \
	echo "  배포자: $$DEPLOYED_BY"; \
	python3 $(MAKEFILE_DIR)/scripts/env_manager.py update \
		--environment $(ENVIRONMENT) \
		--image "$(IMAGE)" \
		--ref "$$REF" \
		--version "$$VERSION" \
		--commit-sha "$$COMMIT_SHA" \
		--deployed-by "$$DEPLOYED_BY"
	@$(call print_color, $(GREEN),✓ 배포 정보가 이미지 태그에서 추출되어 업데이트되었습니다)

update-deploy-from-registry: ## 🔧 Registry에서 최신 이미지 정보로 배포 정보 업데이트
	@echo "🔍 Registry에서 최신 이미지 조회 중..."
	@LATEST_TAG=$$($(MAKE) --no-print-directory list-tags REPO_HUB="$(REPO_HUB)" NAME="$(NAME)" | grep -E "$(ENVIRONMENT)|main|develop" | head -1); \
	if [ -z "$$LATEST_TAG" ]; then \
		echo "❌ Registry에서 이미지를 찾을 수 없습니다."; \
		exit 1; \
	fi; \
	FULL_IMAGE="$(REPO_HUB)/$(NAME):$$LATEST_TAG"; \
	echo "  최신 이미지: $$FULL_IMAGE"; \
	$(MAKE) update-deploy-from-image IMAGE="$$FULL_IMAGE" ENVIRONMENT=$(ENVIRONMENT)

update-deploy-from-previous: ## 🔧 이전 배포 정보를 기반으로 업데이트 (대화형)
	@if [ ! -f .env.$(ENVIRONMENT) ]; then \
		echo "❌ .env.$(ENVIRONMENT) 파일이 없습니다."; \
		exit 1; \
	fi
	@PREV_IMAGE=$$(grep '^DEPLOY_IMAGE=' .env.$(ENVIRONMENT) | cut -d= -f2); \
	echo "🔍 이전 배포 이미지: $$PREV_IMAGE"; \
	echo ""; \
	echo "새 이미지를 입력하세요 (Enter로 이전 이미지 유지):"; \
	read NEW_IMAGE; \
	IMAGE=$${NEW_IMAGE:-$$PREV_IMAGE}; \
	$(MAKE) update-deploy-from-image IMAGE="$$IMAGE" ENVIRONMENT=$(ENVIRONMENT)

# ================================================================
# 레지스트리 관리
# ================================================================

login: ## � LLogin to Docker registry
	@$(call colorecho, 🔑 Logging in to Docker registry...)
	@if [ -n "$(DOCKER_REGISTRY_USER)" ] && [ -n "$(DOCKER_REGISTRY_PASS)" ]; then \
		echo "$(DOCKER_REGISTRY_PASS)" | docker login -u "$(DOCKER_REGISTRY_USER)" --password-stdin $(DOCKER_REGISTRY_URL); \
	else \
		docker login $(DOCKER_REGISTRY_URL); \
	fi

logout: ## � LLogout from Docker registry
	@$(call colorecho, 🔓 Logging out from Docker registry...)
	@docker logout $(DOCKER_REGISTRY_URL)

# ================================================================
# 이미지 분석
# ================================================================

image-size: build ## �  Show image size information
	@echo "$(BLUE)Image Size Analysis:$(RESET)"
	@docker images $(FULL_TAG) --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"
	@echo ""
	@if command -v dive >/dev/null 2>&1; then \
		$(call colorecho, 🔍 Running dive analysis...); \
		dive $(FULL_TAG); \
	else \
		$(call warn, Install 'dive' for detailed layer analysis: https://github.com/wagoodman/dive); \
	fi

image-history: build ## � Showw image build history
	@echo "$(BLUE)Image Build History:$(RESET)"
	@docker history $(FULL_TAG)

# ================================================================
# 캐시 관리
# ================================================================

clear-build-cache: ## 🧹 Clear Docker build cache
	@$(call colorecho, 🧹 Clearing Docker build cache...)
	@docker builder prune -f
	@$(call success, Build cache cleared)


list-tags: ## � List ttags from registry (supports private)
	@IGNORE_TAG="$(IGNORE_TAG)" REPO_HUB="$(REPO_HUB)" NAME="$(NAME)" PRIVATE="$(PRIVATE)" PAGE_SIZE="$(PAGE_SIZE)" AUTHFILE="$(AUTHFILE)" \
	DOCKER_USERNAME="$(DOCKER_USERNAME)" DOCKER_PASSWORD="$(DOCKER_PASSWORD)" \
	REG_USER="$(REG_USER)" REG_PASS="$(REG_PASS)" \
	"$(LIST_TAGS_SCRIPT)"


latest-tag: ## � Show lattest SemVer tag
	@$(MAKE) --no-print-directory list-tags REPO_HUB="$(REPO_HUB)" NAME="$(NAME)" | \
	grep -E '^[0-9]+(\.[0-9]+){1,2}(-[0-9A-Za-z.-]+)?$$' | sort -Vr | head -n1