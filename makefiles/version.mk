# ================================================================
# Version Management System
# ================================================================

.PHONY: version update-version uv show-version version-info
.PHONY: version-tag version-changelog version-release-notes

# 버전 업데이트 도구 설정 (project.mk에서 오버라이드 가능)
VERSION_UPDATE_TOOL ?= auto-detect
VERSION_FILE ?= package.json

# ================================================================
# 기본 버전 관리 타겟들
# ================================================================

version: ## 🔧 Show current version
	@echo "$(BLUE)Version Information:$(RESET)"
	@echo "  Project Version: $(VERSION)"
	@echo "  Tag Name: $(TAGNAME)"
	@echo "  Current Branch: $(CURRENT_BRANCH)"
	@echo "  Last Git Tag: $$(git describe --tags --abbrev=0 2>/dev/null || echo 'none')"
	@echo "  Git Commit: $$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"

show-version: version ## 🔧 Alias for version command

uv: update-version ## 🔧 Update version (shortcut)

update-version: ## 🔧 Update version using appropriate tool
	@$(call colorecho, "🔄 Updating version...")
	@$(MAKE) _detect_and_update_version
	@$(call success, "Version updated successfully")

# ================================================================
# 버전 업데이트 도구 자동 감지 및 실행
# ================================================================

_detect_and_update_version:
	@if [ "$(VERSION_UPDATE_TOOL)" = "auto-detect" ]; then \
		$(MAKE) _auto_detect_version_tool; \
	else \
		$(MAKE) _update_version_with_tool TOOL=$(VERSION_UPDATE_TOOL); \
	fi

_auto_detect_version_tool:
	@$(call colorecho, "🔍 Detecting version update tool...")
	@if [ -f "package.json" ] && command -v yarn >/dev/null 2>&1; then \
		$(call colorecho, "📦 Detected: Yarn + package.json"); \
		$(MAKE) _update_version_with_tool TOOL=yarn; \
	elif [ -f "package.json" ] && command -v npm >/dev/null 2>&1; then \
		$(call colorecho, "📦 Detected: NPM + package.json"); \
		$(MAKE) _update_version_with_tool TOOL=npm; \
	elif [ -f "pyproject.toml" ] && command -v poetry >/dev/null 2>&1; then \
		$(call colorecho, "🐍 Detected: Poetry + pyproject.toml"); \
		$(MAKE) _update_version_with_tool TOOL=poetry; \
	elif [ -f "setup.py" ] && command -v python >/dev/null 2>&1; then \
		$(call colorecho, "🐍 Detected: Python + setup.py"); \
		$(MAKE) _update_version_with_tool TOOL=python; \
	elif [ -f "go.mod" ] && command -v go >/dev/null 2>&1; then \
		$(call colorecho, "🔷 Detected: Go + go.mod"); \
		$(MAKE) _update_version_with_tool TOOL=go; \
	elif [ -f "Cargo.toml" ] && command -v cargo >/dev/null 2>&1; then \
		$(call colorecho, "🦀 Detected: Rust + Cargo.toml"); \
		$(MAKE) _update_version_with_tool TOOL=cargo; \
	else \
		$(call colorecho, "⚙️  No specific tool detected, using generic approach"); \
		$(MAKE) _update_version_with_tool TOOL=generic; \
	fi

_update_version_with_tool:
	@case "$(TOOL)" in \
		yarn) \
			$(call colorecho, "📦 Updating version with Yarn..."); \
			yarn version --patch --no-git-tag-version; \
			;; \
		npm) \
			$(call colorecho, "📦 Updating version with NPM..."); \
			npm version patch --no-git-tag-version; \
			;; \
		poetry) \
			$(call colorecho, "🐍 Updating version with Poetry..."); \
			poetry version patch; \
			;; \
		python) \
			$(call colorecho, "🐍 Updating Python version..."); \
			python setup.py --version; \
			;; \
		go) \
			$(call colorecho, "🔷 Go version management..."); \
			echo "Go versions are typically managed through git tags"; \
			;; \
		cargo) \
			$(call colorecho, "🦀 Updating Cargo version..."); \
			cargo bump patch; \
			;; \
		generic) \
			$(call colorecho, "⚙️  Generic version update..."); \
			echo "Please manually update your version file"; \
			;; \
		*) \
			$(call error, "Unknown version tool: $(TOOL)"); \
			exit 1; \
			;; \
	esac

# ================================================================
# 버전 파일 관리
# ================================================================

update-version-file: ## 🔧 Update version in specific file
	@if [ -z "$(NEW_VERSION)" ]; then \
		$(call error, "NEW_VERSION is required. Usage: make update-version-file NEW_VERSION=v1.2.3"); \
		exit 1; \
	fi; \
	$(call colorecho, "📝 Updating version to $(NEW_VERSION) in $(VERSION_FILE)..."); \
	case "$(VERSION_FILE)" in \
		package.json) \
			$(SED) 's/"version": "[^"]*"/"version": "$(NEW_VERSION:v%=%)"/' $(VERSION_FILE); \
			;; \
		pyproject.toml) \
			$(SED) 's/version = "[^"]*"/version = "$(NEW_VERSION:v%=%)"/' $(VERSION_FILE); \
			;; \
		Cargo.toml) \
			$(SED) 's/version = "[^"]*"/version = "$(NEW_VERSION:v%=%)"/' $(VERSION_FILE); \
			;; \
		VERSION) \
			echo "$(NEW_VERSION)" > $(VERSION_FILE); \
			;; \
		*) \
			$(call warn, "Unknown version file format: $(VERSION_FILE)"); \
			echo "Please update $(VERSION_FILE) manually to $(NEW_VERSION)"; \
			;; \
	esac; \
	$(call success, "Version file updated")

# ================================================================
# 버전 태깅
# ================================================================

version-tag: ## 🔧 Create version tag without release
	@if [ -z "$(TAG_VERSION)" ]; then \
		TAG_VERSION=$(VERSION); \
	fi; \
	$(call colorecho, "🏷️  Creating version tag: $$TAG_VERSION"); \
	if git tag -l | grep -q "^$$TAG_VERSION$$"; then \
		$(call warn, "Tag $$TAG_VERSION already exists"); \
	else \
		git tag -a $$TAG_VERSION -m "Version $$TAG_VERSION"; \
		$(call success, "Tag $$TAG_VERSION created"); \
	fi

push-tags: ## 🔧 Push all tags to remote
	@$(call colorecho, "📤 Pushing tags to remote...")
	@git push --tags
	@$(call success, "Tags pushed successfully")

delete-tag: ## 🔧 Delete version tag (usage: make delete-tag TAG=v1.0.0)
	@if [ -z "$(TAG)" ]; then \
		$(call error, "TAG is required. Usage: make delete-tag TAG=v1.0.0"); \
		exit 1; \
	fi; \
	$(call colorecho, "🗑️  Deleting tag: $(TAG)"); \
	git tag -d $(TAG); \
	git push origin :refs/tags/$(TAG); \
	$(call success, "Tag $(TAG) deleted")

# ================================================================
# 버전 히스토리 및 변경사항
# ================================================================

version-changelog: ## 🔧 Generate changelog since last version
	@$(call colorecho, "📋 Generating changelog...")
	@LAST_TAG=$$(git describe --tags --abbrev=0 2>/dev/null || echo ""); \
	if [ -n "$$LAST_TAG" ]; then \
		echo "$(BLUE)Changes since $$LAST_TAG:$(RESET)"; \
		git log --pretty=format:"- %s (%h) by %an" $$LAST_TAG..HEAD; \
	else \
		echo "$(BLUE)All commits (no previous tags):$(RESET)"; \
		git log --pretty=format:"- %s (%h) by %an"; \
	fi; \
	echo ""

version-release-notes: ## 🔧 Generate release notes for current version
	@$(call colorecho, "📝 Generating release notes...")
	@CURRENT_TAG=$(VERSION); \
	LAST_TAG=$$(git tag --sort=-version:refname | grep -v "$$CURRENT_TAG" | head -1); \
	echo "# Release Notes for $$CURRENT_TAG"; \
	echo ""; \
	if [ -n "$$LAST_TAG" ]; then \
		echo "## Changes since $$LAST_TAG"; \
		echo ""; \
		git log --pretty=format:"- %s (%h)" $$LAST_TAG..HEAD; \
	else \
		echo "## Initial Release"; \
		echo ""; \
		git log --pretty=format:"- %s (%h)"; \
	fi; \
	echo ""; \
	echo ""; \
	echo "**Full Changelog**: $$(git remote get-url origin)/compare/$$LAST_TAG...$$CURRENT_TAG" 2>/dev/null || true

# ================================================================
# 버전 비교 및 검증
# ================================================================

version-compare: ## 🔧 Compare current version with remote tags
	@$(call colorecho, "🔍 Comparing versions...")
	@echo "$(BLUE)Local Version: $(VERSION)$(RESET)"
	@echo "$(BLUE)Local Tags:$(RESET)"
	@git tag --sort=-version:refname | head -5 | sed 's/^/  /'
	@echo ""
	@echo "$(BLUE)Remote Tags (latest 5):$(RESET)"
	@git ls-remote --tags origin | grep -v '\^{}' | \
		awk '{print $$2}' | sed 's|refs/tags/||' | sort -V -r | head -5 | sed 's/^/  /' || \
		echo "  Unable to fetch remote tags"

version-next: ## 🔧 Show what the next version would be
	@$(call colorecho, "🔮 Calculating next versions...")
	@CURRENT=$$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0"); \
	CURRENT_NUM=$$(echo $$CURRENT | sed 's/v//'); \
	MAJOR=$$(echo $$CURRENT_NUM | cut -d. -f1); \
	MINOR=$$(echo $$CURRENT_NUM | cut -d. -f2); \
	PATCH=$$(echo $$CURRENT_NUM | cut -d. -f3); \
	echo "$(BLUE)Current Version: $$CURRENT$(RESET)"; \
	echo "$(BLUE)Next Versions:$(RESET)"; \
	echo "  Patch: v$$MAJOR.$$MINOR.$$((PATCH + 1))"; \
	echo "  Minor: v$$MAJOR.$$((MINOR + 1)).0"; \
	echo "  Major: v$$((MAJOR + 1)).0.0"

# ================================================================
# 시맨틱 버전 관리
# ================================================================

version-patch: ## 🔧 Bump patch version and create tag
	@$(MAKE) bump-version
	@NEW_VERSION=$$(cat .NEW_VERSION.tmp); \
	$(MAKE) update-version-file NEW_VERSION=$$NEW_VERSION; \
	$(MAKE) version-tag TAG_VERSION=$$NEW_VERSION; \
	$(call success, "Patch version bumped to $$NEW_VERSION")

version-minor: ## 🔧 Bump minor version and create tag
	@$(MAKE) bump-minor
	@NEW_VERSION=$$(cat .NEW_VERSION.tmp); \
	$(MAKE) update-version-file NEW_VERSION=$$NEW_VERSION; \
	$(MAKE) version-tag TAG_VERSION=$$NEW_VERSION; \
	$(call success, "Minor version bumped to $$NEW_VERSION")

version-major: ## 🔧 Bump major version and create tag
	@$(MAKE) bump-major
	@NEW_VERSION=$$(cat .NEW_VERSION.tmp); \
	$(MAKE) update-version-file NEW_VERSION=$$NEW_VERSION; \
	$(MAKE) version-tag TAG_VERSION=$$NEW_VERSION; \
	$(call success, "Major version bumped to $$NEW_VERSION")

# ================================================================
# 버전 검증
# ================================================================

validate-version: ## 🔧 Validate version format
	@$(call colorecho, "✅ Validating version format...")
	@if echo "$(VERSION)" | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.-]+)?$$' >/dev/null; then \
		$(call success, "Version format is valid: $(VERSION)"); \
	else \
		$(call error, "Invalid version format: $(VERSION)"); \
		echo "Expected format: v1.2.3 or v1.2.3-alpha.1"; \
		exit 1; \
	fi

check-version-consistency: ## 🔧 Check version consistency across files
	@$(call colorecho, "🔍 Checking version consistency...")
	@INCONSISTENT=false; \
	if [ -f "package.json" ]; then \
		PKG_VERSION=$$(grep '"version"' package.json | sed 's/.*"version": "\([^"]*\)".*/\1/'); \
		if [ "$(VERSION:v%=%)" != "$$PKG_VERSION" ]; then \
			$(call warn, "Version mismatch in package.json: $$PKG_VERSION vs $(VERSION)"); \
			INCONSISTENT=true; \
		fi; \
	fi; \
	if [ -f "pyproject.toml" ]; then \
		TOML_VERSION=$$(grep '^version =' pyproject.toml | sed 's/version = "\([^"]*\)"/\1/'); \
		if [ "$(VERSION:v%=%)" != "$$TOML_VERSION" ]; then \
			$(call warn, "Version mismatch in pyproject.toml: $$TOML_VERSION vs $(VERSION)"); \
			INCONSISTENT=true; \
		fi; \
	fi; \
	if [ "$$INCONSISTENT" = "true" ]; then \
		$(call error, "Version inconsistencies found"); \
		exit 1; \
	else \
		$(call success, "All versions are consistent"); \
	fi

# ================================================================
# 버전 정보 내보내기
# ================================================================

export-version-info: ## 🔧 Export version information to file
	@$(call colorecho, "📤 Exporting version information...")
	@echo '{' > version-info.json
	@echo '  "version": "$(VERSION)",' >> version-info.json
	@echo '  "tagname": "$(TAGNAME)",' >> version-info.json
	@echo '  "branch": "$(CURRENT_BRANCH)",' >> version-info.json
	@echo '  "commit": "'$$(git rev-parse HEAD 2>/dev/null || echo 'unknown')'",' >> version-info.json
	@echo '  "shortCommit": "'$$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')'",' >> version-info.json
	@echo '  "lastTag": "'$$(git describe --tags --abbrev=0 2>/dev/null || echo 'none')'",' >> version-info.json
	@echo '  "buildDate": "'$$(date -u +%Y-%m-%dT%H:%M:%SZ)'",' >> version-info.json
	@echo '  "project": "$(NAME)",' >> version-info.json
	@echo '  "repository": "$(REPO_HUB)/$(NAME)"' >> version-info.json
	@echo '}' >> version-info.json
	@$(call success, "Version info exported to version-info.json")


# ================================================================
# 개발자 도구
# ================================================================

version-help: ## 🔧 Show version management help
	@echo ""
	@echo "$(BLUE)🏷️  Version Management Help$(RESET)"
	@echo ""
	@echo "$(YELLOW)Basic Commands:$(RESET)"
	@echo "  $(GREEN)version$(RESET)                  Show current version info"
	@echo "  $(GREEN)update-version$(RESET)           Update version using detected tool"
	@echo "  $(GREEN)version-next$(RESET)             Show next possible versions"
	@echo ""
	@echo "$(YELLOW)Semantic Versioning:$(RESET)"
	@echo "  $(GREEN)version-patch$(RESET)            Bump patch version (1.0.0 -> 1.0.1)"
	@echo "  $(GREEN)version-minor$(RESET)            Bump minor version (1.0.0 -> 1.1.0)"
	@echo "  $(GREEN)version-major$(RESET)            Bump major version (1.0.0 -> 2.0.0)"
	@echo ""
	@echo "$(YELLOW)Tagging:$(RESET)"
	@echo "  $(GREEN)version-tag$(RESET)              Create version tag"
	@echo "  $(GREEN)push-tags$(RESET)               Push tags to remote"
	@echo "  $(GREEN)delete-tag TAG=v1.0.0$(RESET)   Delete specific tag"
	@echo ""
	@echo "$(YELLOW)Documentation:$(RESET)"
	@echo "  $(GREEN)version-changelog$(RESET)        Generate changelog"
	@echo "  $(GREEN)version-release-notes$(RESET)    Generate release notes"
	@echo "  $(GREEN)export-version-info$(RESET)      Export version to JSON"
	@echo ""
	@echo "$(YELLOW)Validation:$(RESET)"
	@echo "  $(GREEN)validate-version$(RESET)         Check version format"
	@echo "  $(GREEN)check-version-consistency$(RESET) Check consistency across files"
