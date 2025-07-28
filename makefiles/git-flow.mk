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

bump-version: ## 🌿 Calculate and show next patch version
	@$(call colorecho, "📋 Calculating next version...")
	@if [ -z "$$NEW_VERSION" ]; then \
		$(BUMP_VERSION_LOGIC); \
		echo "$$NEW_VERSION" > .NEW_VERSION.tmp; \
		$(call colorecho, "Latest tag     : $$LATEST_TAG"); \
		$(call colorecho, "Next version   : $$NEW_VERSION"); \
	else \
		echo "$$NEW_VERSION" > .NEW_VERSION.tmp; \
		$(call colorecho, "NEW_VERSION is already set: $$NEW_VERSION"); \
	fi

bump-major: ## 🌿 Bump major version
	@$(call colorecho, "📋 Bumping major version...")
	@git fetch --tags; \
	LATEST_TAG=$$(git describe --tags `git rev-list --tags --max-count=1` 2>/dev/null || echo "v0.0.0"); \
	VERSION_NUM=$$(echo $$LATEST_TAG | sed 's/v//'); \
	MAJOR=$$(echo $$VERSION_NUM | cut -d. -f1); \
	NEW_MAJOR=$$(($$MAJOR + 1)); \
	NEW_VERSION="v$$NEW_MAJOR.0.0"; \
	echo "$$NEW_VERSION" > .NEW_VERSION.tmp; \
	$(call colorecho, "Latest tag     : $$LATEST_TAG"); \
	$(call colorecho, "Next version   : $$NEW_VERSION (MAJOR)")

bump-minor: ## 🌿 Bump minor version
	@$(call colorecho, "📋 Bumping minor version...")
	@git fetch --tags; \
	LATEST_TAG=$$(git describe --tags `git rev-list --tags --max-count=1` 2>/dev/null || echo "v0.0.0"); \
	VERSION_NUM=$$(echo $$LATEST_TAG | sed 's/v//'); \
	MAJOR=$$(echo $$VERSION_NUM | cut -d. -f1); \
	MINOR=$$(echo $$VERSION_NUM | cut -d. -f2); \
	NEW_MINOR=$$(($$MINOR + 1)); \
	NEW_VERSION="v$$MAJOR.$$NEW_MINOR.0"; \
	echo "$$NEW_VERSION" > .NEW_VERSION.tmp; \
	$(call colorecho, "Latest tag     : $$LATEST_TAG"); \
	$(call colorecho, "Next version   : $$NEW_VERSION (MINOR)")

# ================================================================
# 릴리스 프로세스
# ================================================================

create-release-branch: bump-version ## 🌿 Create new release branch with auto-versioning
	@$(call colorecho, "🌿 Creating release branch...")
	@CUR_BRANCH=$$(git rev-parse --abbrev-ref HEAD); \
	if [ -z "$$NEW_VERSION" ]; then \
		NEW_VERSION=$$(cat .NEW_VERSION.tmp); \
	fi; \
	RELEASE_BRANCH="release/$$NEW_VERSION"; \
	if git rev-parse --verify "$$RELEASE_BRANCH" >/dev/null 2>&1; then \
		$(call colorecho, "Release branch '$$RELEASE_BRANCH' already exists. Removing for idempotency..."); \
		if [ "$$CUR_BRANCH" = "$$RELEASE_BRANCH" ]; then \
			git checkout $(DEVELOP_BRANCH); \
		fi; \
		git branch -D $$RELEASE_BRANCH; \
	fi; \
	$(call colorecho, "Creating new release branch '$$RELEASE_BRANCH' from '$(DEVELOP_BRANCH)'..."); \
	git checkout -b $$RELEASE_BRANCH $(DEVELOP_BRANCH); \
	$(call success, "Successfully created and switched to '$$RELEASE_BRANCH'")

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

auto-release: ## 🚀 Automated release process (create branch + push + finish)
	@$(call colorecho, "🚀 [auto-release] Starting automated release...")
	@$(MAKE) create-release-branch
	@$(call colorecho, "📌 [auto-release] Created release branch successfully")
	@$(MAKE) push-release-branch  
	@$(call colorecho, "📤 [auto-release] Pushed release branch successfully")
	@$(MAKE) finish-release
	@$(call success, "🎉 [auto-release] Automated release completed!")

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