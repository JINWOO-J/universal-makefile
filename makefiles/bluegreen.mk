# ============================================
# Blue/Green Deployment Makefile
# ============================================

# ============================================
# Initialization
# ============================================

bg-init: ## 🚀 Initialize Blue/Green deployment structure
	@$(ECHO_CMD) "$(CYAN)╔════════════════════════════════════════════════════════════╗$(RESET)"
	@$(ECHO_CMD) "$(CYAN)║        Initializing Blue/Green Deployment                 ║$(RESET)"
	@$(ECHO_CMD) "$(CYAN)╚════════════════════════════════════════════════════════════╝$(RESET)"
	@echo ""
	@echo "$(CYAN)🔹 Creating directory structure$(RESET)"
	@mkdir -p config
	@echo ""
	@echo "$(CYAN)🔹 Creating configuration files$(RESET)"
	@if [ -f "config/bluegreen.conf" ]; then \
		echo "  $(YELLOW)⚠ config/bluegreen.conf already exists, skipping$(RESET)"; \
	else \
		cp $(MAKEFILE_DIR)/templates/bluegreen.conf.template config/bluegreen.conf; \
		echo "  $(GREEN)✓ Created config/bluegreen.conf$(RESET)"; \
	fi
	@if [ "$(BG_USE_PROXY)" = "true" ]; then \
		if [ -f "$(BG_CONFIG_DIR)/nginx-proxy.conf" ]; then \
			echo "  $(YELLOW)⚠ config/nginx-proxy.conf already exists, skipping$(RESET)"; \
		else \
			cp $(MAKEFILE_DIR)/templates/nginx-proxy.conf.template config/nginx-proxy.conf; \
			sed -i.bak 's/__APP_PORT__/$(BG_APP_PORT)/g' config/nginx-proxy.conf; \
			rm -f config/nginx-proxy.conf.bak; \
			echo "  $(GREEN)✓ Created config/nginx-proxy.conf$(RESET)"; \
		fi; \
	fi
	@echo ""
	@echo "$(CYAN)🔹 Creating docker-compose file$(RESET)"
	@if [ -f "$(BG_COMPOSE_FILE)" ]; then \
		echo "  $(YELLOW)⚠ $(BG_COMPOSE_FILE) already exists, skipping$(RESET)"; \
	else \
		if [ "$(BG_USE_PROXY)" = "true" ]; then \
			cp $(MAKEFILE_DIR)/templates/docker-compose.bluegreen.yml.template $(BG_COMPOSE_FILE); \
			echo "  $(GREEN)✓ Created $(BG_COMPOSE_FILE) (with proxy)$(RESET)"; \
		else \
			cp $(MAKEFILE_DIR)/templates/docker-compose.bluegreen-noproxy.yml.template $(BG_COMPOSE_FILE); \
			echo "  $(GREEN)✓ Created $(BG_COMPOSE_FILE) (without proxy)$(RESET)"; \
		fi; \
	fi
	@echo ""
	@echo "$(CYAN)🔹 Creating environment files$(RESET)"
	@if [ ! -f ".env.common" ]; then \
		echo "# Common environment variables for both Blue and Green" > .env.common; \
		echo "  $(GREEN)✓ Created .env.common$(RESET)"; \
	else \
		echo "  $(YELLOW)⚠ .env.common already exists, skipping$(RESET)"; \
	fi
	@if [ ! -f ".env.blue" ]; then \
		echo "# Blue environment specific variables" > .env.blue; \
		echo "  $(GREEN)✓ Created .env.blue$(RESET)"; \
	else \
		echo "  $(YELLOW)⚠ .env.blue already exists, skipping$(RESET)"; \
	fi
	@if [ ! -f ".env.green" ]; then \
		echo "# Green environment specific variables" > .env.green; \
		echo "  $(GREEN)✓ Created .env.green$(RESET)"; \
	else \
		echo "  $(YELLOW)⚠ .env.green already exists, skipping$(RESET)"; \
	fi
	@if [ ! -f ".env.version" ]; then \
		echo "APP_VERSION=1.0.0" > .env.version; \
		echo "BUILD_DATE=$$(date -u +\"%Y-%m-%dT%H:%M:%SZ\")" >> .env.version; \
		echo "  $(GREEN)✓ Created .env.version$(RESET)"; \
	else \
		echo "  $(YELLOW)⚠ .env.version already exists, skipping$(RESET)"; \
	fi
	@if [ ! -f ".env.active" ]; then \
		echo "ACTIVE_ENV=blue" > .env.active; \
		echo "BLUE_VERSION=1.0.0" >> .env.active; \
		echo "GREEN_VERSION=1.0.0" >> .env.active; \
		echo "  $(GREEN)✓ Created .env.active$(RESET)"; \
	else \
		echo "  $(YELLOW)⚠ .env.active already exists, skipping$(RESET)"; \
	fi
	@echo ""
	@$(ECHO_CMD) "$(GREEN)╔════════════════════════════════════════════════════════════╗$(RESET)"
	@$(ECHO_CMD) "$(GREEN)║          Initialization Completed Successfully!           ║$(RESET)"
	@$(ECHO_CMD) "$(GREEN)╚════════════════════════════════════════════════════════════╝$(RESET)"
	@echo ""
	@echo "$(YELLOW)📝 Next Steps:$(RESET)"
	@echo "  1. Edit project.mk and set:"
	@echo "     $(GREEN)BG_ENABLED = true$(RESET)"
	@echo "  2. Review and customize:"
	@echo "     - config/bluegreen.conf"
	@echo "     - $(BG_COMPOSE_FILE)"
	@if [ "$(BG_USE_PROXY)" = "true" ]; then \
		echo "     - config/nginx-proxy.conf"; \
	fi
	@echo "  3. Build and deploy:"
	@echo "     $(GREEN)make bg-build$(RESET)"
	@echo "     $(GREEN)make bg-deploy VERSION=1.0.0$(RESET)"
	@echo ""

# Guard target to check if BG is enabled
_bg-check-enabled:
	@if [ "$(BG_ENABLED)" != "true" ]; then \
		echo "$(YELLOW)⚠ Blue/Green deployment is not enabled$(RESET)"; \
		echo "  Set $(GREEN)BG_ENABLED=true$(RESET) in project.mk"; \
		echo "  Or run $(GREEN)make bg-init$(RESET) to initialize"; \
		exit 1; \
	fi

# ============================================
# Help System (Integrated with help.mk)
# ============================================
# This content is now in help.mk as help-bg target

# ============================================
# Configuration Loading
# ============================================

# Load configuration files
-include .env.version
-include .env.active
-include .env.common
-include .env.blue
-include .env.green
-include config/bluegreen.conf

# Blue/Green Configuration (with defaults)
BG_ENABLED ?= false
BG_USE_PROXY ?= true
BG_COMPOSE_FILE ?= docker-compose.bluegreen.yml
BG_PROXY_PORT ?= 80
BG_APP_PORT ?= 8080
BG_BLUE_PORT ?= 8080
BG_GREEN_PORT ?= 8081
BG_HEALTH_ENDPOINT ?= /health
BG_HEALTH_CHECK_ENABLED ?= true
BG_HEALTH_CHECK_TIMEOUT ?= 30
BG_HEALTH_CHECK_RETRIES ?= 5
BG_HEALTH_CHECK_SCRIPT ?=
BG_ROLLBACK_HISTORY_SIZE ?= 5
BG_BUILD_ARGS ?=
SOURCE_DIR ?=

# Derive from project.mk
BG_IMAGE_NAME ?= $(REPO_HUB)/$(NAME)
PROJECT_NAME ?= $(NAME)

# Legacy support: if SOURCE_DIR is set, use source-based paths
ifneq ($(SOURCE_DIR),)
  BG_COMPOSE_FILE := $(SOURCE_DIR)/docker-compose.yml
  BG_CONFIG_DIR := $(SOURCE_DIR)/config
else
  BG_CONFIG_DIR := config
endif

# Basic variables
APP_VERSION ?= 1.0.0
ACTIVE_ENV ?= blue
BUILD_DATE := $(shell date -u +"%Y-%m-%dT%H:%M:%SZ")
HISTORY_FILE := .deploy-history.log
MAX_HISTORY := $(BG_ROLLBACK_HISTORY_SIZE)

# Docker Compose 설정
COMPOSE_FILE := $(SOURCE_DIR)/docker-compose.yml
COMPOSE_PROJECT := $(PROJECT_NAME)

# 스크립트 경로
SCRIPT_DIR := $(MAKEFILE_DIR)/scripts
HEALTH_CHECK_SCRIPT := $(SCRIPT_DIR)/health-check.sh
VERSION_CHECK_SCRIPT := $(SCRIPT_DIR)/version-check.sh
CUSTOM_HEALTH_CHECK_SCRIPT := $(SCRIPT_DIR)/custom-health-check.sh

# ============================================
# Blue/Green Deployment Targets
# ============================================

.PHONY: bg-version-set bg-version-show bg-build bg-build-blue bg-build-green \
	bg-deploy bg-deploy-blue bg-deploy-green bg-deploy-prepare bg-deploy-switch bg-deploy-verify \
	bg-health bg-health-blue bg-health-green bg-health-proxy \
	bg-rollback bg-rollback-version bg-rollback-history \
	bg-status bg-logs bg-logs-blue bg-logs-green \
	bg-clean bg-clean-all bg-init _bg-check-enabled

# ============================================
# Version Management
# ============================================

bg-version-set: ## 🚀 Set deployment version (VERSION=x.x.x)
	@if [ -z "$(VERSION)" ]; then \
		echo "$(RED)✗ VERSION is required$(RESET)"; \
		echo "  Usage: make bg-version-set VERSION=1.0.1"; \
		exit 1; \
	fi
	@echo "$(CYAN)🔹 Setting version to $(VERSION)$(RESET)"
	@cp .env.version .env.version.backup 2>/dev/null || true
	@echo "APP_VERSION=$(VERSION)" > .env.version
	@echo "BUILD_DATE=$(BUILD_DATE)" >> .env.version
	@echo "$(GREEN)✓ Version set to $(VERSION)$(RESET)"

bg-version-show: ## 🚀 Show current version and deployment status
	@$(ECHO_CMD) "$(CYAN)╔════════════════════════════════════════════════════════════╗$(RESET)"
	@$(ECHO_CMD) "$(CYAN)║                    Current Status                         ║$(RESET)"
	@$(ECHO_CMD) "$(CYAN)╚════════════════════════════════════════════════════════════╝$(RESET)"
	@echo ""
	@$(call print_var,Current Version,$(APP_VERSION))
	@$(call print_var,Build Date,$(BUILD_DATE))
	@$(call print_var,Active Environment,$(ACTIVE_ENV))
	@$(call print_var,Blue Version,$(BLUE_VERSION))
	@$(call print_var,Green Version,$(GREEN_VERSION))
	@echo ""
	@if [ -f "$(HISTORY_FILE)" ]; then \
		echo "$(YELLOW)Recent Deployments:$(RESET)"; \
		tail -n 5 $(HISTORY_FILE) | while read line; do echo "  $$line"; done; \
	fi

# ============================================
# Build Targets
# ============================================

bg-build: _bg-check-enabled ## 🚀 Build Docker image with current version
	@echo "$(CYAN)🔹 Building image via docker.mk: $(APP_VERSION)$(RESET)"
	@$(MAKE) build \
		VERSION=$(APP_VERSION) \
		DOCKER_BUILD_ARGS="$(DOCKER_BUILD_ARGS) $(BG_BUILD_ARGS) --build-arg BUILD_DATE=$(BUILD_DATE) --build-arg ENV=build"
	@echo "$(GREEN)✓ Build completed: $(APP_VERSION)$(RESET)"

bg-build-blue: _bg-check-enabled
	@echo "$(CYAN)🔹 Building blue environment via docker.mk$(RESET)"
	@$(MAKE) build \
		VERSION=$(VERSION) \
		DOCKER_BUILD_ARGS="$(DOCKER_BUILD_ARGS) $(BG_BUILD_ARGS) --build-arg BUILD_DATE=$(BUILD_DATE) --build-arg ENV=blue"
	@echo "$(GREEN)✓ Built blue environment: $(VERSION)$(RESET)"

bg-build-green: _bg-check-enabled
	@echo "$(CYAN)🔹 Building green environment via docker.mk$(RESET)"
	@$(MAKE) build \
		VERSION=$(VERSION) \
		DOCKER_BUILD_ARGS="$(DOCKER_BUILD_ARGS) $(BG_BUILD_ARGS) --build-arg BUILD_DATE=$(BUILD_DATE) --build-arg ENV=green"
	@echo "$(GREEN)✓ Built green environment: $(VERSION)$(RESET)"

# ============================================
# Deployment Targets
# ============================================

bg-deploy: ## 🚀 Deploy new version with Blue/Green strategy (VERSION=x.x.x)
	@$(ECHO_CMD) "$(CYAN)╔════════════════════════════════════════════════════════════╗$(RESET)"
	@$(ECHO_CMD) "$(CYAN)║              Starting Blue/Green Deployment                    ║$(RESET)"
	@$(ECHO_CMD) "$(CYAN)╚════════════════════════════════════════════════════════════╝$(RESET)"
	@echo ""
	@if [ -z "$(VERSION)" ]; then \
		echo "$(YELLOW)⚠ No VERSION specified, using current: $(APP_VERSION)$(RESET)"; \
		$(MAKE) _bg-deploy-flow VERSION=$(APP_VERSION); \
	else \
		$(MAKE) bg-version-set VERSION=$(VERSION); \
		$(MAKE) _bg-deploy-flow VERSION=$(VERSION); \
	fi

_bg-deploy-flow:
	@echo "$(CYAN)🔹 Current status:$(RESET)"
	@$(MAKE) bg-status
	@echo ""
	@echo "$(CYAN)🔹 Step 1: Prepare inactive environment$(RESET)"
	@$(MAKE) bg-deploy-prepare VERSION=$(VERSION)
	@echo ""
	@echo "$(CYAN)🔹 Step 2: Switch traffic$(RESET)"
	@$(MAKE) bg-deploy-switch
	@echo ""
	@echo "$(CYAN)🔹 Step 3: Verify deployment$(RESET)"
	@$(MAKE) bg-deploy-verify
	@echo ""
	@$(ECHO_CMD) "$(GREEN)╔════════════════════════════════════════════════════════════╗$(RESET)"
	@$(ECHO_CMD) "$(GREEN)║           Deployment Completed Successfully!              ║$(RESET)"
	@$(ECHO_CMD) "$(GREEN)╚════════════════════════════════════════════════════════════╝$(RESET)"

bg-deploy-prepare:
	@if [ "$(ACTIVE_ENV)" = "blue" ]; then \
		echo "$(CYAN)🔹 Preparing green environment (inactive)$(RESET)"; \
		$(MAKE) _deploy-to-env TARGET_ENV=green VERSION=$(VERSION); \
	else \
		echo "$(CYAN)🔹 Preparing blue environment (inactive)$(RESET)"; \
		$(MAKE) _deploy-to-env TARGET_ENV=blue VERSION=$(VERSION); \
	fi

bg-deploy-blue:
	@$(MAKE) _deploy-to-env TARGET_ENV=blue VERSION=$(VERSION)

bg-deploy-green:
	@$(MAKE) _deploy-to-env TARGET_ENV=green VERSION=$(VERSION)

_deploy-to-env:
	@echo "$(CYAN)🔹 Building $(TARGET_ENV) environment: $(VERSION)$(RESET)"
	@docker build \
		--build-arg VERSION=$(VERSION) \
		--build-arg ENV=$(TARGET_ENV) \
		--build-arg BUILD_DATE=$(BUILD_DATE) \
		-t $(DOCKER_IMAGE_NAME):$(VERSION) \
		-f $(SOURCE_DIR)/Dockerfile $(SOURCE_DIR)
	@echo ""
	@echo "$(CYAN)🔹 Starting $(TARGET_ENV) container$(RESET)"
	@if [ "$(TARGET_ENV)" = "blue" ]; then \
		docker stop $(PROJECT_NAME)-app-blue 2>/dev/null || true; \
		docker rm $(PROJECT_NAME)-app-blue 2>/dev/null || true; \
		export BLUE_VERSION=$(VERSION) PROJECT_NAME=$(PROJECT_NAME) DOCKER_IMAGE_NAME=$(DOCKER_IMAGE_NAME) BUILD_DATE=$(BUILD_DATE); \
		docker-compose -f $(SOURCE_DIR)/docker-compose.yml up -d app-blue; \
	else \
		docker stop $(PROJECT_NAME)-app-green 2>/dev/null || true; \
		docker rm $(PROJECT_NAME)-app-green 2>/dev/null || true; \
		export GREEN_VERSION=$(VERSION) PROJECT_NAME=$(PROJECT_NAME) DOCKER_IMAGE_NAME=$(DOCKER_IMAGE_NAME) BUILD_DATE=$(BUILD_DATE); \
		docker-compose -f $(SOURCE_DIR)/docker-compose.yml up -d app-green; \
	fi
	@echo ""
	@echo "$(CYAN)🔹 Waiting for container to be ready...$(RESET)"
	@sleep 5
	@echo ""
	@echo "$(CYAN)🔹 Running health checks$(RESET)"
	@$(MAKE) _health-check-env TARGET_ENV=$(TARGET_ENV)
	@echo ""
	@echo "$(GREEN)✓ $(TARGET_ENV) environment ready: $(VERSION)$(RESET)"

bg-deploy-switch:
	@if [ "$(BG_USE_PROXY)" = "true" ]; then \
		if [ "$(ACTIVE_ENV)" = "blue" ]; then \
			echo "$(CYAN)🔹 Switching from blue to green (via proxy)$(RESET)"; \
			$(MAKE) _bg-switch-with-proxy TARGET_ENV=green; \
		else \
			echo "$(CYAN)🔹 Switching from green to blue (via proxy)$(RESET)"; \
			$(MAKE) _bg-switch-with-proxy TARGET_ENV=blue; \
		fi; \
	else \
		if [ "$(ACTIVE_ENV)" = "blue" ]; then \
			echo "$(CYAN)🔹 Switching from blue to green (via port)$(RESET)"; \
			$(MAKE) _bg-switch-with-port TARGET_ENV=green; \
		else \
			echo "$(CYAN)🔹 Switching from green to blue (via port)$(RESET)"; \
			$(MAKE) _bg-switch-with-port TARGET_ENV=blue; \
		fi; \
	fi

_bg-switch-with-proxy:
	@echo "$(CYAN)🔹 Generating nginx configuration from template$(RESET)"
	@if [ "$(TARGET_ENV)" = "blue" ]; then \
		sed 's/__BACKEND_HOST__/$(PROJECT_NAME)-blue/g' config/nginx-proxy.conf.template > config/nginx-proxy.conf.new; \
	else \
		sed 's/__BACKEND_HOST__/$(PROJECT_NAME)-green/g' config/nginx-proxy.conf.template > config/nginx-proxy.conf.new; \
	fi
	@echo ""
	@echo "$(CYAN)🔹 Testing nginx configuration syntax$(RESET)"
	@docker cp config/nginx-proxy.conf.new $(PROJECT_NAME)-proxy:/tmp/default.conf.test
	@if ! docker exec $(PROJECT_NAME)-proxy nginx -t -c /tmp/default.conf.test; then \
		echo "$(RED)✗ Nginx config test failed$(RESET)"; \
		rm -f config/nginx-proxy.conf.new; \
		exit 1; \
	fi
	@echo ""
	@echo "$(CYAN)🔹 Copying configuration to container$(RESET)"
	@docker cp config/nginx-proxy.conf.new $(PROJECT_NAME)-proxy:/etc/nginx/conf.d/default.conf
	@echo ""
	@echo "$(CYAN)🔹 Reloading nginx$(RESET)"
	@docker exec $(PROJECT_NAME)-proxy nginx -s reload
	@sleep 2
	@echo ""
	@echo "$(CYAN)🔹 Updating .env.active$(RESET)"
	@sed -i.bak "s/ACTIVE_ENV=.*/ACTIVE_ENV=$(TARGET_ENV)/" .env.active
	@if [ "$(TARGET_ENV)" = "blue" ]; then \
		sed -i.bak "s/BLUE_VERSION=.*/BLUE_VERSION=$(APP_VERSION)/" .env.active; \
	else \
		sed -i.bak "s/GREEN_VERSION=.*/GREEN_VERSION=$(APP_VERSION)/" .env.active; \
	fi
	@rm -f .env.active.bak config/nginx-proxy.conf.new
	@echo ""
	@$(MAKE) _log-deployment ACTION=PROXY_SWITCH FROM_ENV=$(ACTIVE_ENV) TO_ENV=$(TARGET_ENV) VERSION=$(APP_VERSION) STATUS=SUCCESS
	@echo "$(GREEN)✓ Traffic switched to $(TARGET_ENV) via proxy$(RESET)"

_bg-switch-with-port:
	@echo "$(CYAN)🔹 Stopping active container$(RESET)"
	@if [ "$(ACTIVE_ENV)" = "blue" ]; then \
		docker-compose -f $(BG_COMPOSE_FILE) stop app-blue; \
		echo "  Stopped blue container"; \
	else \
		docker-compose -f $(BG_COMPOSE_FILE) stop app-green; \
		echo "  Stopped green container"; \
	fi
	@echo ""
	@echo "$(CYAN)🔹 Updating port mapping in compose file or env$(RESET)"
	@if [ "$(TARGET_ENV)" = "blue" ]; then \
		echo "BG_ACTIVE_PORT=$(BG_BLUE_PORT)" > .env.port; \
		echo "  Set active port to $(BG_BLUE_PORT) for blue"; \
	else \
		echo "BG_ACTIVE_PORT=$(BG_GREEN_PORT)" > .env.port; \
		echo "  Set active port to $(BG_GREEN_PORT) for green"; \
	fi
	@echo ""
	@echo "$(CYAN)🔹 Starting inactive container$(RESET)"
	@if [ "$(TARGET_ENV)" = "blue" ]; then \
		export BLUE_VERSION=$(APP_VERSION) PROJECT_NAME=$(PROJECT_NAME) BG_ACTIVE_PORT=$(BG_BLUE_PORT); \
		docker-compose -f $(BG_COMPOSE_FILE) up -d app-blue; \
		echo "  Started blue container on port $(BG_BLUE_PORT)"; \
	else \
		export GREEN_VERSION=$(APP_VERSION) PROJECT_NAME=$(PROJECT_NAME) BG_ACTIVE_PORT=$(BG_GREEN_PORT); \
		docker-compose -f $(BG_COMPOSE_FILE) up -d app-green; \
		echo "  Started green container on port $(BG_GREEN_PORT)"; \
	fi
	@echo ""
	@echo "$(CYAN)🔹 Updating .env.active$(RESET)"
	@sed -i.bak "s/ACTIVE_ENV=.*/ACTIVE_ENV=$(TARGET_ENV)/" .env.active
	@if [ "$(TARGET_ENV)" = "blue" ]; then \
		sed -i.bak "s/BLUE_VERSION=.*/BLUE_VERSION=$(APP_VERSION)/" .env.active; \
	else \
		sed -i.bak "s/GREEN_VERSION=.*/GREEN_VERSION=$(APP_VERSION)/" .env.active; \
	fi
	@rm -f .env.active.bak
	@echo ""
	@$(MAKE) _log-deployment ACTION=PORT_SWITCH FROM_ENV=$(ACTIVE_ENV) TO_ENV=$(TARGET_ENV) VERSION=$(APP_VERSION) STATUS=SUCCESS
	@echo "$(GREEN)✓ Traffic switched to $(TARGET_ENV) via port mapping$(RESET)"

_switch-to-env:
	@echo "$(CYAN)🔹 Updating nginx configuration$(RESET)"
	@if [ "$(TARGET_ENV)" = "blue" ]; then \
		sed 's/__BACKEND_HOST__/$(PROJECT_NAME)-app-blue/g' config/nginx-proxy.conf.template > config/nginx-proxy.conf.new; \
	else \
		sed 's/__BACKEND_HOST__/$(PROJECT_NAME)-app-green/g' config/nginx-proxy.conf.template > config/nginx-proxy.conf.new; \
	fi
	@echo ""
	@echo "$(CYAN)🔹 Testing nginx configuration$(RESET)"
	@docker cp config/nginx-proxy.conf.new $(PROJECT_NAME)-proxy:/tmp/default.conf.test
	@if ! docker exec $(PROJECT_NAME)-proxy nginx -t; then \
		echo "$(RED)✗ Nginx config test failed$(RESET)"; \
		exit 1; \
	fi
	@echo ""
	@echo "$(CYAN)🔹 Applying new configuration$(RESET)"
	@cp config/nginx-proxy.conf.new config/nginx-proxy.conf
	@sleep 1
	@docker exec $(PROJECT_NAME)-proxy nginx -s reload
	@sleep 2
	@echo ""
	@echo "$(CYAN)🔹 Updating active environment$(RESET)"
	@sed -i.bak "s/ACTIVE_ENV=.*/ACTIVE_ENV=$(TARGET_ENV)/" .env.active
	@if [ "$(TARGET_ENV)" = "blue" ]; then \
		sed -i.bak "s/BLUE_VERSION=.*/BLUE_VERSION=$(APP_VERSION)/" .env.active; \
	else \
		sed -i.bak "s/GREEN_VERSION=.*/GREEN_VERSION=$(APP_VERSION)/" .env.active; \
	fi
	@echo ""
	@$(MAKE) _log-deployment ACTION=SWITCH FROM_ENV=$(ACTIVE_ENV) TO_ENV=$(TARGET_ENV) VERSION=$(APP_VERSION) STATUS=SUCCESS
	@echo "$(GREEN)✓ Traffic switched to $(TARGET_ENV)$(RESET)"

bg-deploy-verify:
	@echo "$(CYAN)🔹 Verifying deployment$(RESET)"
	@$(MAKE) bg-health-proxy
	@$(MAKE) bg-health
	@echo "$(GREEN)✓ Deployment verified$(RESET)"

# ============================================
# Health Check Targets
# ============================================

bg-health: ## 🚀 Check health of all environments
	@echo "$(CYAN)🔹 Checking all environments$(RESET)"
	@$(MAKE) bg-health-blue
	@$(MAKE) bg-health-green
	@$(MAKE) bg-health-proxy

bg-health-blue:
	@$(MAKE) _health-check-env TARGET_ENV=blue

bg-health-green:
	@$(MAKE) _health-check-env TARGET_ENV=green

bg-health-proxy:
	@echo "$(CYAN)🔹 Checking proxy health$(RESET)"
	@if ! bash $(HEALTH_CHECK_SCRIPT) "http://localhost:$(BG_PROXY_PORT)$(BG_HEALTH_ENDPOINT)" "$(BG_HEALTH_CHECK_TIMEOUT)" "$(BG_HEALTH_CHECK_RETRIES)"; then \
		echo "$(RED)✗ Proxy health check failed$(RESET)"; \
		exit 1; \
	fi

_health-check-env:
	@if [ "$(TARGET_ENV)" = "blue" ]; then \
		CONTAINER=$(PROJECT_NAME)-app-blue; \
	else \
		CONTAINER=$(PROJECT_NAME)-app-green; \
	fi; \
	echo "$(CYAN)  Checking $(TARGET_ENV) environment$(RESET)"; \
	if ! docker ps | grep -q $$CONTAINER; then \
		echo "$(YELLOW)  ⚠ Container not running$(RESET)"; \
		exit 0; \
	fi; \
	CONTAINER_IP=$$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $$CONTAINER); \
	CONTAINER_PORT=$(BG_APP_PORT); \
	if [ -n "$(BG_HEALTH_CHECK_SCRIPT)" ] && [ -f "$(BG_HEALTH_CHECK_SCRIPT)" ]; then \
		echo "$(CYAN)  Using custom health check script: $(BG_HEALTH_CHECK_SCRIPT)$(RESET)"; \
		bash "$(BG_HEALTH_CHECK_SCRIPT)" "$$CONTAINER_IP" "$$CONTAINER_PORT" "$(BG_HEALTH_ENDPOINT)" "$(BG_HEALTH_CHECK_TIMEOUT)" "$(BG_HEALTH_CHECK_RETRIES)"; \
	else \
		echo "$(CYAN)  Using default HTTP health check$(RESET)"; \
		bash $(HEALTH_CHECK_SCRIPT) "http://$$CONTAINER_IP:$$CONTAINER_PORT$(BG_HEALTH_ENDPOINT)" "$(BG_HEALTH_CHECK_TIMEOUT)" "$(BG_HEALTH_CHECK_RETRIES)"; \
	fi

# ============================================
# Rollback Targets
# ============================================

bg-rollback: ## 🚀 Rollback to previous environment
	@$(ECHO_CMD) "$(CYAN)╔════════════════════════════════════════════════════════════╗$(RESET)"
	@$(ECHO_CMD) "$(CYAN)║                  Rolling Back Deployment                  ║$(RESET)"
	@$(ECHO_CMD) "$(CYAN)╚════════════════════════════════════════════════════════════╝$(RESET)"
	@echo ""
	@if [ "$(ACTIVE_ENV)" = "blue" ]; then \
		echo "$(YELLOW)⏪ Rolling back from blue to green$(RESET)"; \
		$(MAKE) _switch-to-env TARGET_ENV=green; \
	else \
		echo "$(YELLOW)⏪ Rolling back from green to blue$(RESET)"; \
		$(MAKE) _switch-to-env TARGET_ENV=blue; \
	fi
	@$(MAKE) _log-deployment ACTION=ROLLBACK FROM_ENV=$(ACTIVE_ENV) TO_ENV="" VERSION=$(APP_VERSION) STATUS=SUCCESS
	@echo ""
	@echo "$(GREEN)✓ Rollback completed$(RESET)"

bg-rollback-version:
	@if [ -z "$(VERSION)" ]; then \
		echo "$(RED)✗ Error: VERSION is required$(RESET)"; \
		echo "  Usage: make bg-rollback-version VERSION=1.0.0"; \
		exit 1; \
	fi
	@echo "$(YELLOW)⏪ Rolling back to version $(VERSION)$(RESET)"
	@$(MAKE) bg-version-set VERSION=$(VERSION)
	@$(MAKE) bg-deploy VERSION=$(VERSION)

bg-rollback-history: ## 🚀 Show deployment history (last 5)
	@$(ECHO_CMD) "$(CYAN)╔════════════════════════════════════════════════════════════╗$(RESET)"
	@$(ECHO_CMD) "$(CYAN)║                  Deployment History                       ║$(RESET)"
	@$(ECHO_CMD) "$(CYAN)╚════════════════════════════════════════════════════════════╝$(RESET)"
	@echo ""
	@if [ -f "$(HISTORY_FILE)" ]; then \
		tail -n $(MAX_HISTORY) $(HISTORY_FILE); \
	else \
		echo "$(YELLOW)No deployment history found$(RESET)"; \
	fi

# ============================================
# Status & Logs
# ============================================

bg-status: ## 🚀 Show current deployment status
	@$(ECHO_CMD) "$(CYAN)╔════════════════════════════════════════════════════════════╗$(RESET)"
	@$(ECHO_CMD) "$(CYAN)║                    System Status                          ║$(RESET)"
	@$(ECHO_CMD) "$(CYAN)╚════════════════════════════════════════════════════════════╝$(RESET)"
	@echo ""
	@$(call print_var,Version,$(APP_VERSION))
	@$(call print_var,Active Environment,$(ACTIVE_ENV))
	@$(call print_var,Blue Version,$(BLUE_VERSION))
	@$(call print_var,Green Version,$(GREEN_VERSION))
	@echo ""
	@echo "$(YELLOW)Container Status:$(RESET)"
	@docker ps --filter "name=$(PROJECT_NAME)-" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" || true

bg-logs: ## 🚀 Show logs from all containers
	@docker-compose -f $(SOURCE_DIR)/docker-compose.yml logs -f

bg-logs-blue:
	@docker-compose -f $(SOURCE_DIR)/docker-compose.yml logs -f app-blue

bg-logs-green:
	@docker-compose -f $(SOURCE_DIR)/docker-compose.yml logs -f app-green

# ============================================
# Cleanup Targets
# ============================================

bg-clean: ## 🚀 Clean inactive environment
	@echo "$(CYAN)🔹 Cleaning inactive environment$(RESET)"
	@if [ "$(ACTIVE_ENV)" = "blue" ]; then \
		echo "  Stopping green environment"; \
		docker-compose -f $(SOURCE_DIR)/docker-compose.yml stop app-green; \
	else \
		echo "  Stopping blue environment"; \
		docker-compose -f $(SOURCE_DIR)/docker-compose.yml stop app-blue; \
	fi
	@echo "$(GREEN)✓ Cleanup completed$(RESET)"

bg-clean-all: ## 🚀 Clean all deployment resources
	@echo "$(CYAN)🔹 Cleaning all environments$(RESET)"
	@docker-compose -f $(SOURCE_DIR)/docker-compose.yml down -v
	@docker images | grep $(DOCKER_IMAGE_NAME) | awk '{print $$3}' | xargs -r docker rmi -f || true
	@echo "$(GREEN)✓ All cleaned$(RESET)"

# ============================================
# Internal Helpers
# ============================================

_log-deployment:
	@echo "$$(date '+%Y-%m-%d %H:%M:%S') | $(ACTION) | $(VERSION) | $(FROM_ENV) -> $(TO_ENV) | $(STATUS) | $$(whoami)@$$(hostname)" >> $(HISTORY_FILE)
	@tail -n $(MAX_HISTORY) $(HISTORY_FILE) > $(HISTORY_FILE).tmp && mv $(HISTORY_FILE).tmp $(HISTORY_FILE)
