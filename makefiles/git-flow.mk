include $(MAKEFILE_DIR)/makefiles/colors.mk
# ================================================================
# Git Flow and Release Management
# ================================================================

.PHONY: git-status sync-develop start-release list-old-branches clean-old-branches
.PHONY: bump-version create-release-branch push-release-branch finish-release auto-release

# ================================================================
# 버전 관리 로직
# ================================================================

# 버전 자동 증가 로직
define BUMP_VERSION_LOGIC
git fetch --tags; \
LATEST_TAG=$$(git describe --tags `git rev-list --tags --max-count=1` 2>/dev/null || echo "v0.0.0"); \
VERSION_NUM=$$(echo $$LATEST_TAG | sed 's/v//'); \
MAJOR=$$(echo $$VERSION_NUM | cut -d. -f1); \
MINOR=$$(echo $$VERSION_NUM | cut -d. -f2); \
PATCH=$$(echo $$VERSION_NUM | cut -d. -f3); \
NEW_PATCH=$$(($$PATCH + 1)); \
NEW_VERSION="v$$MAJOR.$$MINOR.$$NEW_PATCH"
endef

# ================================================================
# Git 상태 확인
# ================================================================

git-status: ## 🌿 Show comprehensive git status
	@echo "$(BLUE)Git Repository Status:$(RESET)"
	@echo "  Current Branch: $(CURRENT_BRANCH)"
	@echo "  Main Branch: $(MAIN_BRANCH)"
	@echo "  Develop Branch: $(DEVELOP_BRANCH)"
	@echo ""
	@echo "$(BLUE)Working Directory:$(RESET)"
	@git status --short || echo "  Clean"
	@echo ""
	@echo "$(BLUE)Recent Tags:$(RESET)"
	@git tag --sort=-version:refname | head -5 || echo "  No tags found"
	@echo ""
	@echo "$(BLUE)Branch Tracking:$(RESET)"
	@git branch -vv | grep "^\*" || echo "  Not tracking any remote"

git-branches: ## 🌿 Show all branches with status
	@echo "$(BLUE)Local Branches:$(RESET)"
	@git branch -v
	@echo ""
	@echo "$(BLUE)Remote Branches:$(RESET)"
	@git branch -rv

# ================================================================
# 브랜치 관리
# ================================================================

sync-develop: ## 🌿 Sync current branch to develop branch
ifeq ($(CURRENT_BRANCH),$(DEVELOP_BRANCH))
	@$(call colorecho, "Already on '$(DEVELOP_BRANCH)' branch. Nothing to do.")
else
	@$(call colorecho, "Switching to '$(DEVELOP_BRANCH)' and merging '$(CURRENT_BRANCH)'...")
	@git checkout $(DEVELOP_BRANCH)
	@git pull origin $(DEVELOP_BRANCH)
	@git merge --no-ff $(CURRENT_BRANCH)
	@git push origin $(DEVELOP_BRANCH)
	@$(call success, "Successfully merged '$(CURRENT_BRANCH)' into '$(DEVELOP_BRANCH)'")
endif

start-release: ## 🌿 Start new release branch from develop
ifneq ($(CURRENT_BRANCH),$(DEVELOP_BRANCH))
	@$(call error, "You must be on the '$(DEVELOP_BRANCH)' branch to start a release")
	@exit 1
else
	@$(call colorecho, "Creating new release branch 'release/$(VERSION)' from '$(DEVELOP_BRANCH)'...")
	@git checkout -b release/$(VERSION) $(DEVELOP_BRANCH)
	@$(call success, "Successfully created and switched to 'release/$(VERSION)'")
endif

# ================================================================
# 브랜치 정리
# ================================================================

list-old-branches: ## 🌿 List merged release branches that can be deleted
	@$(call colorecho, "Merged 'release/*' branches (safe to delete):")
	@git branch --merged $(MAIN_BRANCH) | grep "release/" | sed 's/..//' || \
		echo "  No old release branches found"
	@echo ""
	@$(call colorecho, "Unmerged 'release/*' branches:")
	@git branch --no-merged $(MAIN_BRANCH) | grep "release/" | sed 's/..//' || \
		echo "  No unmerged release branches found"

clean-old-branches: ## 🧹 Delete merged release branches (CAREFUL!)
	@$(call warn, "This will delete local 'release/*' branches merged into '$(MAIN_BRANCH)'")
	@echo "$(YELLOW)Branches to be deleted:$(RESET)"
	@git branch --merged $(MAIN_BRANCH) | grep "release/" | sed 's/..//' || echo "  None"
	@echo ""
	@echo "Continue? [y/N] " && read ans && [ $${ans:-N} = y ]
	@$(call colorecho, "🧹 Cleaning up old release branches...")
	@git branch --merged $(MAIN_BRANCH) | grep "release/" | sed 's/..//' | xargs -r -n 1 git branch -d
	@$(call success, "Local cleanup complete")
	@$(call colorecho, "To delete remote branches, run: git push origin --delete <branch_name>")

clean-remote-branches: ## 🧹 Delete merged remote release branches (VERY CAREFUL!)
	@$(call warn, "This will delete REMOTE 'release/*' branches merged into '$(MAIN_BRANCH)'")
	@echo "Remote branches to be deleted:"
	@git branch -r --merged origin/$(MAIN_BRANCH) | grep "origin/release/" | sed 's/.*origin\///' || echo "  None"
	@echo ""
	@echo "Continue? [y/N] " && read ans && [ $${ans:-N} = y ]
	@$(call colorecho, "🧹 Cleaning up remote release branches...")
	@git branch -r --merged origin/$(MAIN_BRANCH) | grep "origin/release/" | sed 's/.*origin\///' | xargs -r -n 1 git push origin --delete
	@$(call success, "Remote cleanup complete")

# ================================================================
# 버전 관리
# ================================================================

bump-version: ## 🔧 Bump version (patch by default)
	@$(call colorecho, "📋 Calculating next version...")
	@if [ -z "$(NEW_VERSION)" ]; then \
		git fetch --tags 2>/dev/null || true; \
		LATEST_TAG=$$(git describe --tags $$(git rev-list --tags --max-count=1) 2>/dev/null || echo "v0.0.0"); \
		VERSION_NUM=$$(echo $$LATEST_TAG | sed 's/v//'); \
		MAJOR=$$(echo $$VERSION_NUM | cut -d. -f1); \
		MINOR=$$(echo $$VERSION_NUM | cut -d. -f2); \
		PATCH=$$(echo $$VERSION_NUM | cut -d. -f3); \
		NEW_PATCH=$$((PATCH + 1)); \
		NEW_VERSION="v$$MAJOR.$$MINOR.$$NEW_PATCH"; \
		echo "$$NEW_VERSION" > .NEW_VERSION.tmp; \
		echo "Latest tag     : $$LATEST_TAG"; \
		echo "Next version   : $$NEW_VERSION"; \
	else \
		echo "$$NEW_VERSION" > .NEW_VERSION.tmp; \
		echo "Using provided version: $$NEW_VERSION"; \
	fi

# Bump minor version
bump-minor: ## 🔧 Bump minor version
	@$(call colorecho, "📋 Bumping minor version...")
	@git fetch --tags 2>/dev/null || true
	@LATEST_TAG=$$(git describe --tags $$(git rev-list --tags --max-count=1) 2>/dev/null || echo "v0.0.0"); \
	VERSION_NUM=$$(echo $$LATEST_TAG | sed 's/v//'); \
	MAJOR=$$(echo $$VERSION_NUM | cut -d. -f1); \
	MINOR=$$(echo $$VERSION_NUM | cut -d. -f2); \
	NEW_MINOR=$$((MINOR + 1)); \
	NEW_VERSION="v$$MAJOR.$$NEW_MINOR.0"; \
	echo "$$NEW_VERSION" > .NEW_VERSION.tmp; \
	echo "Latest tag     : $$LATEST_TAG"; \
	echo "Next version   : $$NEW_VERSION (MINOR)"

# Bump major version
bump-major: ## 🔧 Bump major version
	@$(call colorecho, "📋 Bumping major version...")
	@git fetch --tags 2>/dev/null || true
	@LATEST_TAG=$$(git describe --tags $$(git rev-list --tags --max-count=1) 2>/dev/null || echo "v0.0.0"); \
	VERSION_NUM=$$(echo $$LATEST_TAG | sed 's/v//'); \
	MAJOR=$$(echo $$VERSION_NUM | cut -d. -f1); \
	NEW_MAJOR=$$((MAJOR + 1)); \
	NEW_VERSION="v$$NEW_MAJOR.0.0"; \
	echo "$$NEW_VERSION" > .NEW_VERSION.tmp; \
	echo "Latest tag     : $$LATEST_TAG"; \
	echo "Next version   : $$NEW_VERSION (MAJOR)"
# ================================================================
# 릴리스 프로세스
# ================================================================

# 🌿 Create release branch
# Create release branch with version check
# create-release-branch: ## 🌿 Create release branch
# 	@$(call colorecho, "🌿 Creating release branch...")
# 	@if [ -n "$(NEW_VERSION)" ]; then \
# 		RELEASE_VERSION="$(NEW_VERSION)"; \
# 	elif [ -f .NEW_VERSION.tmp ]; then \
# 		RELEASE_VERSION=$$(cat .NEW_VERSION.tmp); \
# 	else \
# 		$(call error, "NEW_VERSION is not set and .NEW_VERSION.tmp not found"); \
# 		exit 1; \
# 	fi; \
# 	RELEASE_BRANCH="release/$$RELEASE_VERSION"; \
# 	CUR_BRANCH=$$(git rev-parse --abbrev-ref HEAD); \
# 	if git rev-parse --verify "$$RELEASE_BRANCH" >/dev/null 2>&1; then \
# 		$(call colorecho, "Release branch '$$RELEASE_BRANCH' already exists. Removing for idempotency..."); \
# 		if [ "$$CUR_BRANCH" = "$$RELEASE_BRANCH" ]; then \
# 			git checkout develop; \
# 		fi; \
# 		git branch -D "$$RELEASE_BRANCH"; \
# 	fi; \
# 	$(call colorecho, "Creating new release branch '$$RELEASE_BRANCH' from 'develop'..."); \
# 	git checkout -b "$$RELEASE_BRANCH" develop && \
# 	$(call success, "Successfully created and switched to '$$RELEASE_BRANCH'")


# create-release-branch: ## 🌿 Create release branch
# 		@$(call colorecho, "Debugging version file location...")
# 		@echo "Current directory: $$(pwd)"
# 		@echo "NEW_VERSION.tmp exists: $$(test -f .NEW_VERSION.tmp && echo "yes" || echo "no")"
# 		@echo "File contents if exists: $$(cat .NEW_VERSION.tmp 2>/dev/null || echo "no content")"
# 		@$(MAKEFILE_DIR)/scripts/create-release-branch.sh


# Git repository validation
check-git-repo:
	@if ! git rev-parse --git-dir > /dev/null 2>&1; then \
		echo "$(RED)Error: Not in a git repository. Please run 'git init' first.$(RESET)" >&2; \
		exit 1; \
	fi

# Ensure develop branch exists
ensure-develop-branch: check-git-repo
	@if ! git rev-parse --verify develop > /dev/null 2>&1; then \
		echo "$(BLUE)Develop branch not found. Creating develop branch...$(RESET)"; \
		if git rev-parse --verify main > /dev/null 2>&1; then \
			git checkout -b develop main; \
		elif git rev-parse --verify master > /dev/null 2>&1; then \
			git checkout -b develop master; \
		else \
			git checkout -b develop; \
			git add .; \
			git commit -m "Initial commit" || true; \
		fi; \
	fi

# Get release version
get-release-version:
	$(eval RELEASE_VERSION := $(if $(NEW_VERSION),$(NEW_VERSION),$(shell cat .NEW_VERSION.tmp 2>/dev/null)))
	@if [ -z "$(RELEASE_VERSION)" ]; then \
		echo "$(RED)Error: NEW_VERSION is not set and .NEW_VERSION.tmp not found$(RESET)" >&2; \
		exit 1; \
	fi

# Create release branch
create-release-branch: bump-version ensure-develop-branch get-release-version ## 🌿 Create release branch
	@echo "$(BLUE)🌿 Creating release branch...$(RESET)"
	@echo "$(BLUE)Using version: $(RELEASE_VERSION)$(RESET)"
	@RELEASE_BRANCH="release/$(RELEASE_VERSION)"; \
	if ! git checkout develop; then \
		echo "$(RED)Error: Failed to checkout develop branch$(RESET)" >&2; \
		exit 1; \
	fi; \
	if git rev-parse --verify "release/$(RELEASE_VERSION)" >/dev/null 2>&1; then \
		echo "$(BLUE)Release branch 'release/$(RELEASE_VERSION)' already exists. Removing for idempotency...$(RESET)"; \
		git branch -D "release/$(RELEASE_VERSION)"; \
	fi; \
	echo "$(BLUE)Creating new release branch 'release/$(RELEASE_VERSION)' from 'develop'...$(RESET)"; \
	if git checkout -b "release/$(RELEASE_VERSION)"; then \
		echo "$(GREEN)✅ Successfully created and switched to 'release/$(RELEASE_VERSION)'$(RESET)"; \
	else \
		echo "$(RED)Error: Failed to create release branch$(RESET)" >&2; \
		exit 1; \
	fi


push-release-branch: ## 🌿 Push current release branch to origin
	@$(call colorecho, "📤 Pushing release branch...")
	@CUR_BRANCH=$$(git rev-parse --abbrev-ref HEAD); \
	if [ -z "$$NEW_VERSION" ]; then \
		NEW_VERSION=$$(cat .NEW_VERSION.tmp 2>/dev/null || echo ""); \
	fi; \
	if [ -z "$$NEW_VERSION" ]; then \
		$(call error, "No version found. Run 'make bump-version' first"); \
		exit 1; \
	fi; \
	RELEASE_BRANCH="release/$$NEW_VERSION"; \
	if ! echo "$$CUR_BRANCH" | grep -q "^release/"; then \
		$(call error, "You must be on a 'release/*' branch (currently on '$$CUR_BRANCH')"); \
		exit 1; \
	fi; \
	git push -u origin $$RELEASE_BRANCH; \
	$(call success, "Successfully pushed release branch")

finish-release: ## 🚀 Complete release process (merge to main and develop, create tag)
	@$(call colorecho, "🎉 Finishing release...")
	@if [ ! -f .NEW_VERSION.tmp ]; then \
		$(call error, "No version file found. Run release process from the beginning"); \
		exit 1; \
	fi; \
	NEW_VERSION=$$(cat .NEW_VERSION.tmp); \
	RELEASE_BRANCH="release/$$NEW_VERSION"; \
	RELEASE_VERSION=$$(echo "$$RELEASE_BRANCH" | sed "s/release\///"); \
	PREVIOUS_TAG=$$(git describe --tags `git rev-list --tags --max-count=1` 2>/dev/null); \
	if [ -z "$$PREVIOUS_TAG" ]; then \
		CHANGELOG=$$(git log --pretty=format:"- %s (%h)" $(DEVELOP_BRANCH)..$$RELEASE_BRANCH); \
	else \
		CHANGELOG=$$(git log --pretty=format:"- %s (%h)" $$PREVIOUS_TAG..$$RELEASE_BRANCH); \
	fi; \
	$(call colorecho, "Merging $$RELEASE_BRANCH into $(MAIN_BRANCH)..."); \
	git checkout $(MAIN_BRANCH); \
	git pull origin $(MAIN_BRANCH); \
	git merge --no-ff -m "Merge $$RELEASE_BRANCH into $(MAIN_BRANCH)" $$RELEASE_BRANCH; \
	$(call colorecho, "Tagging release: $$RELEASE_VERSION"); \
	git tag -a $$RELEASE_VERSION -m "Release $$RELEASE_VERSION"; \
	$(call colorecho, "Merging back into $(DEVELOP_BRANCH)..."); \
	git checkout $(DEVELOP_BRANCH); \
	git pull origin $(DEVELOP_BRANCH); \
	git merge --no-ff -m "Merge $$RELEASE_BRANCH into $(DEVELOP_BRANCH)" $$RELEASE_BRANCH; \
	$(call colorecho, "Pushing $(MAIN_BRANCH), $(DEVELOP_BRANCH), and tags..."); \
	git push origin $(MAIN_BRANCH); \
	git push origin $(DEVELOP_BRANCH); \
	git push --tags; \
	if command -v gh >/dev/null 2>&1; then \
		$(call colorecho, "Creating GitHub Release..."); \
		gh release create $$RELEASE_VERSION --title "Release $$RELEASE_VERSION" --notes "$$CHANGELOG"; \
	else \
		$(call warn, "GitHub CLI not found. Skipping GitHub release creation"); \
	fi; \
	$(call colorecho, "Cleaning up local release branch..."); \
	git branch -d $$RELEASE_BRANCH; \
	rm -f .NEW_VERSION.tmp; \
	$(call success, "Release $$RELEASE_VERSION finished successfully!")

# ================================================================
# 자동화된 릴리스 프로세스
# ================================================================

# Auto release process
auto-release: ## 🚀 Automated release process
	@echo "$(BLUE)🚀 [auto-release] Starting automated release...$(RESET)"
	@if [ -n "$(VERSION)" ]; then \
		export NEW_VERSION="$(VERSION)"; \
	fi; \
	$(MAKE) bump-version NEW_VERSION="$$NEW_VERSION" && \
	if [ -f .NEW_VERSION.tmp ]; then \
		NEXT_VERSION=$$(cat .NEW_VERSION.tmp); \
		echo "$(BLUE)Using version: $$NEXT_VERSION$(RESET)"; \
		$(MAKE) create-release-branch NEW_VERSION="$$NEXT_VERSION" && \
		$(MAKE) update-version-file NEW_VERSION="$$NEXT_VERSION" && \
		$(MAKE) version-tag TAG_VERSION="$$NEXT_VERSION" && \
		$(MAKE) merge-release; \
	else \
		echo "$(RED)Error: Failed to determine version$(RESET)" >&2; \
		exit 1; \
	fi; \
	echo "$(GREEN)🎉 Auto-release completed successfully!$(RESET)"


# Merge release branch
merge-release: ## 🔄 Merge release branch to main branches
	@echo "$(BLUE)🔄 Merging release branch...$(RESET)"
	@CUR_BRANCH=$$(git rev-parse --abbrev-ref HEAD); \
	if ! echo "$$CUR_BRANCH" | grep -q "^release/"; then \
		echo "$(RED)Error: Not on a release branch. Current branch: $$CUR_BRANCH$(RESET)" >&2; \
		exit 1; \
	fi; \
	echo "$(BLUE)Merging to main...$(RESET)"; \
	if ! git rev-parse --verify main >/dev/null 2>&1; then \
		echo "$(BLUE)Creating main branch...$(RESET)"; \
		git checkout -b main; \
	else \
		git checkout main; \
	fi && \
	if ! git merge --no-ff "$$CUR_BRANCH" -m "🔀 Merge release $$CUR_BRANCH into main"; then \
		echo "$(RED)Error: Failed to merge into main$(RESET)" >&2; \
		exit 1; \
	fi; \
	echo "$(BLUE)Merging to develop...$(RESET)"; \
	if ! git checkout develop; then \
		echo "$(RED)Error: Failed to checkout develop branch$(RESET)" >&2; \
		exit 1; \
	fi && \
	if ! git merge --no-ff "$$CUR_BRANCH" -m "🔀 Merge release $$CUR_BRANCH into develop"; then \
		echo "$(RED)Error: Failed to merge into develop$(RESET)" >&2; \
		exit 1; \
	fi && \
	echo "$(BLUE)Cleaning up release branch...$(RESET)" && \
	git branch -d "$$CUR_BRANCH" && \
	echo "$(GREEN)✅ Release branch successfully merged and cleaned up!$(RESET)"

.PHONY: merge-release

# ================================================================
# 핫픽스 지원
# ================================================================

start-hotfix: ## 🌿 Start hotfix branch from main
	@$(call colorecho, "🔥 Starting hotfix branch...")
	@if [ -z "$(HOTFIX_NAME)" ]; then \
		$(call error, "HOTFIX_NAME is required. Usage: make start-hotfix HOTFIX_NAME=fix-critical-bug"); \
		exit 1; \
	fi; \
	git checkout $(MAIN_BRANCH); \
	git pull origin $(MAIN_BRANCH); \
	git checkout -b hotfix/$(HOTFIX_NAME) $(MAIN_BRANCH); \
	$(call success, "Created hotfix branch 'hotfix/$(HOTFIX_NAME)'")

finish-hotfix: ## 🚀 Finish hotfix (merge to main and develop)
	@$(call colorecho, "🔥 Finishing hotfix...")
	@CUR_BRANCH=$$(git rev-parse --abbrev-ref HEAD); \
	if ! echo "$$CUR_BRANCH" | grep -q "^hotfix/"; then \
		$(call error, "You must be on a 'hotfix/*' branch"); \
		exit 1; \
	fi; \
	HOTFIX_NAME=$$(echo "$$CUR_BRANCH" | sed 's/hotfix\///'); \
	$(call colorecho, "Merging $$CUR_BRANCH into $(MAIN_BRANCH)..."); \
	git checkout $(MAIN_BRANCH); \
	git pull origin $(MAIN_BRANCH); \
	git merge --no-ff $$CUR_BRANCH; \
	$(call colorecho, "Merging $$CUR_BRANCH into $(DEVELOP_BRANCH)..."); \
	git checkout $(DEVELOP_BRANCH); \
	git pull origin $(DEVELOP_BRANCH); \
	git merge --no-ff $$CUR_BRANCH; \
	$(call colorecho, "Pushing changes..."); \
	git push origin $(MAIN_BRANCH); \
	git push origin $(DEVELOP_BRANCH); \
	git branch -d $$CUR_BRANCH; \
	$(call success, "Hotfix '$$HOTFIX_NAME' completed!")
