# ================================================================
# Docker Build and Registry Operations
# ================================================================

.PHONY: build push tag-latest bash docker-clean docker-info

# ================================================================
# 메인 Docker 타겟들
# ================================================================

# 캐시 스코프 - 브랜치명을 안전한 Docker 태그로 변환
CACHE_SCOPE ?= $(shell echo "$(or $(SCOPE),$(shell git rev-parse --abbrev-ref HEAD))" | sed 's/[^a-zA-Z0-9-]/-/g')
CACHE_TAG ?= $(or $(CACHE_TAG),cache)

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

build: check-docker make-build-args ## 🎯 Build the Docker image
	@$(call print_color, $(BLUE),🔨Building Docker image with tag: $(TAGNAME))
	@echo "$(BLUE)🔍 Cache Debug Info:$(RESET)"
	@echo "  Environment: $(if $(CI),GitHub Actions,Local)"
	@echo "  CACHE_SCOPE: $(CACHE_SCOPE)"
	@echo "  DISABLE_CACHE: $(DISABLE_CACHE)"
	@echo "  CACHE_TAG: $(CACHE_TAG)"
	@$(if $(DISABLE_CACHE),echo "  CACHE: DISABLED",echo "  CACHE_IMAGE: $(CACHE_IMAGE)")
	@$(if $(DISABLE_CACHE),,echo "  CACHE_FALLBACK: $(CACHE_IMAGE_MAIN)")
	@echo "  CACHE_MODE: max (with multi-stage)"
	@echo "  CACHE_FROM: $(CACHE_FROM)"
	@echo "  CACHE_TO: $(CACHE_TO)"
	@echo "  BUILD_OUTPUT: $(BUILD_OUTPUT)"
	@echo "  BUILDX_FLAGS: $(BUILDX_FLAGS)"
	@echo ""
	$(call run_interactive, Image Build $(FULL_TAG), \
		DOCKER_BUILDKIT=$(DOCKER_BUILDKIT) docker buildx build \
			$(DOCKER_BUILD_OPTION) \
			$(BUILD_ARGS_CONTENT) \
			-f $(DOCKERFILE_PATH) \
			-t $(FULL_TAG) \
			$(BUILDX_FLAGS) \
			. \
	)
	@echo ""
	@$(call print_color, $(BLUE),--- Image Details ---)
	@docker images $(FULL_TAG)

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



ensure-image:
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
	@docker run -it --rm --name $(NAME)-debug $(FULL_TAG) sh

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

security-scan: build ## 🔒 Run security scan on the image
	@$(call colorecho, 🔒 Running security scan...)
	@if command -v trivy >/dev/null 2>&1; then \
		trivy image $(FULL_TAG); \
	elif command -v docker-security-scan >/dev/null 2>&1; then \
		docker-security-scan $(FULL_TAG); \
	else \
		$(call warn, No security scanner found. Install trivy or docker-security-scan); \
	fi

# ================================================================
# 레지스트리 관리
# ================================================================

login: ## 🔑 Login to Docker registry
	@$(call colorecho, 🔑 Logging in to Docker registry...)
	@if [ -n "$(DOCKER_REGISTRY_USER)" ] && [ -n "$(DOCKER_REGISTRY_PASS)" ]; then \
		echo "$(DOCKER_REGISTRY_PASS)" | docker login -u "$(DOCKER_REGISTRY_USER)" --password-stdin $(DOCKER_REGISTRY_URL); \
	else \
		docker login $(DOCKER_REGISTRY_URL); \
	fi

logout: ## 🔓 Logout from Docker registry
	@$(call colorecho, 🔓 Logging out from Docker registry...)
	@docker logout $(DOCKER_REGISTRY_URL)

# ================================================================
# 이미지 분석
# ================================================================

image-size: build ## 📊 Show image size information
	@echo "$(BLUE)Image Size Analysis:$(RESET)"
	@docker images $(FULL_TAG) --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"
	@echo ""
	@if command -v dive >/dev/null 2>&1; then \
		$(call colorecho, 🔍 Running dive analysis...); \
		dive $(FULL_TAG); \
	else \
		$(call warn, Install 'dive' for detailed layer analysis: https://github.com/wagoodman/dive); \
	fi

image-history: build ## 📈 Show image build history
	@echo "$(BLUE)Image Build History:$(RESET)"
	@docker history $(FULL_TAG)

# ================================================================
# 캐시 관리
# ================================================================

clear-build-cache: ## 🧹 Clear Docker build cache
	@$(call colorecho, 🧹 Clearing Docker build cache...)
	@docker builder prune -f
	@$(call success, Build cache cleared)
