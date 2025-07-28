# ================================================================
# Cleanup and Utility Operations
# ================================================================

.PHONY: clean env-clean deep-clean safe-clean
.PHONY: clean-temp clean-logs clean-cache clean-build
.PHONY: clean-all-containers clean-all-images clean-all-volumes

# ================================================================
# 기본 정리 타겟들
# ================================================================

clean: ## 🧹 Clean temporary files and safe cleanup
	@$(call colorecho, "🧹 Cleaning temporary files...")
	@$(MAKE) clean-temp
	@$(MAKE) clean-logs
	@$(MAKE) env-clean
	@$(call success, "Basic cleanup completed")

safe-clean: clean ## 🧹 Alias for clean (safe cleanup)

deep-clean: ## 🧹 Complete cleanup (DANGEROUS - removes all project artifacts)
	@$(call warn, "This will perform a COMPLETE cleanup of all project artifacts")
	@$(call warn, "This includes:")
	@echo "  - All temporary files"
	@echo "  - All Docker containers, images, and volumes"
	@echo "  - All build artifacts"
	@echo "  - All log files"
	@echo "  - All cache files"
	@echo ""
	@echo "$(RED)This action is IRREVERSIBLE!$(RESET)"
	@echo ""
	@echo "Continue? [y/N] " && read ans && [ $${ans:-N} = y ]
	@$(call colorecho, "🧹 Performing deep cleanup...")
	@$(MAKE) clean-temp
	@$(MAKE) clean-logs
	@$(MAKE) clean-cache
	@$(MAKE) clean-build
	@$(MAKE) env-clean
	@$(MAKE) docker-deep-clean
	@$(MAKE) clean-old-branches
	@$(call success, "Deep cleanup completed")

# ================================================================
# 임시 파일 정리
# ================================================================

clean-temp: ## 🧹 Clean temporary files
	@$(call colorecho, "🗑️  Cleaning temporary files...")
	@rm -f .NEW_VERSION.tmp || true
	@rm -f *.tmp || true
	@rm -f .DS_Store || true
	@find . -name "*.tmp" -type f -delete 2>/dev/null || true
	@find . -name ".DS_Store" -type f -delete 2>/dev/null || true
	@find . -name "Thumbs.db" -type f -delete 2>/dev/null || true
	@find . -name "*.swp" -type f -delete 2>/dev/null || true
	@find . -name "*.swo" -type f -delete 2>/dev/null || true
	@find . -name "*~" -type f -delete 2>/dev/null || true
	@$(call success, "Temporary files cleaned")

clean-logs: ## 🧹 Clean log files
	@$(call colorecho, "📋 Cleaning log files...")
	@rm -rf logs/ || true
	@rm -f *.log || true
	@find . -name "*.log" -type f -delete 2>/dev/null || true
	@find . -name "*.log.*" -type f -delete 2>/dev/null || true
	@$(call success, "Log files cleaned")

clean-cache: ## 🧹 Clean cache files and directories
	@$(call colorecho, "💾 Cleaning cache files...")
	@rm -rf .cache/ || true
	@rm -rf __pycache__/ || true
	@find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
	@find . -name "*.pyc" -type f -delete 2>/dev/null || true
	@find . -name "*.pyo" -type f -delete 2>/dev/null || true
	@rm -rf node_modules/.cache/ || true
	@rm -rf .npm/ || true
	@rm -rf .yarn/cache/ || true
	@rm -rf target/debug/ || true
	@rm -rf target/release/ || true
	@$(call success, "Cache files cleaned")

clean-build: ## 🧹 Clean build artifacts
	@$(call colorecho, "🔨 Cleaning build artifacts...")
	@rm -rf build/ || true
	@rm -rf dist/ || true
	@rm -rf out/ || true
	@rm -rf target/ || true
	@rm -rf .build/ || true
	@find . -name "*.o" -type f -delete 2>/dev/null || true
	@find . -name "*.so" -type f -delete 2>/dev/null || true
	@find . -name "*.dylib" -type f -delete 2>/dev/null || true
	@find . -name "*.dll" -type f -delete 2>/dev/null || true
	@$(call success, "Build artifacts cleaned")

# ================================================================
# 환경 파일 정리
# ================================================================

env-clean: ## 🧹 Clean environment files
	@$(call colorecho, "🌍 Cleaning environment files...")
	@rm -f .env || true
	@rm -f .env.local || true
	@rm -f .env.*.local || true
	@find . -name ".env.*.local" -type f -delete 2>/dev/null || true
	@$(call success, "Environment files cleaned")

# ================================================================
# 언어별 정리
# ================================================================

clean-node: ## 🧹 Clean Node.js specific files
	@$(call colorecho, "📦 Cleaning Node.js files...")
	@rm -rf node_modules/ || true
	@rm -f package-lock.json || true
	@rm -f yarn.lock || true
	@rm -f .yarn/install-state.gz || true
	@rm -rf .yarn/cache/ || true
	@rm -rf .npm/ || true
	@$(call success, "Node.js files cleaned")

clean-python: ## 🧹 Clean Python specific files
	@$(call colorecho, "🐍 Cleaning Python files...")
	@rm -rf __pycache__/ || true
	@find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
	@find . -name "*.pyc" -type f -delete 2>/dev/null || true
	@find . -name "*.pyo" -type f -delete 2>/dev/null || true
	@find . -name "*.pyd" -type f -delete 2>/dev/null || true
	@rm -rf .pytest_cache/ || true
	@rm -rf .coverage || true
	@rm -rf htmlcov/ || true
	@rm -rf .mypy_cache/ || true
	@rm -rf dist/ || true
	@rm -rf build/ || true
	@rm -rf *.egg-info/ || true
	@$(call success, "Python files cleaned")

clean-rust: ## 🧹 Clean Rust specific files
	@$(call colorecho, "🦀 Cleaning Rust files...")
	@if [ -f "Cargo.toml" ]; then \
		cargo clean 2>/dev/null || true; \
	fi
	@rm -rf target/ || true
	@$(call success, "Rust files cleaned")

clean-go: ## 🧹 Clean Go specific files
	@$(call colorecho, "🔷 Cleaning Go files...")
	@if [ -f "go.mod" ]; then \
		go clean -cache 2>/dev/null || true; \
		go clean -modcache 2>/dev/null || true; \
		go clean -testcache 2>/dev/null || true; \
	fi
	@$(call success, "Go files cleaned")

clean-java: ## 🧹 Clean Java specific files
	@$(call colorecho, "☕ Cleaning Java files...")
	@rm -rf target/ || true
	@rm -rf build/ || true
	@find . -name "*.class" -type f -delete 2>/dev/null || true
	@$(call success, "Java files cleaned")

# ================================================================
# IDE 및 에디터 파일 정리
# ================================================================

clean-ide: ## 🧹 Clean IDE and editor files
	@$(call colorecho, "💻 Cleaning IDE files...")
	@rm -rf .vscode/ || true
	@rm -rf .idea/ || true
	@rm -f *.sublime-project || true
	@rm -f *.sublime-workspace || true
	@find . -name ".vscode" -type d -exec rm -rf {} + 2>/dev/null || true
	@find . -name ".idea" -type d -exec rm -rf {} + 2>/dev/null || true
	@$(call success, "IDE files cleaned")

# ================================================================
# 테스트 관련 정리
# ================================================================

clean-test: ## 🧹 Clean test artifacts
	@$(call colorecho, "🧪 Cleaning test artifacts...")
	@rm -rf coverage/ || true
	@rm -rf htmlcov/ || true
	@rm -rf .coverage || true
	@rm -rf .pytest_cache/ || true
	@rm -rf .nyc_output/ || true
	@rm -rf test-results/ || true
	@rm -rf junit.xml || true
	@find . -name "*.cover" -type f -delete 2>/dev/null || true
	@$(call success, "Test artifacts cleaned")

# ================================================================
# 고급 정리 옵션
# ================================================================

clean-recursively: ## 🧹 Clean recursively in all subdirectories
	@$(call colorecho, "🔄 Recursive cleanup in all subdirectories...")
	@find . -type d -name "node_modules" -exec rm -rf {} + 2>/dev/null || true
	@find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	@find . -type d -name ".pytest_cache" -exec rm -rf {} + 2>/dev/null || true
	@find . -type d -name "target" -path "*/target" -exec rm -rf {} + 2>/dev/null || true
	@$(call success, "Recursive cleanup completed")

clean-large-files: ## 🧹 Find and optionally clean large files (>50MB)
	@$(call colorecho, "🔍 Finding large files (>50MB)...")
	@echo "$(BLUE)Large files found:$(RESET)"
	@find . -type f -size +50M -exec ls -lh {} \; 2>/dev/null | \
		awk '{print "  " $$9 " (" $$5 ")"}' || echo "  No large files found"
	@echo ""
	@echo "$(YELLOW)To delete these files, run: find . -type f -size +50M -delete$(RESET)"

clean-old-files: ## 🧹 Find and optionally clean old files (>30 days)
	@$(call colorecho, "🗓️  Finding old files (>30 days)...")
	@echo "$(BLUE)Old files found:$(RESET)"
	@find . -type f -mtime +30 -not -path "./.git/*" -exec ls -lh {} \; 2>/dev/null | \
		awk '{print "  " $$9 " (modified: " $$6 " " $$7 " " $$8 ")"}' | head -20 || \
		echo "  No old files found"
	@echo ""
	@echo "$(YELLOW)To delete these files, run: find . -type f -mtime +30 -not -path './.git/*' -delete$(RESET)"

# ================================================================
# 보안 정리
# ================================================================

clean-secrets: ## 🧹 Clean potential secret files (BE CAREFUL!)
	@$(call warn, "This will remove potential secret files")
	@$(call warn, "Files that will be removed:")
	@find . -name "*.pem" -o -name "*.key" -o -name "*.p12" -o -name "*.pfx" | head -10
	@echo ""
	@echo "Continue? [y/N] " && read ans && [ $${ans:-N} = y ]
	@$(call colorecho, "🔐 Cleaning secret files...")
	@find . -name "*.pem" -type f -delete 2>/dev/null || true
	@find . -name "*.key" -type f -delete 2>/dev/null || true
	@find . -name "*.p12" -type f -delete 2>/dev/null || true
	@find . -name "*.pfx" -type f -delete 2>/dev/null || true
	@$(call success, "Secret files cleaned")

# ================================================================
# 상태 확인 및 보고
# ================================================================

clean-status: ## 🧹 Show cleanup status and disk usage
	@echo "$(BLUE)📊 Cleanup Status Report$(RESET)"
	@echo ""
	@echo "$(YELLOW)Current Directory Size:$(RESET)"
	@du -sh . 2>/dev/null || echo "  Unable to calculate size"
	@echo ""
	@echo "$(YELLOW)Largest Directories:$(RESET)"
	@du -sh */ 2>/dev/null | sort -hr | head -5 | sed 's/^/  /' || echo "  No subdirectories found"
	@echo ""
	@echo "$(YELLOW)File Type Summary:$(RESET)"
	@find . -type f | sed 's/.*\.//' | sort | uniq -c | sort -nr | head -10 | \
		awk '{printf "  %s files: %d\n", $$2, $$1}' || echo "  Unable to analyze files"
	@echo ""
	@echo "$(YELLOW)Cleanup Suggestions:$(RESET)"
	@if [ -d "node_modules" ]; then echo "  📦 Run 'make clean-node' to clean Node.js files"; fi
	@if [ -d "__pycache__" ]; then echo "  🐍 Run 'make clean-python' to clean Python files"; fi
	@if [ -d "target" ]; then echo "  🦀 Run 'make clean-rust' to clean Rust files"; fi
	@if find . -name "*.log" | head -1 | grep -q .; then echo "  📋 Run 'make clean-logs' to clean log files"; fi

# ================================================================
# 자동 정리 (cron job용)
# ================================================================

auto-clean: ## 🧹 Automated cleanup (safe for cron jobs)
	@$(call colorecho, "🤖 Running automated cleanup...")
	@$(MAKE) clean-temp
	@$(MAKE) clean-logs
	@# 오래된 Docker 이미지 정리 (7일 이상)
	@docker image prune -f --filter "until=168h" 2>/dev/null || true
	@# 오래된 컨테이너 정리
	@docker container prune -f 2>/dev/null || true
	@$(call success, "Automated cleanup completed")

# ================================================================
# 정리 도움말
# ================================================================

clean-help: ## 🧹 Show cleanup commands help
	@echo ""
	@echo "$(BLUE)🧹 Cleanup Commands Help$(RESET)"
	@echo ""
	@echo "$(YELLOW)Basic Cleanup:$(RESET)"
	@echo "  $(GREEN)clean$(RESET)                   Safe cleanup (temp files, logs, env)"
	@echo "  $(GREEN)deep-clean$(RESET)              Complete cleanup (DANGEROUS)"
	@echo "  $(GREEN)auto-clean$(RESET)              Automated cleanup (cron-safe)"
	@echo ""
	@echo "$(YELLOW)Specific Cleanup:$(RESET)"
	@echo "  $(GREEN)clean-temp$(RESET)              Clean temporary files"
	@echo "  $(GREEN)clean-logs$(RESET)              Clean log files"
	@echo "  $(GREEN)clean-cache$(RESET)             Clean cache files"
	@echo "  $(GREEN)clean-build$(RESET)             Clean build artifacts"
	@echo "  $(GREEN)env-clean$(RESET)               Clean environment files"
	@echo ""
	@echo "$(YELLOW)Language-specific:$(RESET)"
	@echo "  $(GREEN)clean-node$(RESET)              Clean Node.js files"
	@echo "  $(GREEN)clean-python$(RESET)            Clean Python files"
	@echo "  $(GREEN)clean-rust$(RESET)              Clean Rust files"
	@echo "  $(GREEN)clean-go$(RESET)                Clean Go files"
	@echo "  $(GREEN)clean-java$(RESET)              Clean Java files"
	@echo ""
	@echo "$(YELLOW)Advanced:$(RESET)"
	@echo "  $(GREEN)clean-large-files$(RESET)       Find large files (>50MB)"
	@echo "  $(GREEN)clean-old-files$(RESET)         Find old files (>30 days)"
	@echo "  $(GREEN)clean-recursively$(RESET)       Recursive cleanup"
	@echo "  $(GREEN)clean-status$(RESET)            Show cleanup status report"
	@echo ""
	@echo "$(RED)⚠️  Warning: deep-clean and clean-secrets are destructive!$(RESET)"

# ================================================================
# 커스텀 정리 스크립트 지원
# ================================================================

clean-custom: ## 🧹 Run custom cleanup script (if exists)
	@if [ -f "scripts/custom-clean.sh" ]; then \
		$(call colorecho, "🔧 Running custom cleanup script..."); \
		bash scripts/custom-clean.sh; \
		$(call success, "Custom cleanup completed"); \
	else \
		$(call warn, "No custom cleanup script found at scripts/custom-clean.sh"); \
		echo "Create this file to add project-specific cleanup logic"; \
	fi