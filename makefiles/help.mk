# ================================================================
# Help System and Documentation
# ================================================================
CAT_MAIN   := 🎯
CAT_RELEASE:= 🚀
CAT_GIT    := 🌿
CAT_DEV    := 🔧
CAT_CLEAN  := 🧹

.PHONY: help list-targets help-docker help-git help-compose help-cleanup help-version help-env help-system

# ================================================================
# 메인 Help 시스템
# ================================================================

help: ## 🏠 Show this help message
	@echo ""
	@echo "$(BLUE)📋 Universal Makefile System $(VERSION)$(RESET)"
	@echo "$(BLUE)Project: $(NAME) v$(VERSION)$(RESET)"
	@echo "$(BLUE)Repository: $(REPO_HUB)/$(NAME)$(RESET)"
	@echo "$(BLUE)Current Branch: $(CURRENT_BRANCH)$(RESET)"
	@echo "$(BLUE)Environment: $(ENV)$(RESET)"
	@echo "$(BLUE)Show Source: $(MAKEFILE_LIST)$(RESET)"
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
	@echo "  $(GREEN)make help-version$(RESET)    Version management commands"  
	@echo "  $(GREEN)make help-env$(RESET)        Environment variables helpers" 
	@echo "  $(GREEN)make help-system$(RESET)     Installer/system commands"
	@echo "  $(GREEN)make help-bg$(RESET)         Blue/Green deployment commands" 
	@echo ""
	@echo "$(BLUE)💡 Usage Examples:$(RESET)"
	@echo "  make build VERSION=v2.0 DEBUG=true"
	@echo "  make auto-release"
	@echo "  make clean-old-branches"
	@echo "  make help-docker"

# 내부 함수: 카테고리별 타겟 표시
# _show-category:
# 	@grep -h -E '^[a-zA-Z0-9_.-]+:.*?## $(CATEGORY).*$$' $(MAKEFILE_LIST) | \
# 		sort | \
# 		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-20s$(RESET) %s\n", $$1, substr($$2, 3)}'


_show-category:
	@awk -v cat="$(CATEGORY)" -v GREEN="$(GREEN)" -v RESET="$(RESET)" 'function base(p,a,n){n=split(p,a,"/");return a[n]} /^[A-Za-z0-9_.-]+:[[:space:]].*##[[:space:]]/ { line=$$0; pos=index(line,"## "); if(!pos) next; comment=substr(line,pos+3); if(index(comment,cat)==0) next; split(line,parts,":"); t=parts[1]; if(index(comment,cat)==1){ desc=substr(comment,length(cat)+1); sub(/^[[:space:]]+/,"",desc) } else { desc=comment } printf("  %s%-20s%s %s  [%s]\n", GREEN, t, RESET, desc, base(FILENAME)) }' $(MAKEFILE_LIST)

# Find which file defines a specific target (usage: make where TARGET=<name>)
.PHONY: where
where:
	@awk -v tgt="$(TARGET)" 'function base(p,a,n){n=split(p,a,"/");return a[n]} /^[A-Za-z0-9_.-]+:[[:space:]]/ { split($$0,p,":"); if(p[1]==tgt) print "• " tgt "  ->  " base(FILENAME) }' $(MAKEFILE_LIST)


# Start of Selection
# One-liner version without awk
# End of Selection
# _show-files-grouped:
# 	@awk -v list="$(FILES)" -v groups="$(GROUPS)" -v green="$(GREEN)" -v yellow="$(YELLOW)" -v reset="$(RESET)" -v show="$(SHOW_SOURCE)" 'function base(p,a,n){n=split(p,a,"/");return a[n]} function trim(s){sub(/^[[:space:]]+/,"",s);sub(/[[:space:]]+$$/,"",s);return s} BEGIN{ng=split(groups,G,"|");for(i=1;i<=ng;i++){split(G[i],kv,":");ord[i]=kv[1];lab[kv[1]]=kv[2]} m=split(list,L,",");for(i=1;i<=m;i++){x=L[i];sub(/^[[:space:]]+/,"",x);sub(/[[:space:]]+$$/,"",x);allow[x]=1}} /^[A-Za-z0-9_.-]+:[[:space:]].*##[[:space:]]/ {line=$$0;pos=index(line,"## ");if(!pos)next;c=substr(line,pos+3);split(line,p,":");t=p[1];f=base(FILENAME);if(!(f in allow))next; d=(f=="docker.mk")?"docker":(f=="compose.mk")?"compose":(f=="git-flow.mk")?"git":(f=="version.mk"||f=="version-check.mk")?"version":(f=="cleanup.mk")?"cleanup":(f=="core.mk")?"core":"other"; g="";for(i=1;i<=ng;i++){tag="[" ord[i] "]";if(index(c,tag)>0){g=ord[i];break}} if(g==""){ if(d=="docker"){ if(t=="build"||index(t,"build-")==1||t=="push"||t=="tag-latest")g="build"; else if(t=="bash"||t=="run"||t=="exec"||t=="docker-logs")g="dev"; else if(index(t,"docker-")==1||index(t,"image-")==1||t=="security-scan"||t=="clear-build-cache")g="mgmt"; else g="other"; } else if(d=="compose"){ if(t=="up"||t=="down"||t=="restart"||t=="rebuild"||t=="dev-up"||t=="dev-down"||t=="dev-restart")g="ops"; else if(t=="logs"||t=="logs-tail"||t=="dev-logs"||t=="status"||t=="dev-status"||t=="health-check")g="monitor"; else if(t=="exec-service"||t=="restart-service"||t=="logs-service"||t=="scale")g="service"; else if(t=="compose-config"||t=="compose-images")g="inspect"; else if(t=="compose-clean"||t=="compose-test"||t=="backup-volumes")g="maint"; else g="other"; } else if(d=="git"){ if(index(t,"start-release")==1||index(t,"finish-release")==1||index(t,"merge-release")==1||index(t,"push-release")==1||t=="create-release-branch"||t=="push-release-branch"||t=="github-release"||t=="auto-release"||t=="update-and-release"||t=="ur")g="release"; else if(index(t,"start-hotfix")==1||index(t,"finish-hotfix")==1)g="hotfix"; else if(index(t,"git-")==1||t=="sync-develop"||t=="git-status"||t=="git-branches")g="branch"; else g="other"; } else if(d=="version"){ if(t=="version"||t=="update-version"||t=="update-version-file"||t=="version-next")g="show"; else if(t=="version-tag"||t=="push-tags"||t=="delete-tag")g="tagging"; else if(t=="version-changelog"||t=="version-release-notes")g="notes"; else if(t=="version-patch"||t=="version-minor"||t=="version-major")g="semver"; else if(t=="validate-version"||t=="check-version-consistency"||t=="export-version-info")g="validate"; else g="other"; } else if(d=="cleanup"){ if(t=="clean"||t=="clean-temp"||t=="clean-logs"||t=="clean-cache"||t=="clean-build"||t=="env-clean")g="project"; else if(t=="clean-node"||t=="clean-python"||t=="clean-java")g="lang"; else if(t=="clean-ide"||t=="clean-test"||t=="clean-recursively"||t=="clean-secrets")g="ide"; else if(index(t,"docker-")==1)g="docker"; else g="other"; } else if(d=="core"){ if(index(t,"env-")==1){ if(t=="env-keys"||t=="env-get"||t=="env-show")g="query"; else if(t=="env-pretty"||t=="env-github")g="format"; else if(t=="env-file")g="file"; else g="other"; } else if(index(t,"self-")==1){ if(t=="self-app")g="app"; else g="installer"; } else g="other"; } else { g="other"; } } for(i=1;i<=ng;i++){tag="[" ord[i] "]";while((s=index(c,tag))>0){c=substr(c,1,s-1) substr(c,s+length(tag))}} desc=trim(c); n[g]++;T[g,n[g]]=t;D[g,n[g]]=desc;F[g,n[g]]=f;if(length(t)>W[g])W[g]=length(t) } END{for(ii=1;ii<=ng;ii++){k=ord[ii];if(n[k]>0){printf("%s%s:%s\n",yellow,lab[k],reset);for(i=1;i<=n[k];i++){if(show=="true"||show=="1")printf("  %s%-*s%s %s  [%s]\n",green,W[k]+2,T[k,i],reset,D[k,i],F[k,i]);else printf("  %s%-*s%s %s\n",green,W[k]+2,T[k,i],reset,D[k,i])}printf("\n")}} }' $(MAKEFILE_LIST)

# include makefiles/show_grouped.awk
_show-files-grouped:
	@awk \
	  -v list="$(FILES)" \
	  -v groups="$(GROUPS)" \
	  -v show="$(SHOW_SOURCE)" \
	  -v green="$(GREEN)" -v yellow="$(YELLOW)" -v reset="$(RESET)" \
	  -f $(MAKEFILE_DIR)/makefiles/show_grouped.awk \
	  $(MAKEFILE_LIST)

# ================================================================
# 상세 Help 시스템들
# ================================================================

help-docker:
	@echo ""
	@echo "$(BLUE)🐳 Docker Commands Help$(RESET)"
	@echo ""
	@$(MAKE) --no-print-directory _show-files-grouped \
		FILES="docker.mk,compose.mk" \
		GROUPS="build:Build & Registry|dev:Development|mgmt:Management|other:Other"
	@echo "$(BLUE)💡 Examples:$(RESET)"
	@echo "  make build DEBUG=true FORCE_REBUILD=true"
	@echo "  make build-multi     # Build for multiple architectures"
	@echo "  make bash           # Interactive shell in container"

help-git: ## 🔧 Git workflow commands help (auto, grouped)
	@echo ""
	@echo "$(BLUE)🌿 Git Workflow Commands Help$(RESET)"
	@echo ""
	@$(MAKE) --no-print-directory _show-files-grouped \
		FILES="git-flow.mk" \
		GROUPS="branch:Branch Management|release:Release Process|hotfix:Hotfix Support|other:Other"

help-compose: ## 🔧 Docker Compose commands help (auto, grouped)
	@echo ""
	@echo "$(BLUE)🐙 Docker Compose Commands Help$(RESET)"
	@echo ""
	@$(MAKE) --no-print-directory _show-files-grouped \
		FILES="compose.mk" \
		GROUPS="ops:Environment Management|monitor:Monitoring|service:Operations|inspect:Introspection|maint:Maintenance|other:Other"

help-cleanup: ## 🔧 Cleanup commands help (auto, grouped)
	@echo ""
	@echo "$(BLUE)🧹 Cleanup Commands Help$(RESET)"
	@echo ""
	@$(MAKE) --no-print-directory _show-files-grouped \
		FILES="cleanup.mk" \
		GROUPS="project:Project Cleanup|lang:Language-specific|ide:IDE/Test/Recursive|docker:Docker Cleanup|other:Other"

help-version: ## 🔧 Version management commands help (auto, grouped)
	@echo ""
	@echo "$(BLUE)🏷  Version Management Commands Help$(RESET)"
	@echo ""
	@$(MAKE) --no-print-directory _show-files-grouped \
		FILES="version.mk,version-check.mk" \
		GROUPS="show:Show/Update|tagging:Tagging|notes:Changelog/Notes|semver:Semver bump|validate:Validation|other:Other"

help-env: ## 🔧 Environment variable helpers help (auto, grouped)
	@echo ""
	@echo "$(BLUE)🌐 Environment Helpers$(RESET)"
	@echo ""
	@$(MAKE) --no-print-directory _show-files-grouped \
		FILES="core.mk,env-file.mk" \
		GROUPS="query:Query/Show|format:Formatting|file:Files|prepare:.env Preparation|other:Other"

help-system: ## 🔧 Installer/system commands help (auto, grouped)
	@echo ""
	@echo "$(BLUE)🧩 System/Installer Commands$(RESET)"
	@echo ""
	@$(MAKE) --no-print-directory _show-files-grouped \
		FILES="core.mk" \
		GROUPS="installer:Installer|app:App|other:Other"

help-bg: ## 🔧 Blue/Green deployment commands help
	@echo ""
	@echo "$(BLUE)🔵🟢 Blue/Green Deployment Commands$(RESET)"
	@echo ""
	@echo "$(YELLOW)Setup:$(RESET)"
	@echo "  $(GREEN)bg-init$(RESET)                Initialize BG deployment"
	@echo ""
	@echo "$(YELLOW)Version:$(RESET)"
	@echo "  $(GREEN)bg-version-set$(RESET)         Set version (VERSION=x.x.x)"
	@echo "  $(GREEN)bg-version-show$(RESET)        Show version & status"
	@echo ""
	@echo "$(YELLOW)Build:$(RESET)"
	@echo "  $(GREEN)bg-build$(RESET)               Build current version"
	@echo "  $(GREEN)bg-build-blue$(RESET)          Build blue"
	@echo "  $(GREEN)bg-build-green$(RESET)         Build green"
	@echo ""
	@echo "$(YELLOW)Deploy:$(RESET)"
	@echo "  $(GREEN)bg-deploy$(RESET)              Auto deploy (VERSION=x.x.x)"
	@echo "  $(GREEN)bg-deploy-blue$(RESET)         Deploy to blue"
	@echo "  $(GREEN)bg-deploy-green$(RESET)        Deploy to green"
	@echo "  $(GREEN)bg-deploy-prepare$(RESET)      Prepare inactive env"
	@echo "  $(GREEN)bg-deploy-switch$(RESET)       Switch traffic"
	@echo "  $(GREEN)bg-deploy-verify$(RESET)       Verify deployment"
	@echo ""
	@echo "$(YELLOW)Health:$(RESET)"
	@echo "  $(GREEN)bg-health$(RESET)              Check all"
	@echo "  $(GREEN)bg-health-blue$(RESET)         Check blue"
	@echo "  $(GREEN)bg-health-green$(RESET)        Check green"
	@echo "  $(GREEN)bg-health-proxy$(RESET)        Check proxy"
	@echo ""
	@echo "$(YELLOW)Rollback:$(RESET)"
	@echo "  $(GREEN)bg-rollback$(RESET)            Rollback to previous"
	@echo "  $(GREEN)bg-rollback-version$(RESET)    Rollback to VERSION=x.x.x"
	@echo "  $(GREEN)bg-rollback-history$(RESET)    Show history"
	@echo ""
	@echo "$(YELLOW)Monitor:$(RESET)"
	@echo "  $(GREEN)bg-status$(RESET)              Show status"
	@echo "  $(GREEN)bg-logs$(RESET)                All logs"
	@echo "  $(GREEN)bg-logs-blue$(RESET)           Blue logs"
	@echo "  $(GREEN)bg-logs-green$(RESET)          Green logs"
	@echo ""
	@echo "$(YELLOW)Clean:$(RESET)"
	@echo "  $(GREEN)bg-clean$(RESET)               Clean inactive"
	@echo "  $(GREEN)bg-clean-all$(RESET)           Clean all"
	@echo ""
	@echo "$(BLUE)💡 Examples:$(RESET)"
	@echo "  make bg-init                    # Initialize Blue/Green deployment"
	@echo "  make bg-deploy VERSION=1.0.1    # Deploy new version"
	@echo "  make bg-rollback                # Rollback to previous"
	@echo "  make bg-status                  # Check current status"
	@echo ""
	@echo "$(BLUE)📚 Configuration:$(RESET)"
	@echo "  Set $(GREEN)BG_ENABLED=true$(RESET) in project.mk to enable"
	@echo "  Run $(GREEN)make bg-init$(RESET) to create config files"
	@echo "  Edit config/bluegreen.conf for customization"

# ================================================================
# 타겟 검색 및 나열
# ================================================================

list-targets: ## 🔧 List all available targets
	@echo "$(BLUE)All Available Targets:$(RESET)"
	@$(MAKE) -qp | awk -F':' '/^[a-zA-Z0-9][^$$#\/\t=]*:([^=]|$$)/ {split($$1,A,/ /);for(i in A)print A[i]}' | sort -u

search-targets: ## 🔧 Search targets by keyword (usage: make search-targets KEYWORD=docker)
	@if [ -z "$(KEYWORD)" ]; then \
		$(call fail, KEYWORD is required. Usage: make search-targets KEYWORD=docker); \
		exit 1; \
	fi; \
	echo "$(BLUE)Targets matching '$(KEYWORD)':$(RESET)"; \
	grep -h -E '^[a-zA-Z0-9_.-]+:.*?##.*$(KEYWORD)' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-20s$(RESET) %s\n", $$1, $$2}' || \
		echo "  No targets found matching '$(KEYWORD)'"

# ================================================================
# 타겟별 상세 도움말
# ================================================================

help-md: ## 🔧 Generate help.md file
	@NO_COLOR=1 HELP_WIDTH=28 \
	$(MAKE) --no-print-directory help \
	| sed -E 's/\x1b\[[0-9;]*[mGKH]//g' | sed -E 's/\x1b\([B0]//g' > HELP.md
	@echo "Wrote HELP.md"

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

readme-embed-help: help-md
	@awk -v inc="HELP.md" '\
	  BEGIN { while ((getline l < inc) > 0) buf = buf l ORS; close(inc) } \
	  { \
	    if ($$0 ~ /<!-- BEGIN: HELP -->/) { print; print buf; skip=1; next } \
	    if ($$0 ~ /<!-- END: HELP -->/)   { print; skip=0; next } \
	    if (!skip) print \
	  }' README.md > README.md.tmp && mv README.md.tmp README.md
	@echo "README.md updated with docs/HELP.md ✅"


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