# ================================================================
# Docker Build and Registry Operations
# ================================================================

.PHONY: build push tag-latest bash docker-clean docker-info

# ================================================================
# 메인 Docker 타겟들
# ================================================================

CACHE_SCOPE ?= $(or $(SCOPE),$(shell git rev-parse --abbrev-ref HEAD))
CACHE_FROM  := --cache-from=type=gha,scope=$(CACHE_SCOPE)
CACHE_TO    := --cache-to=type=gha,mode=max,scope=$(CACHE_SCOPE)

# buildx 출력 방식: 기본은 로컬 데몬에 적재(--load)
# PUSH=1로 호출하면 --push로 전환 (CI에서 push 타겟과 함께 사용)
BUILD_OUTPUT := --load
ifeq ($(PUSH),1)
BUILD_OUTPUT := --push
endif

# buildx 공통 옵션
BUILDX_FLAGS := $(CACHE_FROM) $(CACHE_TO) $(BUILD_OUTPUT) --progress=plain
BUILD_NO_CACHE :=
ifeq ($(FORCE_REBUILD),true)
  BUILD_NO_CACHE = --no-cache
endif

build: check-docker make-build-args ## 🎯 Build the Docker image
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


build-clean: ## 🎯 Build without cache
	@$(call print_color, $(BLUE),🔨Building Docker image without cache)
	@$(MAKE) build FORCE_REBUILD=true


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
	@$(call colorecho, 📦 Pushing images to registry...)
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
