include $(MAKEFILE_DIR)/makefiles/colors.mk
# ================================================================
# Git Flow and Release Management
# ================================================================

SHOW_PATCH ?= 0     # 1이면 unified diff까지 출력
FAIL_ON_DIFF ?= 0   # 1이면 내용 다르면 비정상 종료(Exit 2)
REMOTE ?= origin
AUTO_RELEASE_ALLOWED_BRANCH ?= $(DEVELOP_BRANCH)

TAG_REMOTE ?= origin
TAG_PREFIX ?= v           # 태그 접두사 (예: v1.2.3)
BUMP ?= patch             # patch | minor | major
TAG_ANNOTATE ?= 1         # 1: annotated tag, 0: lightweight
TAG_SIGN ?= 0             # 1: GPG 서명 태그
TP    := $(strip $(TAG_PREFIX))
BUMPK := $(strip $(BUMP))
SCRIPTS_DIR = $(MAKEFILE_DIR)/scripts

# sync-remote 타겟용 변수 (remote name과 local branch name)
REMOTE_BRANCH ?= origin
LOCAL_BRANCH ?= main

USE_PAGER ?= 0
GIT_PAGER_OPT := $(if $(filter 1,$(USE_PAGER)),,--no-pager)
GIT_COMMAND := git $(GIT_PAGER_OPT)

GIT_TARGET ?= project
GIT_INFO_DIR = $(strip \
  $(if $(filter source,$(GIT_TARGET)), \
    $(if $(SOURCE_DIR),$(SOURCE_DIR),$(error GIT_TARGET=source requires SOURCE_DIR to be set)), \
  $(if $(filter system,$(GIT_TARGET)),$(MAKEFILE_DIR), \
  .)))

# 하위 호환성: CLEAN → SYNC_MODE 자동 변환
# CLEAN=true → SYNC_MODE=clone, CLEAN=false → SYNC_MODE=keep
ifdef CLEAN
  ifeq ($(CLEAN),true)
    SYNC_MODE ?= clone
  else
    SYNC_MODE ?= keep
  endif
endif
SYNC_MODE ?= reset  # 기본값: reset (remote 우선)
FETCH_ALL ?= false  # 기본값: false

.PHONY: git-status sync-develop start-release list-old-branches clean-old-branches
.PHONY: bump-version create-release-branch push-release-branch finish-release auto-release push-release push-release-clean

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
# Common helpers
# ================================================================

# Reset local branch to remote tracking branch (origin/<branch>)
# Usage: $(call RESET_TO_REMOTE, <branch-name>)
define RESET_TO_REMOTE
    branch="$(1)"; \
    if ! git rev-parse --verify "$$branch" >/dev/null 2>&1; then \
        echo "$(BLUE)Creating $$branch branch...$(RESET)"; \
        git checkout -b "$$branch" || exit 1; \
    else \
        git checkout "$$branch"; \
    fi; \
    echo "$(BLUE)🔄 Resetting $$branch to origin/$$branch...$(RESET)"; \
    git fetch origin "$$branch"; \
    git reset --hard "origin/$$branch"
endef

.PHONY: reset-branch reset-main reset-develop sync-remote-dry sync-remote _git-check

print-git-dir:
	@echo "📦 Git Directory: $(GIT_INFO_DIR)"

_git-check:
	@# git repo 여부 확인
	@if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then \
		echo "Not a git repository."; exit 1; \
	fi

git-fetch: ## 🔧 소스 코드 가져오기 (사용법: make git-fetch SOURCE_REPO=owner/repo REF=main)
	@if [ -z "$(SOURCE_REPO)" ]; then \
		echo "$(RED)❌ SOURCE_REPO 변수가 필요합니다.$(RESET)"; \
		echo ""; \
		echo "$(YELLOW)사용법:$(RESET)"; \
		echo "  make git-fetch SOURCE_REPO=owner/repo REF=main"; \
		echo "  make git-fetch SOURCE_REPO=owner/repo REF=main SYNC_MODE=keep"; \
		echo "  make git-fetch SOURCE_REPO=git@github.com:owner/repo.git REF=develop"; \
		echo "  make git-fetch SOURCE_REPO=https://github.com/owner/repo REF=feature/test"; \
		echo ""; \
		echo "$(CYAN)환경 변수:$(RESET)"; \
		echo "  GH_TOKEN   - GitHub Personal Access Token (private repo용)"; \
		echo "  SYNC_MODE  - 동기화 모드 (기본: reset)"; \
		echo "               clone = 기존 삭제 후 새로 clone"; \
		echo "               reset = remote 강제 적용 (로컬 무시) 👈 일반적"; \
		echo "               pull  = 로컬 변경사항 병합 시도"; \
		echo "               keep  = fetch만, 로컬 유지 👈 급할 때"; \
		echo "  FETCH_ALL  - 모든 remote 가져오기 (기본: false)"; \
		exit 1; \
	fi; \
	if [ -z "$(REF)" ]; then \
		echo "$(RED)❌ REF 변수가 필요합니다.$(RESET)"; \
		exit 1; \
	fi; \
	export GH_TOKEN="$(GH_TOKEN)"; \
	bash $(MAKEFILE_DIR)/scripts/fetch_source.sh \
		"$(SOURCE_DIR)" \
		"$(SOURCE_REPO)" \
		"$(REF)" \
		"$(SYNC_MODE)" \
		"$(FETCH_ALL)"


scan-secrets: ## 🔒 Lightweight secret scan (regex) — no deps
	@set -Eeuo pipefail; echo "$(BLUE)🔍 Scanning for obvious secrets...$(RESET)"; \
	grep -RIn --exclude-dir=.git --exclude-dir=node_modules --exclude=package-lock.json \
	  -E '(AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_\-]{35}|xox[baprs]-[0-9A-Za-z-]{10,}|-----BEGIN (OPENSSH|RSA|EC) PRIVATE KEY-----)' . || true; \
	echo "$(YELLOW)Heuristic only; consider dedicated tooling for CI (git-secrets/trufflehog)$(RESET)"

compare-with-remote: ## 🔍 Compare BRANCH vs $(REMOTE)/COMPARE_BRANCH (GIT_TARGET=..., BRANCH=..., COMPARE_BRANCH=...)
	@set -Eeuo pipefail; \
	GDIR="$(GIT_INFO_DIR)"; \
	if [ ! -d "$$GDIR/.git" ]; then \
		echo "$(RED)Error: $$GDIR is not a git repository$(RESET)"; exit 1; \
	fi; \
	echo "$(CYAN)Git target: $(GIT_TARGET) → $$GDIR$(RESET)"; \
	cd "$$GDIR"; \
	if ! $(GIT_COMMAND) rev-parse --git-dir >/dev/null 2>&1; then \
	  echo "$(RED)Error: Not a git repository$(RESET)"; exit 1; \
	fi; \
	if ! $(GIT_COMMAND) remote get-url $(REMOTE) >/dev/null 2>&1; then \
	  echo "$(RED)Error: remote '$(REMOTE)' not found$(RESET)"; exit 1; \
	fi; \
	BRANCH="$(if $(BRANCH),$(BRANCH),$$($(GIT_COMMAND) rev-parse --abbrev-ref HEAD))"; \
	RB="$(strip $(COMPARE_BRANCH))"; \
	if [ -z "$$RB" ]; then RB="$$BRANCH"; fi; \
	echo "$(BLUE)🔎 Comparing content: $$BRANCH  ⇄  $(REMOTE)/$$RB$(RESET)"; \
	$(GIT_COMMAND) fetch $(REMOTE) "$$RB" >/dev/null 2>&1 || true; \
	if ! $(GIT_COMMAND) rev-parse --verify "$(REMOTE)/$$RB^{commit}" >/dev/null 2>&1; then \
	  echo "$(RED)Error: $(REMOTE)/$$RB not found$(RESET)"; exit 1; \
	fi; \
	LT=$$($(GIT_COMMAND) rev-parse "$$BRANCH^{tree}" 2>/dev/null) || { echo "$(RED)Error: unknown local branch '$$BRANCH'$(RESET)"; exit 1; }; \
	RT=$$($(GIT_COMMAND) rev-parse "$(REMOTE)/$$RB^{tree}" 2>/dev/null); \
	if [ "$$LT" = "$$RT" ]; then \
	  echo "$(GREEN)✔ No content differences (trees are identical)$(RESET)"; \
	  exit 0; \
	fi; \
	echo "$(YELLOW)↕ Content differs. Changed files (remote → local):$(RESET)"; \
	$(GIT_COMMAND) diff --name-status --find-renames "$(REMOTE)/$$RB" "$$BRANCH"; \
	if [ "$(SHOW_PATCH)" = "1" ]; then \
	  echo ""; echo "$(BLUE)--- Unified diff ---$(RESET)"; \
	  $(GIT_COMMAND) diff --find-renames "$(REMOTE)/$$RB" "$$BRANCH"; \
	fi; \
	[ "$(FAIL_ON_DIFF)" = "1" ] && exit 2 || true

diff-refs: ## 🔍 Compare content between two arbitrary refs (REF1, REF2)
	@set -Eeuo pipefail; \
	if [ -z "$(REF1)" ] || [ -z "$(REF2)" ]; then \
	  echo "$(RED)Error: set REF1 and REF2 (e.g., make diff-refs REF1=main REF2=origin/main)$(RESET)"; exit 1; \
	fi; \
	LT=$$(git rev-parse "$(REF1)^{tree}" 2>/dev/null) || { echo "$(RED)Error: unknown ref '$(REF1)'$(RESET)"; exit 1; }; \
	RT=$$(git rev-parse "$(REF2)^{tree}" 2>/dev/null) || { echo "$(RED)Error: unknown ref '$(REF2)'$(RESET)"; exit 1; }; \
	if [ "$$LT" = "$$RT" ]; then \
	  echo "$(GREEN)✔ No content differences (trees are identical)$(RESET)"; \
	  exit 0; \
	fi; \
	echo "$(YELLOW)↕ Content differs between $(REF1) and $(REF2):$(RESET)"; \
	git diff --name-status --find-renames "$(REF1)" "$(REF2)"; \
	if [ "$(SHOW_PATCH)" = "1" ]; then \
	  echo ""; echo "$(BLUE)--- Unified diff ---$(RESET)"; \
	  git diff --find-renames "$(REF1)" "$(REF2)"; \
	fi; \
	[ "$(FAIL_ON_DIFF)" = "1" ] && exit 2 || true

diff-summary: ## 📊 Show summary stats between two refs: REF1, REF2 (lines/files/dirstat)
	@if [ -z "$(REF1)" ] || [ -z "$(REF2)" ]; then \
	  echo "$(RED)Usage: make diff-summary REF1=<ref> REF2=<ref>$(RESET)"; exit 1; \
	fi
	@echo "$(BLUE)🔢 Shortstat$(RESET)"; \
	git diff --shortstat "$(REF1)" "$(REF2)" || true; \
	echo ""; echo "$(BLUE)📁 Dirstat (by files)$(RESET)"; \
	git diff --dirstat=files,0 "$(REF1)" "$(REF2)" || true

# Reset arbitrary branch by passing BRANCH=<name>
reset-branch: check-git-repo ## 🔄 Reset BRANCH to origin/BRANCH
	@if [ -z "$(BRANCH)" ]; then \
		echo "$(RED)Error: BRANCH is required (make reset-branch BRANCH=name)$(RESET)"; exit 1; \
	fi
	@$(call RESET_TO_REMOTE,$(BRANCH))

# Reset main branch to origin/main (or configured MAIN_BRANCH)
reset-main: check-git-repo ## 🔄 Reset MAIN_BRANCH to origin/MAIN_BRANCH
	@$(call RESET_TO_REMOTE,$(MAIN_BRANCH))

# Reset develop branch to origin/develop (or configured DEVELOP_BRANCH)
reset-develop: check-git-repo ## 🔄 Reset DEVELOP_BRANCH to origin/DEVELOP_BRANCH
	@$(call RESET_TO_REMOTE,$(DEVELOP_BRANCH))

# ================================================================
# Git 상태 확인
# ================================================================

ensure-clean: ## 🌿 Ensure clean working directory
	@git update-index -q --refresh
	@if ! git diff-index --quiet HEAD --; then \
		echo "$(RED)Error: You have uncommitted changes. Commit or stash first.$(RESET)"; \
		exit 1; \
	fi

git-status: print-git-dir ## 🌿 Show comprehensive git status (GIT_TARGET=project|source|system)
	@GDIR="$(GIT_INFO_DIR)"; \
	if [ ! -d "$$GDIR/.git" ]; then \
		echo "$(RED)Error: $$GDIR is not a git repository$(RESET)"; exit 1; \
	fi; \
	echo "$(CYAN)Git target: $(GIT_TARGET) → $$GDIR$(RESET)"; \
	cd "$$GDIR"; \
	echo "$(BLUE)Git Repository Status:$(RESET)"; \
	CUR=$$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown"); \
	echo "  Current Branch: $$CUR"; \
	echo "  Main Branch: $(MAIN_BRANCH)"; \
	echo "  Develop Branch: $(DEVELOP_BRANCH)"; \
	echo ""; \
	echo "$(BLUE)Working Directory:$(RESET)"; \
	git status --short || echo "  Clean"; \
	echo ""; \
	echo "$(BLUE)Recent Tags:$(RESET)"; \
	git tag --sort=-version:refname | head -5 || echo "  No tags found"; \
	echo ""; \
	echo "$(BLUE)Branch Tracking:$(RESET)"; \
	git branch -vv | grep "^\*" || echo "  Not tracking any remote"; \
	UP=$$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || echo "none"); \
	echo "  Upstream: $$UP"; \
	if [ "$$UP" != "none" ]; then \
	  git rev-list --left-right --count $$UP...HEAD 2>/dev/null | awk '{printf "  Divergence: behind %s, ahead %s\n", $$1, $$2}'; \
	else echo "  Divergence: n/a"; fi; \
	echo ""; \
	echo "$(BLUE)Remotes:$(RESET)"; \
	git remote -v | awk '$$3=="(fetch)"{printf "  %s -> %s\n", $$1, $$2}' || echo "  No remotes found"; \
	echo "  Default Remote (REMOTE): $(REMOTE)"; \
	echo "  $(REMOTE) URL: $$(git remote get-url $(REMOTE) 2>/dev/null || echo "not set")"

git-branches: ## 🌿 Show all branches with status (GIT_TARGET=project|source|system)
	@GDIR="$(GIT_INFO_DIR)"; \
	if [ ! -d "$$GDIR/.git" ]; then \
		echo "$(RED)Error: $$GDIR is not a git repository$(RESET)"; exit 1; \
	fi; \
	echo "$(CYAN)Git target: $(GIT_TARGET) → $$GDIR$(RESET)"; \
	cd "$$GDIR"; \
	echo "$(BLUE)Local Branches:$(RESET)"; \
	$(GIT_COMMAND) branch -v; \
	echo ""; \
	echo "$(BLUE)Remote Branches:$(RESET)"; \
	$(GIT_COMMAND) branch -rv

	
# ================================================================
# 브랜치 관리
# ================================================================

sync-remote-dry: _git-check ## 🌿 Dry run: preview changes before sync-remote (REMOTE_BRANCH, LOCAL_BRANCH)
	@echo "$(BLUE)>>> DRY RUN: $(REMOTE_BRANCH)/$(LOCAL_BRANCH) 기준으로 동기화시 삭제/변경될 항목 미리보기$(RESET)"
	@$(GIT_COMMAND) fetch $(REMOTE_BRANCH)
	@echo "---- [git diff --name-status HEAD..$(REMOTE_BRANCH)/$(LOCAL_BRANCH)] ----"
	@$(GIT_COMMAND) diff --name-status HEAD..$(REMOTE_BRANCH)/$(LOCAL_BRANCH) || true
	@echo "$(RED)---- [git clean -fdxn] ----$(RESET)"
	@$(GIT_COMMAND) clean -fdxn

sync-remote: _git-check ## 🌿 Hard reset to remote branch (CONFIRM=1, REMOTE_BRANCH, LOCAL_BRANCH)
	@if [ "$(CONFIRM)" != "1" ]; then \
		echo "This will DISCARD ALL local changes and untracked files."; \
		echo "Run: make sync-remote CONFIRM=1"; \
		exit 1; \
	fi
	@set -e; \
	echo "$(GREEN)>>> Fetching $(REMOTE_BRANCH) $(RESET)"; \
	$(GIT_COMMAND) fetch $(REMOTE_BRANCH); \
	echo "$(GREEN)>>> Hard reset to $(REMOTE_BRANCH)/$(LOCAL_BRANCH)$(RESET)"; \
	$(GIT_COMMAND) reset --hard $(REMOTE_BRANCH)/$(LOCAL_BRANCH); \
	echo "$(GREEN)>>> Cleaning untracked files/folders (.gitignore 제외)$(RESET)"; \
	$(GIT_COMMAND) clean -fd; \
	echo "$(GREEN)Done. Current HEAD -> $(REMOTE_BRANCH)/$(LOCAL_BRANCH)$(RESET)"; \
	$(GIT_COMMAND) status -sb


sync-develop: ## 🌿 Sync current branch to develop branch
ifeq ($(CURRENT_BRANCH),$(DEVELOP_BRANCH))
	@$(call colorecho, Already on '$(DEVELOP_BRANCH)' branch. Nothing to do.)
else
	@$(call colorecho, Switching to '$(DEVELOP_BRANCH)' and merging '$(CURRENT_BRANCH)'...)
	@git checkout $(DEVELOP_BRANCH)
	@git pull origin $(DEVELOP_BRANCH)
	@git merge --no-ff $(CURRENT_BRANCH)
	@git push origin $(DEVELOP_BRANCH)
	@$(call success, Successfully merged '$(CURRENT_BRANCH)' into '$(DEVELOP_BRANCH)')
endif

# 모든 로컬 브랜치를 원격으로 푸시
push-all-branches: ## 🌿 Push all local branches to remote ($(REMOTE))
	@echo "$(BLUE)📤 Pushing all local branches to $(REMOTE)...$(RESET)"; \
	branches=$$(git for-each-ref --format='%(refname:short)' refs/heads); \
	if [ -z "$$branches" ]; then \
		echo "$(YELLOW)No local branches found$(RESET)"; \
		exit 0; \
	fi; \
	if ! git remote get-url $(REMOTE) >/dev/null 2>&1; then \
		echo "$(RED)Error: remote '$(REMOTE)' not found$(RESET)"; \
		exit 1; \
	fi; \
	for b in $$branches; do echo "  → $$b"; git push $(REMOTE) "$$b"; done; \
	echo "$(GREEN)✅ All local branches pushed to $(REMOTE)$(RESET)"

start-release: ## 🌿 Start new release branch from develop
ifneq ($(CURRENT_BRANCH),$(DEVELOP_BRANCH))
	@$(call fail, You must be on the '$(DEVELOP_BRANCH)' branch to start a release)
	@exit 1
else
	@$(call colorecho, Creating new release branch 'release/$(VERSION)' from '$(DEVELOP_BRANCH)'...)
	@git checkout -b release/$(VERSION) $(DEVELOP_BRANCH)
	@$(call success, Successfully created and switched to 'release/$(VERSION)')
endif

# ================================================================
# 브랜치 정리
# ================================================================

list-old-branches: ## 🌿 List merged release branches that can be deleted
	@$(call colorecho, Merged 'release/*' branches (safe to delete):)
	@git branch --merged $(MAIN_BRANCH) | grep "release/" | sed 's/..//' || \
		echo "  No old release branches found"
	@echo ""
	@$(call colorecho, Unmerged 'release/*' branches:)
	@git branch --no-merged $(MAIN_BRANCH) | grep "release/" | sed 's/..//' || \
		echo "  No unmerged release branches found"

clean-old-branches: ## 🧹 Delete merged release branches (CAREFUL!)
	@$(call warn, This will delete local 'release/*' branches merged into '$(MAIN_BRANCH)')
	@echo "$(YELLOW)Branches to be deleted:$(RESET)"
	@git branch --merged $(MAIN_BRANCH) | grep "release/" | sed 's/..//' || echo "  None"
	@echo ""
	@echo "Continue? [y/N] " && read ans && [ $${ans:-N} = y ]
	@$(call colorecho, 🧹 Cleaning up old release branches...)
	@git branch --merged $(MAIN_BRANCH) | grep "release/" | sed 's/..//' | xargs -r -n 1 git branch -d
	@$(call success, Local cleanup complete)
	@$(call colorecho, To delete remote branches, run: git push origin --delete <branch_name>)

clean-remote-branches: ## 🧹 Delete merged remote release branches (VERY CAREFUL!)
	@$(call warn, This will delete REMOTE 'release/*' branches merged into '$(MAIN_BRANCH)')
	@echo "Remote branches to be deleted:"
	@git branch -r --merged origin/$(MAIN_BRANCH) | grep "origin/release/" | sed 's/.*origin\///' || echo "  None"
	@echo ""
	@echo "Continue? [y/N] " && read ans && [ $${ans:-N} = y ]
	@$(call colorecho, 🧹 Cleaning up remote release branches...)
	@git branch -r --merged origin/$(MAIN_BRANCH) | grep "origin/release/" | sed 's/.*origin\///' | xargs -r -n 1 git push origin --delete
	@$(call success, Remote cleanup complete)

# ================================================================
# 버전 관리
# ================================================================

commit-version-bump: ## ✅ Commit version bump on release branch
	@V=$$(cat .NEW_VERSION.tmp); \
	git add -A; \
	if ! git diff --cached --quiet; then \
		git commit -m "chore(release): bump version to $$V"; \
		echo "$(GREEN)✅ Committed version bump to $$V$(RESET)"; \
	else \
		echo "$(YELLOW)No changes to commit$(RESET)"; \
	fi

bump-version: ## 🔧 Bump version (patch by default)
	@$(call colorecho, 📋 Calculating next version...)
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
	@$(call colorecho, 📋 Bumping minor version...)
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
	@$(call colorecho, 📋 Bumping major version...)
	@git fetch --tags 2>/dev/null || true
	@LATEST_TAG=$$(git describe --tags $$(git rev-list --tags --max-count=1) 2>/dev/null || echo "v0.0.0"); \
	VERSION_NUM=$$(echo $$LATEST_TAG | sed 's/v//'); \
	MAJOR=$$(echo $$VERSION_NUM | cut -d. -f1); \
	NEW_MAJOR=$$((MAJOR + 1)); \
	NEW_VERSION="v$$NEW_MAJOR.0.0"; \
	echo "$$NEW_VERSION" > .NEW_VERSION.tmp; \
	echo "Latest tag     : $$LATEST_TAG"; \
	echo "Next version   : $$NEW_VERSION (MAJOR)"

########################################################
# TAG 관리
#####################################################3

next-version-from-remote: ## 🔎 Fetch remote latest tag and compute next version (BUMP=patch|minor|major)
	@set -Eeuo pipefail; \
	echo "🔄 Fetching tags from '$(TAG_REMOTE)'..."; \
	git fetch --tags $(TAG_REMOTE) >/dev/null 2>&1 || true; \
	TP='$(TP)'; BUMPK='$(BUMPK)'; \
	LATEST_TAG=$$( \
	  git ls-remote --tags --refs $(TAG_REMOTE) "$${TP}*" \
	  | awk '{print $$2}' \
	  | sed 's#refs/tags/##' \
	  | grep -E "^$${TP}[0-9]+\.[0-9]+\.[0-9]+$$" \
	  | sort -V \
	  | tail -n1 \
	); \
	if [ -z "$$LATEST_TAG" ]; then \
	  echo "ℹ️  No remote tags found. Using $${TP}0.0.0 as base."; \
	  LATEST_TAG="$${TP}0.0.0"; \
	fi; \
	VNUM=$$(printf "%s\n" "$$LATEST_TAG" | sed "s/^$${TP}//"); \
	MAJOR=$$(echo $$VNUM | cut -d. -f1); \
	MINOR=$$(echo $$VNUM | cut -d. -f2); \
	PATCH=$$(echo $$VNUM | cut -d. -f3); \
	case "$$BUMPK" in \
	  major) NEW_MAJOR=$$((MAJOR+1)); NEW_MINOR=0; NEW_PATCH=0 ;; \
	  minor) NEW_MAJOR=$$MAJOR; NEW_MINOR=$$((MINOR+1)); NEW_PATCH=0 ;; \
	  patch) NEW_MAJOR=$$MAJOR; NEW_MINOR=$$MINOR; NEW_PATCH=$$((PATCH+1)) ;; \
	  *) echo "❌ Unknown BUMP='$$BUMPK'. Use patch|minor|major"; exit 2 ;; \
	esac; \
	NEW_VERSION="$${TP}$${NEW_MAJOR}.$${NEW_MINOR}.$${NEW_PATCH}"; \
	printf "%s\n" "$$NEW_VERSION" > .NEW_VERSION.tmp; \
	echo "🔖 Latest remote tag : $$LATEST_TAG"; \
	echo "🚀 Next $$BUMPK version: $$NEW_VERSION"
# version-tag-remote:
# - .NEW_VERSION.tmp (또는 TAG_VERSION 변수)로 태그 생성
# - 원격(TAG_REMOTE)으로 푸시
version-tag-remote: ## 🏷️ Create tag from computed version and push to remote
	@set -Eeuo pipefail; \
	TAG="$${TAG_VERSION:-$$(cat .NEW_VERSION.tmp 2>/dev/null || true)}"; \
	if [ -z "$$TAG" ]; then echo "❌ No TAG version. Run 'make next-version-from-remote' or pass TAG_VERSION=vX.Y.Z"; exit 1; fi; \
	echo "🪪 Using tag: $$TAG"; \
	git fetch --tags $(TAG_REMOTE) >/dev/null 2>&1 || true; \
	if git rev-parse -q --verify "refs/tags/$$TAG" >/dev/null; then \
	  echo "ℹ️  Tag $$TAG already exists locally. Skipping create."; \
	else \
	  MSG="Release $$TAG"; \
	  if [ "$(TAG_SIGN)" = "1" ]; then \
	    if [ "$(TAG_ANNOTATE)" = "1" ]; then git tag -s -a "$$TAG" -m "$$MSG"; else git tag -s "$$TAG" -m "$$MSG"; fi; \
	  else \
	    if [ "$(TAG_ANNOTATE)" = "1" ]; then git tag -a "$$TAG" -m "$$MSG"; else git tag "$$TAG"; fi; \
	  fi; \
	  echo "✅ Created tag $$TAG"; \
	fi; \
	echo "📤 Pushing tag $$TAG to $(TAG_REMOTE) ..."; \
	git push "$(TAG_REMOTE)" "$$TAG"

# bump-and-push-tag-remote:
# - 원샷: 최신 리모트 태그 기반 다음 버전 계산 → 태그 생성 → 푸시
bump-and-push-tag-remote: ## 🚀 One-shot: compute next (remote) + create + push (BUMP=patch|minor|major)
	@$(MAKE) next-version-from-remote BUMP=$(BUMP)
	@$(MAKE) version-tag-remote


# ================================================================
# 릴리스 프로세스
# ================================================================

# 🌿 Create release branch
# Create release branch with version check
# create-release-branch: ## 🌿 Create release branch
# 	@$(call colorecho, 🌿 Creating release branch...)
# 	@if [ -n "$(NEW_VERSION)" ]; then \
# 		RELEASE_VERSION="$(NEW_VERSION)"; \
# 	elif [ -f .NEW_VERSION.tmp ]; then \
# 		RELEASE_VERSION=$$(cat .NEW_VERSION.tmp); \
# 	else \
# 		$(call fail, "NEW_VERSION is not set and .NEW_VERSION.tmp not found"); \
# 		exit 1; \
# 	fi; \
# 	RELEASE_BRANCH="release/$$RELEASE_VERSION"; \
# 	CUR_BRANCH=$$(git rev-parse --abbrev-ref HEAD); \
# 	if git rev-parse --verify "$$RELEASE_BRANCH" >/dev/null 2>&1; then \
# 		$(call colorecho, Release branch '$$RELEASE_BRANCH' already exists. Removing for idempotency...); \
# 		if [ "$$CUR_BRANCH" = "$$RELEASE_BRANCH" ]; then \
# 			git checkout develop; \
# 		fi; \
# 		git branch -D "$$RELEASE_BRANCH"; \
# 	fi; \
# 	$(call colorecho, Creating new release branch '$$RELEASE_BRANCH' from 'develop'...)
# 	git checkout -b "$$RELEASE_BRANCH" develop && \
# 	$(call success, "Successfully created and switched to '$$RELEASE_BRANCH'")


# create-release-branch: ## 🌿 Create release branch
# 		@$(call colorecho, Debugging version file location...)
# 		@echo "Current directory: $$(pwd)"
# 		@echo "NEW_VERSION.tmp exists: $$(test -f .NEW_VERSION.tmp && echo "yes" || echo "no")"
# 		@echo "File contents if exists: $$(cat .NEW_VERSION.tmp 2>/dev/null || echo "no content")"
# 		@$(MAKEFILE_DIR)/scripts/create-release-branch.sh


# Git repository validation
check-git-repo: ## 🌿 Check if current directory is a git repository
	@if ! git rev-parse --git-dir > /dev/null 2>&1; then \
		echo "$(RED)Error: Not in a git repository. Please run 'git init' first.$(RESET)" >&2; \
		exit 1; \
	fi

# Ensure develop branch exists
ensure-develop-branch: check-git-repo ## 🌿 Ensure develop branch exists
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
get-release-version: ## 🌿 Get release version
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
	@$(call colorecho, 📤 Pushing release branch...)
	@CUR_BRANCH=$$(git rev-parse --abbrev-ref HEAD); \
	if [ -z "$$NEW_VERSION" ]; then \
		NEW_VERSION=$$(cat .NEW_VERSION.tmp 2>/dev/null || echo ""); \
	fi; \
	if [ -z "$$NEW_VERSION" ]; then \
		$(call fail, No version found. Run 'make bump-version' first); \
		exit 1; \
	fi; \
	RELEASE_BRANCH="release/$$NEW_VERSION"; \
	if ! echo "$$CUR_BRANCH" | grep -q "^release/"; then \
		$(call fail, You must be on a 'release/*' branch (currently on '$$CUR_BRANCH')); \
		exit 1; \
	fi; \
	git push -u origin $$RELEASE_BRANCH; \
	$(call success, Successfully pushed release branch)

finish-release: ## 🚀 Complete release process (merge to main and develop, create tag)
	@$(call colorecho, 🎉 Finishing release...)
	@if [ ! -f .NEW_VERSION.tmp ]; then \
		$(call fail, No version file found. Run release process from the beginning); \
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
	$(call colorecho, Merging $$RELEASE_BRANCH into $(MAIN_BRANCH)...); \
	$(call colorecho, Resetting $(MAIN_BRANCH) to origin/$(MAIN_BRANCH) ...); \
    $(call RESET_TO_REMOTE,$(MAIN_BRANCH)); \
	git merge --no-ff -m "Merge $$RELEASE_BRANCH into $(MAIN_BRANCH)" $$RELEASE_BRANCH; \
	$(call colorecho, Tagging release: $$RELEASE_VERSION); \
	git tag -a $$RELEASE_VERSION -m "Release $$RELEASE_VERSION"; \
	$(call colorecho, Merging back into $(DEVELOP_BRANCH)...); \
	$(call colorecho, Resetting $(DEVELOP_BRANCH) to origin/$(DEVELOP_BRANCH) ...); \
	$(call RESET_TO_REMOTE,$(DEVELOP_BRANCH)); \
	git merge --no-ff -m "Merge $$RELEASE_BRANCH into $(DEVELOP_BRANCH)" $$RELEASE_BRANCH; \
	$(call colorecho, Pushing $(MAIN_BRANCH), $(DEVELOP_BRANCH), and tags...); \
	git push origin $(MAIN_BRANCH); \
	git push origin $(DEVELOP_BRANCH); \
	git push --tags; \
	if command -v gh >/dev/null 2>&1; then \
		$(call colorecho, Creating GitHub Release...); \
		gh release create $$RELEASE_VERSION --title "Release $$RELEASE_VERSION" --notes "$$CHANGELOG"; \
	else \
		$(call warn, GitHub CLI not found. Skipping GitHub release creation); \
	fi; \
	$(call colorecho, Cleaning up local release branch...); \
	git branch -d $$RELEASE_BRANCH; \
	rm -f .NEW_VERSION.tmp; \
	$(call success, Release $$RELEASE_VERSION finished successfully!)

# ================================================================
# 자동화된 릴리스 프로세스
# ================================================================


push-release: ## 📤 Push main, develop, and tags to remote
	@echo "$(BLUE)📤 Pushing branches and tags to $(REMOTE)...$(RESET)"
	@if ! git rev-parse --verify main >/dev/null 2>&1; then \
		echo "$(RED)Error: main branch not found$(RESET)"; exit 1; \
	fi
	@if ! git rev-parse --verify develop >/dev/null 2>&1; then \
		echo "$(RED)Error: develop branch not found$(RESET)"; exit 1; \
	fi
	@git push $(REMOTE) main develop
	@git push --tags || true
	@echo "$(GREEN)✅ Successfully pushed main, develop, and tags$(RESET)"


push-release-clean: push-release ## 🧹 Also delete remote release/* branch (optional)
	@CUR_BRANCH=$$(git rev-parse --abbrev-ref HEAD); \
	if echo "$$CUR_BRANCH" | grep -q "^release/"; then \
		echo "$(BLUE)🧹 Deleting remote $$CUR_BRANCH on $(REMOTE)...$(RESET)"; \
		git push $(REMOTE) --delete "$$CUR_BRANCH" || true; \
	else \
		if [ -f .NEW_VERSION.tmp ]; then \
			V=$$(cat .NEW_VERSION.tmp); RB="release/$$V"; \
			if git ls-remote --heads $(REMOTE) "$$RB" >/dev/null 2>&1; then \
				echo "$(BLUE)🧹 Deleting remote $$RB on $(REMOTE)...$(RESET)"; \
				git push $(REMOTE) --delete "$$RB" || true; \
			fi; \
		fi; \
	fi


# github-release:
# 	@TAG=$$(cat .NEW_VERSION.tmp); \
# 	set -e; \
# 	if [ -n "$$GITHUB_TOKEN$$GH_TOKEN" ]; then \
# 	  echo "$${GITHUB_TOKEN:-$$GH_TOKEN}" | gh auth login --with-token >/dev/null 2>&1 || true; \
# 	  echo "Checking token scopes..."; \
# 	  curl -sI -H "Authorization: token $${GITHUB_TOKEN:-$$GH_TOKEN}" https://api.github.com/user | grep -i 'x-oauth-scopes\|x-accepted-oauth-scopes' || true; \
# 	fi; \
# 	if ! gh release create "$$TAG" --title "Release $$TAG" --generate-notes 2>err.log; then \
# 	  if grep -q "HTTP 403" err.log; then \
# 	    echo "$(RED)403: Token lacks release permission.$(RESET)"; \
# 	    echo "Needs: classic 'repo' or fine-grained 'Contents: write' (+ SSO if org)."; \
# 	  fi; \
# 	  cat err.log >&2; rm -f err.log; exit 1; \
# 	fi; rm -f err.log; echo "$(GREEN)✅ Release $$TAG created$(RESET)"



github-release: ## 🚀 Create GitHub release from version tag
	@TAG=$$(cat .NEW_VERSION.tmp); \
	echo "$(GREEN)🚀 Starting GitHub Release for $$TAG$(RESET)"; \
	set -euo pipefail; \
	TOKEN="$${GITHUB_TOKEN:-$$GH_TOKEN}"; \
	if [ -n "$$TOKEN" ]; then \
	  LEN=$$(printf %s "$$TOKEN" | wc -c); \
	  if printf %s "$$TOKEN" | grep -q '^github_pat_'; then TYPE=fine-grained; else TYPE=classic; fi; \
	  echo "🔑 Token: $$TYPE ($$LEN chars)"; \
	  echo "$$TOKEN" | gh auth login --with-token >/dev/null 2>&1 || true; \
	  echo "Scopes:"; \
	  curl -sI -H "Authorization: token $$TOKEN" https://api.github.com/user \
	    | grep -i 'x-oauth-scopes\|x-accepted-oauth-scopes' || true; \
	fi; \
	if ! gh release create "$$TAG" --title "Release $$TAG" --generate-notes 2>err.log; then \
	  if grep -q "HTTP 403" err.log; then \
	    echo "$(RED)403: Token lacks release permission.$(RESET)"; \
	    echo "Needs: classic 'repo' or fine-grained 'Contents: write' (+ SSO if org)."; \
	  fi; \
	  cat err.log >&2; rm -f err.log; exit 1; \
	fi; \
	rm -f err.log; \
	echo "$(GREEN)✅ Release $$TAG created$(RESET)"


# Auto release process
auto-release: ## 🚀 Automated release process
	@set -Eeuo pipefail; \
	START_BRANCH=$$(git rev-parse --abbrev-ref HEAD); \
	CUR_BRANCH=$$(git rev-parse --abbrev-ref HEAD); \
	if [ "$$CUR_BRANCH" != "$(AUTO_RELEASE_ALLOWED_BRANCH)" ]; then \
		echo "$(RED)Error: auto-release is allowed only on '$(AUTO_RELEASE_ALLOWED_BRANCH)'. Current: $$CUR_BRANCH$(RESET)"; \
		exit 1; \
	fi; \
	rollback(){ echo "$(YELLOW)↩️  Error occurred. Returning to '$$START_BRANCH'...$(RESET)"; git checkout -q "$$START_BRANCH" || true; }; \
	trap rollback ERR; \
	echo "$(BLUE)🚀 [auto-release] Starting automated release...$(RESET)"; \
	[ -n "$(VERSION)" ] && export NEW_VERSION="$(VERSION)" || true; \
	$(MAKE) bump-version NEW_VERSION="$$NEW_VERSION"; \
	if [ -f .NEW_VERSION.tmp ]; then \
		NEXT_VERSION=$$(cat .NEW_VERSION.tmp); \
		echo "$(BLUE)Using version: $$NEXT_VERSION$(RESET)"; \
		$(MAKE) create-release-branch NEW_VERSION="$$NEXT_VERSION"; \
		$(MAKE) update-version-file NEW_VERSION="$$NEXT_VERSION"; \
		$(MAKE) commit-version-bump; \
		$(MAKE) version-tag TAG_VERSION="$$NEXT_VERSION"; \
		$(MAKE) ensure-clean; \
		$(MAKE) merge-release; \
		$(MAKE) push-release; \
		$(MAKE) github-release; \
	else \
		echo "$(RED)Error: Failed to determine version$(RESET)"; exit 1; \
	fi; \
	trap - ERR; \
	echo "$(GREEN)🎉 Auto-release completed successfully!$(RESET)"


update-and-release: ## 🚀 Update version, then run auto-release (alias: ur)
	@echo "$(BLUE)📝 Updating version, then starting auto-release...$(RESET)"
	$(MAKE) help-md
	$(MAKE) update-version
	$(MAKE) auto-release

ur: update-and-release ## 🚀 Alias for 'update-and-release'

# Merge release branch
merge-release: ensure-clean ## 🔄 Merge release branch to main branches
	@echo "$(BLUE)🔄 Merging release branch...$(RESET)"
	@CUR_BRANCH=$$(git rev-parse --abbrev-ref HEAD); \
	if ! echo "$$CUR_BRANCH" | grep -q "^release/"; then \
		echo "$(RED)Error: Not on a release branch. Current branch: $$CUR_BRANCH$(RESET)" >&2; \
		exit 1; \
	fi; \
	echo "$(BLUE)Merging to main...$(RESET)"; \
    $(call RESET_TO_REMOTE,$(MAIN_BRANCH)) && \
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
	@$(call colorecho, 🔥 Starting hotfix branch...)
	@if [ -z "$(HOTFIX_NAME)" ]; then \
		$(call fail, HOTFIX_NAME is required. Usage: make start-hotfix HOTFIX_NAME=fix-critical-bug); \
		exit 1; \
	fi; \
    $(call RESET_TO_REMOTE,$(MAIN_BRANCH)); \
	git checkout -b hotfix/$(HOTFIX_NAME) $(MAIN_BRANCH); \
	$(call success, Created hotfix branch 'hotfix/$(HOTFIX_NAME)')

finish-hotfix: ## 🚀 Finish hotfix (merge to main and develop)
	@$(call colorecho, 🔥 Finishing hotfix...)
	@CUR_BRANCH=$$(git rev-parse --abbrev-ref HEAD); \
	if ! echo "$$CUR_BRANCH" | grep -q "^hotfix/"; then \
		$(call fail, You must be on a 'hotfix/*' branch); \
		exit 1; \
	fi; \
	HOTFIX_NAME=$$(echo "$$CUR_BRANCH" | sed 's/hotfix\///'); \
	$(call colorecho, Merging $$CUR_BRANCH into $(MAIN_BRANCH)...); \
	git checkout $(MAIN_BRANCH); \
	git pull origin $(MAIN_BRANCH); \
	git merge --no-ff $$CUR_BRANCH; \
	$(call colorecho, Merging $$CUR_BRANCH into $(DEVELOP_BRANCH)...); \
    $(call RESET_TO_REMOTE,$(DEVELOP_BRANCH)); \
	git merge --no-ff $$CUR_BRANCH; \
	$(call colorecho, Pushing changes...); \
	git push origin $(MAIN_BRANCH); \
	git push origin $(DEVELOP_BRANCH); \
	git branch -d $$CUR_BRANCH; \
	$(call success, Hotfix '$$HOTFIX_NAME' completed)

git-log:  ## 📜 Graph + oneline with date/author (GIT_TARGET=..., COUNT=N, LOG_DATE=..., GRAPH=true)
	@GDIR="$(GIT_INFO_DIR)"; \
	if [ ! -d "$$GDIR/.git" ]; then \
		echo "$(RED)Error: $$GDIR is not a git repository$(RESET)"; exit 1; \
	fi; \
	echo "$(CYAN)Git target: $(GIT_TARGET) → $$GDIR$(RESET)"; \
	cd "$$GDIR"; \
	COUNT_FROM_MAKE='$(COUNT)'; \
	LOG_DATE_FROM_MAKE='$(LOG_DATE)'; \
	GRAPH_FROM_MAKE='$(GRAPH)'; \
	COUNT_OPT=$${COUNT_FROM_MAKE:-10}; \
	LOG_DATE_OPT=$${LOG_DATE_FROM_MAKE:-short}; \
	GRAPH_OPT=$${GRAPH_FROM_MAKE:-true}; \
	if [ "$$GRAPH_OPT" = "true" ]; then \
		echo "$(BLUE)📜 Git Log (last $$COUNT_OPT commits, date=$$LOG_DATE_OPT, graph)$(RESET)"; \
	else \
		echo "$(BLUE)📜 Git Log (last $$COUNT_OPT commits, date=$$LOG_DATE_OPT)$(RESET)"; \
	fi; \
	echo "$(YELLOW)Hint: make git-log GIT_TARGET=source COUNT=100 LOG_DATE=relative GRAPH=false$(RESET)"; \
	if echo "$$LOG_DATE_OPT" | grep -q '^format:'; then \
		DATE_ARG=$$(printf "%s" "$$LOG_DATE_OPT" | sed 's/^format://'); \
		DATE_FLAG="--date=format:$$DATE_ARG"; \
	else \
		DATE_FLAG="--date=$$LOG_DATE_OPT"; \
	fi; \
	if [ "$$GRAPH_OPT" = "true" ]; then \
		$(GIT_COMMAND) log --graph --decorate --color=always -n $$COUNT_OPT $$DATE_FLAG \
		  --pretty=format:"$(YELLOW)%h$(RESET) $(GREEN)%ad$(RESET) $(BLUE)%an$(RESET) %C(auto)%d$(RESET) %s"; \
	else \
		$(GIT_COMMAND) log --decorate --color=always -n $$COUNT_OPT $$DATE_FLAG \
		  --pretty=format:"$(YELLOW)%h$(RESET) $(GREEN)%ad$(RESET) $(BLUE)%an$(RESET) %C(auto)%d$(RESET) %s"; \
	fi
	  
save-git-info: print-git-dir ## 🔧 Save git state to .git-info.json (GIT_TARGET=project|source|system)
	@GDIR="$(GIT_INFO_DIR)"; \
	if [ ! -d "$$GDIR/.git" ]; then \
		echo "$(RED)Error: $$GDIR is not a git repository$(RESET)"; exit 1; \
	fi; \
	echo "$(BLUE)💾 Saving git information from $(GIT_TARGET) ($$GDIR) to .git-info.json...$(RESET)"; \
	cd "$$GDIR"; \
	COMMIT_SHA=$$($(GIT_COMMAND) rev-parse HEAD 2>/dev/null || echo "unknown"); \
	COMMIT_SHORT=$$($(GIT_COMMAND) rev-parse --short HEAD 2>/dev/null || echo "unknown"); \
	BRANCH=$$($(GIT_COMMAND) rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown"); \
	COMMIT_DATE=$$($(GIT_COMMAND) log -1 --format=%cd --date=iso 2>/dev/null || echo "unknown"); \
	COMMIT_AUTHOR=$$($(GIT_COMMAND) log -1 --format=%an 2>/dev/null || echo "unknown"); \
	COMMIT_MESSAGE=$$($(GIT_COMMAND) log -1 --format=%s 2>/dev/null | sed 's/"/\\"/g' || echo "unknown"); \
	TAG=$$($(GIT_COMMAND) describe --tags --exact-match 2>/dev/null || echo ""); \
	REMOTE_URL=$$($(GIT_COMMAND) remote get-url origin 2>/dev/null || echo ""); \
	DIRTY=$$($(GIT_COMMAND) diff --quiet 2>/dev/null && echo "false" || echo "true"); \
	cd - >/dev/null; \
	printf '{\n' > .git-info.json; \
	printf '  "gitTarget": "%s",\n' "$(GIT_TARGET)" >> .git-info.json; \
	printf '  "commitSha": "%s",\n' "$$COMMIT_SHA" >> .git-info.json; \
	printf '  "commitShort": "%s",\n' "$$COMMIT_SHORT" >> .git-info.json; \
	printf '  "branch": "%s",\n' "$$BRANCH" >> .git-info.json; \
	printf '  "commitDate": "%s",\n' "$$COMMIT_DATE" >> .git-info.json; \
	printf '  "commitAuthor": "%s",\n' "$$COMMIT_AUTHOR" >> .git-info.json; \
	printf '  "commitMessage": "%s",\n' "$$COMMIT_MESSAGE" >> .git-info.json; \
	printf '  "tag": "%s",\n' "$$TAG" >> .git-info.json; \
	printf '  "remoteUrl": "%s",\n' "$$REMOTE_URL" >> .git-info.json; \
	printf '  "dirty": %s,\n' "$$DIRTY" >> .git-info.json; \
	printf '  "buildDate": "%s"\n' "$$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> .git-info.json; \
	printf '}\n' >> .git-info.json; \
	echo "$(GREEN)✅ Git info saved to .git-info.json$(RESET)"; \
	cat .git-info.json