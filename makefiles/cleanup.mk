.PHONY: clean env-clean deep-clean safe-clean
.PHONY: clean-temp clean-logs clean-cache clean-build
.PHONY: clean-all-containers clean-all-images clean-all-volumes

DRY_RUN ?=

define SAFE_RM
	if [ "$(DRY_RUN)" = "true" ]; then \
		echo "[Dry run]: Would remove: $(1)"; \
	else \
		rm -rf $(1); \
	fi
endef

clean: ## 🧹 Clean temporary files and safe cleanup
	@$(call colorecho, "🧹 Cleaning temporary files...")
	@$(MAKE) clean-temp
	@$(MAKE) clean-logs
	@$(MAKE) env-clean
	@$(call success, "Basic cleanup completed")

clean-temp: ## 🧹 Clean temporary files
	@$(call colorecho, "🗑️  Cleaning temporary files...")
	@$(call SAFE_RM,.NEW_VERSION.tmp)
	@$(call SAFE_RM,*.tmp)
	@$(call SAFE_RM,.DS_Store)
	@find . -name "*.tmp" -type f -print0 | xargs -0 sh -c 'if [ "$${DRY_RUN:-}" = "true" ]; then echo "[Dry run]: Would remove: $$@"; else rm -rf "$$@"; fi' sh
	@find . -name ".DS_Store" -type f -print0 | xargs -0 sh -c 'if [ "$${DRY_RUN:-}" = "true" ]; then echo "[Dry run]: Would remove: $$@"; else rm -rf "$$@"; fi' sh
	@find . -name "Thumbs.db" -type f -print0 | xargs -0 sh -c 'if [ "$${DRY_RUN:-}" = "true" ]; then echo "[Dry run]: Would remove: $$@"; else rm -rf "$$@"; fi' sh
	@find . -name "*.swp" -type f -print0 | xargs -0 sh -c 'if [ "$${DRY_RUN:-}" = "true" ]; then echo "[Dry run]: Would remove: $$@"; else rm -rf "$$@"; fi' sh
	@find . -name "*.swo" -type f -print0 | xargs -0 sh -c 'if [ "$${DRY_RUN:-}" = "true" ]; then echo "[Dry run]: Would remove: $$@"; else rm -rf "$$@"; fi' sh
	@find . -name "*~" -type f -print0 | xargs -0 sh -c 'if [ "$${DRY_RUN:-}" = "true" ]; then echo "[Dry run]: Would remove: $$@"; else rm -rf "$$@"; fi' sh
	@$(call success, "Temporary files cleaned")

clean-logs: ## 🧹 Clean log files
	@$(call colorecho, "📋 Cleaning log files...")
	@$(call SAFE_RM,logs/)
	@$(call SAFE_RM,*.log)
	@find . -name "*.log" -type f -print0 | xargs -0 sh -c 'if [ "$${DRY_RUN:-}" = "true" ]; then echo "[Dry run]: Would remove: $$@"; else rm -rf "$$@"; fi' sh
	@find . -name "*.log.*" -type f -print0 | xargs -0 sh -c 'if [ "$${DRY_RUN:-}" = "true" ]; then echo "[Dry run]: Would remove: $$@"; else rm -rf "$$@"; fi' sh
	@$(call success, "Log files cleaned")

clean-cache: ## 🧹 Clean cache files and directories
	@$(call colorecho, "💾 Cleaning cache files...")
	@$(call SAFE_RM,.cache/)
	@$(call SAFE_RM,__pycache__/)
	@find . -name "__pycache__" -type d -print0 | xargs -0 sh -c 'if [ "$${DRY_RUN:-}" = "true" ]; then echo "[Dry run]: Would remove: $$@"; else rm -rf "$$@"; fi' sh
	@find . -name "*.pyc" -type f -print0 | xargs -0 sh -c 'if [ "$${DRY_RUN:-}" = "true" ]; then echo "[Dry run]: Would remove: $$@"; else rm -rf "$$@"; fi' sh
	@find . -name "*.pyo" -type f -print0 | xargs -0 sh -c 'if [ "$${DRY_RUN:-}" = "true" ]; then echo "[Dry run]: Would remove: $$@"; else rm -rf "$$@"; fi' sh
	@$(call SAFE_RM,node_modules/.cache/)
	@$(call SAFE_RM,.npm/)
	@$(call SAFE_RM,.yarn/cache/)
	@$(call SAFE_RM,target/debug/)
	@$(call SAFE_RM,target/release/)
	@$(call success, "Cache files cleaned")

clean-build: ## 🧹 Clean build artifacts
	@$(call colorecho, "🔨 Cleaning build artifacts...")
	@$(call SAFE_RM,build/)
	@$(call SAFE_RM,dist/)
	@$(call SAFE_RM,out/)
	@$(call SAFE_RM,target/)
	@$(call SAFE_RM,.build/)
	@find . -name "*.o" -type f -print0 | xargs -0 sh -c 'if [ "$${DRY_RUN:-}" = "true" ]; then echo "[Dry run]: Would remove: $$@"; else rm -rf "$$@"; fi' sh
	@find . -name "*.so" -type f -print0 | xargs -0 sh -c 'if [ "$${DRY_RUN:-}" = "true" ]; then echo "[Dry run]: Would remove: $$@"; else rm -rf "$$@"; fi' sh
	@find . -name "*.dylib" -type f -print0 | xargs -0 sh -c 'if [ "$${DRY_RUN:-}" = "true" ]; then echo "[Dry run]: Would remove: $$@"; else rm -rf "$$@"; fi' sh
	@find . -name "*.dll" -type f -print0 | xargs -0 sh -c 'if [ "$${DRY_RUN:-}" = "true" ]; then echo "[Dry run]: Would remove: $$@"; else rm -rf "$$@"; fi' sh
	@$(call success, "Build artifacts cleaned")

env-clean: ## 🧹 Clean environment files
	@$(call colorecho, "🌍 Cleaning environment files...")
	@$(call SAFE_RM,.env)
	@$(call SAFE_RM,.env.local)
	@$(call SAFE_RM,.env.*.local)
	@find . -name ".env.*.local" -type f -print0 | xargs -0 sh -c 'if [ "$${DRY_RUN:-}" = "true" ]; then echo "[Dry run]: Would remove: $$@"; else rm -rf "$$@"; fi' sh
	@$(call success, "Environment files cleaned")

clean-node: ## 🧹 Clean Node.js specific files
	@$(call colorecho, "📦 Cleaning Node.js files...")
	@$(call SAFE_RM,node_modules/)
	@$(call SAFE_RM,package-lock.json)
	@$(call SAFE_RM,yarn.lock)
	@$(call SAFE_RM,.yarn/install-state.gz)
	@$(call SAFE_RM,.yarn/cache/)
	@$(call SAFE_RM,.npm/)
	@$(call success, "Node.js files cleaned")

clean-python: ## 🧹 Clean Python specific files
	@$(call colorecho, "🐍 Cleaning Python files...")
	@$(call SAFE_RM,__pycache__/)
	@find . -name "__pycache__" -type d -print0 | xargs -0 sh -c 'if [ "$${DRY_RUN:-}" = "true" ]; then echo "[Dry run]: Would remove: $$@"; else rm -rf "$$@"; fi' sh
	@find . -name "*.pyc" -type f -print0 | xargs -0 sh -c 'if [ "$${DRY_RUN:-}" = "true" ]; then echo "[Dry run]: Would remove: $$@"; else rm -rf "$$@"; fi' sh
	@find . -name "*.pyo" -type f -print0 | xargs -0 sh -c 'if [ "$${DRY_RUN:-}" = "true" ]; then echo "[Dry run]: Would remove: $$@"; else rm -rf "$$@"; fi' sh
	@find . -name "*.pyd" -type f -print0 | xargs -0 sh -c 'if [ "$${DRY_RUN:-}" = "true" ]; then echo "[Dry run]: Would remove: $$@"; else rm -rf "$$@"; fi' sh
	@$(call SAFE_RM,.pytest_cache/)
	@$(call SAFE_RM,.coverage)
	@$(call SAFE_RM,htmlcov/)
	@$(call SAFE_RM,.mypy_cache/)
	@$(call SAFE_RM,dist/)
	@$(call SAFE_RM,build/)
	@$(call SAFE_RM,*.egg-info/)
	@$(call success, "Python files cleaned")

clean-java: ## ☕ Cleaning Java specific files
	@$(call colorecho, "☕ Cleaning Java files...")
	@$(call SAFE_RM,target/)
	@$(call SAFE_RM,build/)
	@find . -name "*.class" -type f -print0 | xargs -0 sh -c 'if [ "$${DRY_RUN:-}" = "true" ]; then echo "[Dry run]: Would remove: $$@"; else rm -rf "$$@"; fi' sh
	@$(call success, "Java files cleaned")

clean-ide: ## 🧹 Clean IDE and editor files
	@$(call colorecho, "💻 Cleaning IDE files...")
	@$(call SAFE_RM,.vscode/)
	@$(call SAFE_RM,.idea/)
	@$(call SAFE_RM,*.sublime-project)
	@$(call SAFE_RM,*.sublime-workspace)
	@find . -name ".vscode" -type d -print0 | xargs -0 sh -c 'if [ "$${DRY_RUN:-}" = "true" ]; then echo "[Dry run]: Would remove: $$@"; else rm -rf "$$@"; fi' sh
	@find . -name ".idea" -type d -print0 | xargs -0 sh -c 'if [ "$${DRY_RUN:-}" = "true" ]; then echo "[Dry run]: Would remove: $$@"; else rm -rf "$$@"; fi' sh
	@$(call success, "IDE files cleaned")

clean-test: ## 🧹 Clean test artifacts
	@$(call colorecho, "🧪 Cleaning test artifacts...")
	@$(call SAFE_RM,coverage/)
	@$(call SAFE_RM,htmlcov/)
	@$(call SAFE_RM,.coverage)
	@$(call SAFE_RM,.pytest_cache/)
	@$(call SAFE_RM,.nyc_output/)
	@$(call SAFE_RM,test-results/)
	@$(call SAFE_RM,junit.xml)
	@find . -name "*.cover" -type f -print0 | xargs -0 sh -c 'if [ "$${DRY_RUN:-}" = "true" ]; then echo "[Dry run]: Would remove: $$@"; else rm -rf "$$@"; fi' sh
	@$(call success, "Test artifacts cleaned")

clean-recursively: ## 🧹 Clean recursively in all subdirectories
	@$(call colorecho, "🔄 Recursive cleanup in all subdirectories...")
	@find . -type d -name "node_modules" -print0 | xargs -0 sh -c 'if [ "$${DRY_RUN:-}" = "true" ]; then echo "[Dry run]: Would remove: $$@"; else rm -rf "$$@"; fi' sh
	@find . -type d -name "__pycache__" -print0 | xargs -0 sh -c 'if [ "$${DRY_RUN:-}" = "true" ]; then echo "[Dry run]: Would remove: $$@"; else rm -rf "$$@"; fi' sh
	@find . -type d -name ".pytest_cache" -print0 | xargs -0 sh -c 'if [ "$${DRY_RUN:-}" = "true" ]; then echo "[Dry run]: Would remove: $$@"; else rm -rf "$$@"; fi' sh
	@find . -type d -name "target" -path "*/target" -print0 | xargs -0 sh -c 'if [ "$${DRY_RUN:-}" = "true" ]; then echo "[Dry run]: Would remove: $$@"; else rm -rf "$$@"; fi' sh
	@$(call success, "Recursive cleanup completed")

clean-secrets: ## 🧹 Clean potential secret files (BE CAREFUL!)
	@$(call warn, "This will remove potential secret files")
	@$(call warn, "Files that will be removed:")
	@find . -name "*.pem" -o -name "*.key" -o -name "*.p12" -o -name "*.pfx" | head -10
	@echo ""
	@echo "Continue? [y/N] " && read ans && [ $${ans:-N} = y ]
	@$(call colorecho, "🔐 Cleaning secret files...")
	@find . -name "*.pem" -type f -print0 | xargs -0 sh -c 'if [ "$${DRY_RUN:-}" = "true" ]; then echo "[Dry run]: Would remove: $$@"; else rm -rf "$$@"; fi' sh
	@find . -name "*.key" -type f -print0 | xargs -0 sh -c 'if [ "$${DRY_RUN:-}" = "true" ]; then echo "[Dry run]: Would remove: $$@"; else rm -rf "$$@"; fi' sh
	@find . -name "*.p12" -type f -print0 | xargs -0 sh -c 'if [ "$${DRY_RUN:-}" = "true" ]; then echo "[Dry run]: Would remove: $$@"; else rm -rf "$$@"; fi' sh
	@find . -name "*.pfx" -type f -print0 | xargs -0 sh -c 'if [ "$${DRY_RUN:-}" = "true" ]; then echo "[Dry run]: Would remove: $$@"; else rm -rf "$$@"; fi' sh
	@$(call success, "Secret files cleaned")
