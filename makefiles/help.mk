# ================================================================
# Help System and Documentation
# ================================================================

.PHONY: help list-targets help-docker help-git help-compose help-cleanup

# ================================================================
# 메인 Help 시스템
# ================================================================

help: ## 🏠 Show this help message
	@echo ""
	@echo "$(BLUE)📋 Universal Makefile System$(RESET)"
	@echo "$(BLUE)Project: $(NAME) v$(VERSION)$(RESET)"
	@echo "$(BLUE)Repository: $(REPO_HUB)/$(NAME)$(RESET)"
	@echo "$(BLUE)Current Branch: $(CURRENT_BRANCH)$(RESET)"
	@echo "$(BLUE)Environment: $(ENV)$(RESET)"
	@echo ""
	@echo "$(YELLOW)🎯 Main Build Targets:$(RESET)"
	@$(MAKE) --no-print-directory _show-category CATEGORY="🎯"
	@echo ""
	@echo "$(YELLOW)🚀 Release & Deploy:$(RESET)"
	@$(MAKE) --no-print-directory _show-category CATEGORY="🚀"
	@echo ""
	@echo "$(YELLOW)🌿 Git Workflow:$(RESET)"
	@$(MAKE) --no-print-directory _show-category CATEGORY="🌿"
	@echo ""
	@echo "$(YELLOW)🔧 Development & Debug:$(RESET)"
	@$(MAKE) --no-print-directory _show-category CATEGORY="🔧"
	@echo ""
	@echo "$(YELLOW)🧹 Cleanup & Utils:$(RESET)"
	@$(MAKE) --no-print-directory _show-category CATEGORY="🧹"
	@echo ""
	@echo "$(BLUE)📖 Detailed Help:$(RESET)"
	@echo "  $(GREEN)make help-docker$(RESET)     Docker-related commands"
	@echo "  $(GREEN)make help-git$(RESET)        Git workflow commands" 
	@echo "  $(GREEN)make help-compose$(RESET)    Docker Compose commands"
	@echo "  $(GREEN)make help-cleanup$(RESET)    Cleanup commands"
	@echo ""
	@echo "$(BLUE)💡 Usage Examples:$(RESET)"
	@echo "  make build VERSION=v2.0 DEBUG=true"
	@echo "  make auto-release"
	@echo "  make clean-old-branches"
	@echo "  make help-docker"

# 내부 함수: 카테고리별 타겟 표시
_show-category:
	@grep -E '^[a-zA-Z_-]+:.*?## $(CATEGORY).*$$' $(MAKEFILE_LIST) | \
		sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-20s$(RESET) %s\n", $$1, substr($$2, 3)}'

# ================================================================
# 상세 Help 시스템들
# ================================================================

help-docker: ## 🔧 Show Docker-related commands help
	@echo ""
	@echo "$(BLUE)🐳 Docker Commands Help$(RESET)"
	@echo ""
	@echo "$(YELLOW)Build & Registry:$(RESET)"
	@echo "  $(GREEN)build$(RESET)               Build Docker image"
	@echo "  $(GREEN)build-multi$(RESET)         Build multi-platform image (amd64, arm64)"
	@echo "  $(GREEN)build-no-cache$(RESET)      Build without using cache"
	@echo "  $(GREEN)push$(RESET)                Push image to registry"
	@echo "  $(GREEN)tag-latest$(RESET)          Tag as 'latest' and push"
	@echo ""
	@echo "$(YELLOW)Development:$(RESET)"
	@echo "  $(GREEN)bash$(RESET)                Run bash in container"
	@echo "  $(GREEN)run$(RESET)                 Run container interactively"
	@echo "  $(GREEN)exec$(RESET)                Execute command in running container"
	@echo ""
	@echo "$(YELLOW)Management:$(RESET)"
	@echo "  $(GREEN)docker-info$(RESET)         Show Docker and image information"
	@echo "  $(GREEN)docker-clean$(RESET)        Clean project Docker resources"
	@echo "  $(GREEN)docker-deep-clean$(RESET)   Deep clean all Docker resources (DANGEROUS)"
	@echo "  $(GREEN)security-scan$(RESET)       Run security scan on image"
	@echo "  $(GREEN)image-size$(RESET)          Show image size analysis"
	@echo ""
	@echo "$(BLUE)💡 Examples:$(RESET)"
	@echo "  make build DEBUG=true FORCE_REBUILD=true"
	@echo "  make build-multi     # Build for multiple architectures"
	@echo "  make bash           # Interactive shell in container"

help-git: ## 🔧 Show Git workflow commands help
	@echo ""
	@echo "$(BLUE)🌿 Git Workflow Commands Help$(RESET)"
	@echo ""
	@echo "$(YELLOW)Branch Management:$(RESET)"
	@echo "  $(GREEN)git-status$(RESET)          Show comprehensive git status"
	@echo "  $(GREEN)git-branches$(RESET)        Show all branches with status"
	@echo "  $(GREEN)sync-develop$(RESET)        Sync current branch to develop"
	@echo "  $(GREEN)start-release$(RESET)       Start release branch from develop"
	@echo ""
	@echo "$(YELLOW)Version Management:$(RESET)"
	@echo "  $(GREEN)bump-version$(RESET)        Calculate next patch version"
	@echo "  $(GREEN)bump-minor$(RESET)          Bump minor version"
	@echo "  $(GREEN)bump-major$(RESET)          Bump major version"
	@echo ""
	@echo "$(YELLOW)Release Process:$(RESET)"
	@echo "  $(GREEN)create-release-branch$(RESET) Create release branch with auto-versioning"
	@echo "  $(GREEN)push-release-branch$(RESET)   Push release branch to origin"
	@echo "  $(GREEN)finish-release$(RESET)        Complete release (merge, tag, GitHub release)"
	@echo "  $(GREEN)auto-release$(RESET)          Full automated release process"
	@echo ""
	@echo "$(YELLOW)Hotfix Support:$(RESET)"
	@echo "  $(GREEN)start-hotfix$(RESET)         Start hotfix branch from main"
	@echo "  $(GREEN)finish-hotfix$(RESET)        Complete hotfix process"
	@echo ""
	@echo "$(YELLOW)Cleanup:$(RESET)"
	@echo "  $(GREEN)list-old-branches$(RESET)    List merged release branches"
	@echo "  $(GREEN)clean-old-branches$(RESET)   Delete merged local release branches"
	@echo "  $(GREEN)clean-remote-branches$(RESET) Delete merged remote release branches"
	@echo ""
	@echo "$(BLUE)💡 Examples:$(RESET)"
	@echo "  make auto-release                    # Full automated release"
	@echo "  make start-hotfix HOTFIX_NAME=fix-bug # Start hotfix branch"
	@echo "  make bump-minor                      # Bump minor version"

help-compose: ## 🔧 Show Docker Compose commands help
	@echo ""
	@echo "$(BLUE)🐙 Docker Compose Commands Help$(RESET)"
	@echo ""
	@echo "$(YELLOW)Environment Management:$(RESET)"
	@echo "  $(GREEN)up$(RESET)                  Start production environment"
	@echo "  $(GREEN)down$(RESET)                Stop production environment"
	@echo "  $(GREEN)dev-up$(RESET)              Start development environment"
	@echo "  $(GREEN)dev-down$(RESET)            Stop development environment"
	@echo ""
	@echo "$(YELLOW)Monitoring:$(RESET)"
	@echo "  $(GREEN)logs$(RESET)                Show service logs"
	@echo "  $(GREEN)dev-logs$(RESET)            Show development logs"
	@echo "  $(GREEN)status$(RESET)              Show services status"
	@echo ""
	@echo "$(YELLOW)Operations:$(RESET)"
	@echo "  $(GREEN)restart$(RESET)             Restart all services"
	@echo "  $(GREEN)rebuild$(RESET)             Rebuild and restart services"
	@echo ""
	@echo "$(BLUE)💡 Examples:$(RESET)"
	@echo "  make up ENV=production    # Start production environment"
	@echo "  make dev-up              # Start development environment"
	@echo "  make logs                # Follow service logs"

help-cleanup: ## 🔧 Show cleanup commands help
	@echo ""
	@echo "$(BLUE)🧹 Cleanup Commands Help$(RESET)"
	@echo ""
	@echo "$(YELLOW)Project Cleanup:$(RESET)"
	@echo "  $(GREEN)clean$(RESET)               Clean temporary files and containers"
	@echo "  $(GREEN)env-clean$(RESET)           Clean .env files"
	@echo ""
	@echo "$(YELLOW)Docker Cleanup:$(RESET)"
	@echo "  $(GREEN)docker-clean$(RESET)        Clean project Docker resources"
	@echo "  $(GREEN)docker-deep-clean$(RESET)   Deep clean all Docker resources (DANGEROUS)"
	@echo "  $(GREEN)clear-build-cache$(RESET)   Clear Docker build cache"
	@echo ""
	@echo "$(YELLOW)Git Cleanup:$(RESET)"
	@echo "  $(GREEN)clean-old-branches$(RESET)  Delete merged local release branches"
	@echo "  $(GREEN)clean-remote-branches$(RESET) Delete merged remote release branches"
	@echo ""
	@echo "$(YELLOW)Complete Cleanup:$(RESET)"
	@echo "  $(GREEN)deep-clean$(RESET)          Complete project cleanup (DANGEROUS)"
	@echo ""
	@echo "$(RED)⚠️  Warning: Deep clean commands are irreversible!$(RESET)"
	@echo ""
	@echo "$(BLUE)💡 Examples:$(RESET)"
	@echo "  make clean                    # Safe cleanup"
	@echo "  make clean-old-branches       # Clean merged branches"
	@echo "  make docker-clean            # Clean Docker resources"

# ================================================================
# 타겟 검색 및 나열
# ================================================================

list-targets: ## 🔧 List all available targets
	@echo "$(BLUE)All Available Targets:$(RESET)"
	@$(MAKE) -qp | awk -F':' '/^[a-zA-Z0-9][^$$#\/\t=]*:([^=]|$$)/ {split($$1,A,/ /);for(i in A)print A[i]}' | sort -u

search-targets: ## 🔧 Search targets by keyword (usage: make search-targets KEYWORD=docker)
	@if [ -z "$(KEYWORD)" ]; then \
		$(call error, "KEYWORD is required. Usage: make search-targets KEYWORD=docker"); \
		exit 1; \
	fi; \
	echo "$(BLUE)Targets matching '$(KEYWORD)':$(RESET)"; \
	grep -E '^[a-zA-Z_-]+:.*?##.*$(KEYWORD)' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-20s$(RESET) %s\n", $$1, $$2}' || \
		echo "  No targets found matching '$(KEYWORD)'"

# ================================================================
# 타겟별 상세 도움말
# ================================================================

help-%: ## 🔧 Show detailed help for specific target (usage: make help-build)
	@TARGET=$(subst help-,,$@); \
	echo "$(BLUE)📖 Detailed Help for: $$TARGET$(RESET)"; \
	echo ""; \
	if grep -E "^$$TARGET:.*?##" $(MAKEFILE_LIST) >/dev/null 2>&1; then \
		echo "$(YELLOW)Description:$(RESET)"; \
		grep -E "^$$TARGET:.*?##" $(MAKEFILE_LIST) | \
			awk 'BEGIN {FS = ":.*?## "}; {print "  " $$2}'; \
		echo ""; \
		echo "$(YELLOW)Definition:$(RESET)"; \
		grep -A 10 "^$$TARGET:" $(MAKEFILE_LIST) | head -10 | sed 's/^/  /'; \
	else \
		echo "$(RED)Target '$$TARGET' not found or has no documentation.$(RESET)"; \
		echo ""; \
		echo "Use 'make search-targets KEYWORD=$$TARGET' to find similar targets."; \
	fi

# ================================================================
# 시스템 정보
# ================================================================

version-info: ## 🔧 Show version information
	@echo "$(BLUE)Version Information:$(RESET)"
	@echo "  Project Version: $(VERSION)"
	@echo "  Git Branch: $(CURRENT_BRANCH)"
	@echo "  Git Commit: $$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
	@echo "  Last Tag: $$(git describe --tags --abbrev=0 2>/dev/null || echo 'none')"
	@echo "  Makefile System: $$(cat $(MAKEFILE_DIR)/VERSION 2>/dev/null || echo 'unknown')"
	@echo "  Docker Version: $$(docker --version 2>/dev/null || echo 'not installed')"
	@echo "  Git Version: $$(git --version 2>/dev/null || echo 'not installed')"

# ================================================================
# 사용법 가이드
# ================================================================

getting-started: ## 🔧 Show getting started guide
	@echo ""
	@echo "$(BLUE)🚀 Getting Started with Universal Makefile System$(RESET)"
	@echo ""
	@echo "$(YELLOW)1. Quick Start:$(RESET)"
	@echo "   make help                    # Show all available commands"
	@echo "   make build                   # Build your application"
	@echo "   make up                      # Start the application"
	@echo ""
	@echo "$(YELLOW)2. Development Workflow:$(RESET)"
	@echo "   make dev-up                  # Start development environment"
	@echo "   make bash                    # Get shell access to container"
	@echo "   make logs                    # Watch application logs"
	@echo ""
	@echo "$(YELLOW)3. Release Workflow:$(RESET)"
	@echo "   make auto-release            # Automated release process"
	@echo "   make bump-version            # Just check next version"
	@echo "   make clean-old-branches      # Clean up after releases"
	@echo ""
	@echo "$(YELLOW)4. Troubleshooting:$(RESET)"
	@echo "   make debug-vars              # Check all variables"
	@echo "   make docker-info             # Check Docker status"
	@echo "   make clean                   # Clean up temporary files"
	@echo ""
	@echo "$(BLUE)📚 For more help:$(RESET)"
	@echo "   make help-docker             # Docker commands help"
	@echo "   make help-git                # Git workflow help"
	@echo "   make help-<target>           # Detailed help for any target"