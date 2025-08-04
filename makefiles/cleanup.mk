.PHONY: clean env-clean deep-clean safe-clean
.PHONY: clean-temp clean-logs clean-cache clean-build
.PHONY: clean-all-containers clean-all-images clean-all-volumes

safe_rm = \
	@if [ "$(DRY_RUN)" = "true" ]; then \
		echo "[Dry run]: Would remove the following files:"; \
		echo "$$@"; \
	else \
		rm -rf "$$@"; \
	fi

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
	@$(safe_rm) .NEW_VERSION.tmp
	@$(safe_rm) *.tmp
	@$(safe_rm) .DS_Store
	@find . -name "*.tmp" -type f -print0 | xargs -0 $(safe_rm)
	@find . -name ".DS_Store" -type f -print0 | xargs -0 $(safe_rm)
	@find . -name "Thumbs.db" -type f -print0 | xargs -0 $(safe_rm)
	@find . -name "*.swp" -type f -print0 | xargs -0 $(safe_rm)
	@find . -name "*.swo" -type f -print0 | xargs -0 $(safe_rm)
	@find . -name "*~" -type f -print0 | xargs -0 $(safe_rm)
	@$(call success, "Temporary files cleaned")

clean-logs: ## 🧹 Clean log files
	@$(call colorecho, "📋 Cleaning log files...")
	@$(safe_rm) logs/
	@$(safe_rm) *.log
	@find . -name "*.log" -type f -print0 | xargs -0 $(safe_rm)
	@find . -name "*.log.*" -type f -print0 | xargs -0 $(safe_rm)
	@$(call success, "Log files cleaned")

clean-cache: ## 🧹 Clean cache files and directories
	@$(call colorecho, "💾 Cleaning cache files...")
	@$(safe_rm) .cache/
	@$(safe_rm) __pycache__/
	@find . -name "__pycache__" -type d -print0 | xargs -0 $(safe_rm)
	@find . -name "*.pyc" -type f -print0 | xargs -0 $(safe_rm)
	@find . -name "*.pyo" -type f -print0 | xargs -0 $(safe_rm)
	@$(safe_rm) node_modules/.cache/
	@$(safe_rm) .npm/
	@$(safe_rm) .yarn/cache/
	@$(safe_rm) target/debug/
	@$(safe_rm) target/release/
	@$(call success, "Cache files cleaned")

clean-build: ## 🧹 Clean build artifacts
	@$(call colorecho, "🔨 Cleaning build artifacts...")
	@$(safe_rm) build/
	@$(safe_rm) dist/
	@$(safe_rm) out/
	@$(safe_rm) target/
	@$(safe_rm) .build/
	@find . -name "*.o" -type f -print0 | xargs -0 $(safe_rm)
	@find . -name "*.so" -type f -print0 | xargs -0 $(safe_rm)
	@find . -name "*.dylib" -type f -print0 | xargs -0 $(safe_rm)
	@find . -name "*.dll" -type f -print0 | xargs -0 $(safe_rm)
	@$(call success, "Build artifacts cleaned")

# ================================================================
# 환경 파일 정리
# ================================================================

env-clean: ## 🧹 Clean environment files
	@$(call colorecho, "🌍 Cleaning environment files...")
	@$(safe_rm) .env
	@$(safe_rm) .env.local
	@$(safe_rm) .env.*.local
	@find . -name ".env.*.local" -type f -print0 | xargs -0 $(safe_rm)
	@$(call success, "Environment files cleaned")

# ================================================================
# 언어별 정리
# ================================================================

clean-node: ## 🧹 Clean Node.js specific files
	@$(call colorecho, "📦 Cleaning Node.js files...")
	@$(safe_rm) node_modules/
	@$(safe_rm) package-lock.json
	@$(safe_rm) yarn.lock
	@$(safe_rm) .yarn/install-state.gz
	@$(safe_rm) .yarn/cache/
	@$(safe_rm) .npm/
	@$(call success, "Node.js files cleaned")

clean-python: ## 🧹 Clean Python specific files
	@$(call colorecho, "🐍 Cleaning Python files...")
	@$(safe_rm) __pycache__/
	@find . -name "__pycache__" -type d -print0 | xargs -0 $(safe_rm)
	@find . -name "*.pyc" -type f -print0 | xargs -0 $(safe_rm)
	@find . -name "*.pyo" -type f -print0 | xargs -0 $(safe_rm)
	@find . -name "*.pyd" -type f -print0 | xargs -0 $(safe_rm)
	@$(safe_rm) .pytest_cache/
	@$(safe_rm) .coverage
	@$(safe_rm) htmlcov/
	@$(safe_rm) .mypy_cache/
	@$(safe_rm) dist/
	@$(safe_rm) build/
	@$(safe_rm) *.egg-info/
	@$(call success, "Python files cleaned")

clean-rust: ## 🧹 Clean Rust specific files
	@$(call colorecho, "🦀 Cleaning Rust files...")
	@if [ -f "Cargo.toml" ]; then \
		cargo clean 2>/dev/null || true; \
	fi
	@$(safe_rm) target/
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
	@$(safe_rm) target/
	@$(safe_rm) build/
	@find . -name "*.class" -type f -print0 | xargs -0 $(safe_rm)
	@$(call success, "Java files cleaned")

# ================================================================
# IDE 및 에디터 파일 정리
# ================================================================

clean-ide: ## 🧹 Clean IDE and editor files
	@$(call colorecho, "💻 Cleaning IDE files...")
	@$(safe_rm) .vscode/
	@$(safe_rm) .idea/
	@$(safe_rm) *.sublime-project
	@$(safe_rm) *.sublime-workspace
	@find . -name ".vscode" -type d -print0 | xargs -0 $(safe_rm)
	@find . -name ".idea" -type d -print0 | xargs -0 $(safe_rm)
	@$(call success, "IDE files cleaned")

# ================================================================
# 테스트 관련 정리
# ================================================================

clean-test: ## 🧹 Clean test artifacts
	@$(call colorecho, "🧪 Cleaning test artifacts...")
	@$(safe_rm) coverage/
	@$(safe_rm) htmlcov/
	@$(safe_rm) .coverage
	@$(safe_rm) .pytest_cache/
	@$(safe_rm) .nyc_output/
	@$(safe_rm) test-results/
	@$(safe_rm) junit.xml
	@find . -name "*.cover" -type f -print0 | xargs -0 $(safe_rm)
	@$(call success, "Test artifacts cleaned")

# ================================================================
# 고급 정리 옵션
# ================================================================

clean-recursively: ## 🧹 Clean recursively in all subdirectories
	@$(call colorecho, "🔄 Recursive cleanup in all subdirectories...")
	@find . -type d -name "node_modules" -print0 | xargs -0 $(safe_rm)
	@find . -type d -name "__pycache__" -print0 | xargs -0 $(safe_rm)
	@find . -type d -name ".pytest_cache" -print0 | xargs -0 $(safe_rm)
	@find . -type d -name "target" -path "*/target" -print0 | xargs -0 $(safe_rm)
	@$(call success, "Recursive cleanup completed")

clean-large-files: ## 🧹 Find and optionally clean large files (>50MB)
	@$(call colorecho, "🔍 Finding large files (>50MB)...")
	@echo "$(BLUE)Large files found:$(RESET)"
	@find . -type f -size +50M -exec ls -lh {} \; 2>/dev/null | \
		awk '{print "  " $$9 " (" $$5 ")"}' || echo "  No large files found"
	@echo ""
	@echo "$(YELLOW)To delete these files, run: find . -type f -size +50M -print0 | xargs -0 $(safe_rm)$(RESET)"

clean-old-files: ## 🧹 Find and optionally clean old files (>30 days)
	@$(call colorecho, "🗓️  Finding old files (>30 days)...")
	@echo "$(BLUE)Old files found:$(RESET)"
	@find . -type f -mtime +30 -not -path "./.git/*" -exec ls -lh {} \; 2>/dev/null | \
		awk '{print "  " $$9 " (modified: " $$6 " " $$7 " " $$8 ")"}' | head -20 || \
		echo "  No old files found"
	@echo ""
	@echo "$(YELLOW)To delete these files, run: find . -type f -mtime +30 -not -path './.git/*' -print0 | xargs -0 $(safe_rm)$(RESET)"

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
	@find . -name "*.pem" -type f -print0 | xargs -0 $(safe_rm)
	@find . -name "*.key" -type f -print0 | xargs -0 $(safe_rm)
	@find . -name "*.p12" -type f -print0 | xargs -0 $(safe_rm)
	@find . -name "*.pfx" -type f -print0 | xargs -0 $(safe_rm)
	@$(call success, "Secret files cleaned")
