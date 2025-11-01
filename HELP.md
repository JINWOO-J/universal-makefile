
📋 Universal Makefile System v1.0.186
Project: universal-makefile vv1.0.186
Repository: jinwoo/universal-makefile
Current Branch: develop
Environment: development
Show Source:  Makefile project.mk makefiles/core.mk makefiles/colors.mk makefiles/help.mk makefiles/version.mk makefiles/colors.mk makefiles/docker.mk makefiles/compose.mk makefiles/git-flow.mk makefiles/colors.mk makefiles/cleanup.mk

🎯 Main Build Targets:
  all                  Build everything (env + version + build)  [Makefile]
  build                Build the Docker image  [docker.mk]
  build-clean          Build without cache  [docker.mk]
  build-local          Build locally without any cache (for testing)  [docker.mk]
  build-legacy         Build the Docker image  [docker.mk]
  build-multi          Build multi-platform image (amd64, arm64)  [docker.mk]

🚀 Release & Deploy:
  release              Full release process (build + push + tag latest)  [Makefile]
  tag-latest           Tag image as 'latest' and push  [docker.mk]
  push                 Push image to registry  [docker.mk]
  build-push           Build then push  [docker.mk]
  push-latest          Push 'latest' tag only  [docker.mk]
  publish-all          Publish versioned + latest  [docker.mk]
  up                   Start services (자동으로 .env 갱신 체크)	  [compose.mk]
  bump-and-push-tag-remote One-shot: compute next (remote) + create + push (BUMP=patch|minor|major)  [git-flow.mk]
  finish-release       Complete release process (merge to main and develop, create tag)  [git-flow.mk]
  auto-release         Automated release process  [git-flow.mk]
  update-and-release   Update version, then run auto-release (alias: ur)  [git-flow.mk]
  ur                   Alias for 'update-and-release'  [git-flow.mk]
  finish-hotfix        Finish hotfix (merge to main and develop)  [git-flow.mk]

🌿 Git Workflow:
  ensure-clean         Ensure clean working directory  [git-flow.mk]
  git-status           Show comprehensive git status  [git-flow.mk]
  git-branches         Show all branches with status  [git-flow.mk]
  sync-develop         Sync current branch to develop branch  [git-flow.mk]
  push-all-branches    Push all local branches to remote ($(REMOTE))  [git-flow.mk]
  start-release        Start new release branch from develop  [git-flow.mk]
  list-old-branches    List merged release branches that can be deleted  [git-flow.mk]
  check-git-repo       Check if current directory is a git repository  [git-flow.mk]
  ensure-develop-branch Ensure develop branch exists  [git-flow.mk]
  get-release-version  Get release version  [git-flow.mk]
  create-release-branch Create release branch  [git-flow.mk]
  push-release-branch  Push current release branch to origin  [git-flow.mk]
  start-hotfix         Start hotfix branch from main  [git-flow.mk]

🔧 Development & Debug:
  update-makefile-system Update makefile system  [Makefile]
  show-makefile-info   Show makefile system information  [Makefile]
  check-deps           Check if required tools are installed  [core.mk]
  check-docker         Check if Docker is running  [core.mk]
  check-git-clean      Check if working directory is clean  [core.mk]
  debug-vars           Show all Makefile variables in a structured way  [core.mk]
  install-workflow     워크플로우 설치 (사용법: make install-workflow WORKFLOW=파일명)  [core.mk]
  help-git             Git workflow commands help (auto, grouped)  [help.mk]
  help-compose         Docker Compose commands help (auto, grouped)  [help.mk]
  help-cleanup         Cleanup commands help (auto, grouped)  [help.mk]
  help-version         Version management commands help (auto, grouped)  [help.mk]
  help-env             Environment variable helpers help (auto, grouped)  [help.mk]
  help-system          Installer/system commands help (auto, grouped)  [help.mk]
  list-targets         List all available targets  [help.mk]
  search-targets       Search targets by keyword (usage: make search-targets KEYWORD=docker)  [help.mk]
  help-md              Generate help.md file  [help.mk]
  version-info         Show version information  [help.mk]
  getting-started      Show getting started guide  [help.mk]
  show-version         Show current version	  [version.mk]
  print-env            환경 변수 출력 (SILENT_MODE=1로 로그 숨김 가능)  [version.mk]
  print-env-quiet      환경 변수 출력 (로그 없이)  [version.mk]
  uv                   Update version (shortcut)  [version.mk]
  update-version       Bump & sync from project.mk VERSION (prefix-aware)  [version.mk]
  version-sync-ts      Sync version.ts placeholders (@VERSION, @VERSION_DETAIL, @VERSION_NAME)  [version.mk]
  version-tag          Create version tag without release  [version.mk]
  push-tags            Push all tags to remote  [version.mk]
  delete-tag           Delete version tag (usage: make delete-tag TAG=v1.0.0)	  [version.mk]
  version-changelog    Generate changelog since last version  [version.mk]
  version-release-notes Generate release notes for current version  [version.mk]
  version-compare      Compare current version with remote tags  [version.mk]
  version-next         Show what the next version would be  [version.mk]
  version-patch        Bump patch version and create tag  [version.mk]
  version-minor        Bump minor version and create tag  [version.mk]
  version-major        Bump major version and create tag  [version.mk]
  bump-from-project    Bump from project.mk VERSION and update all files  [version.mk]
  validate-version     Validate version format  [version.mk]
  check-version-consistency Check version consistency across files  [version.mk]
  um-version           Show UMF version (installed/pinned/bootstrap)  [version.mk]
  um-check             Check UMF version sync with pinned  [version.mk]
  export-version-info  Export version information to file  [version.mk]
  version-help         Show version management help  [version.mk]
  ensure-source        소스 코드 확인 및 자동 fetch (UMF_MODE=global일 때, SKIP_FETCH=true로 비활성화 가능)  [docker.mk]
  bash                 Run bash in the container  [docker.mk]
  run                  Run the container interactively  [docker.mk]
  exec                 Execute command in running container  [docker.mk]
  docker-info          Show Docker and image information  [docker.mk]
  docker-logs          Show Docker container logs  [docker.mk]
  up-force             Start services (.env 강제 갱신)  [compose.mk]
  up-quick             Start services (.env 갱신 없이 빠른 시작)  [compose.mk]
  restart              Restart services for the current ENV  [compose.mk]
  rebuild              Rebuild services for the current ENV  [compose.mk]
  dev-up               Start development environment  [compose.mk]
  dev-down             Stop development environment  [compose.mk]
  dev-restart          Restart development environment  [compose.mk]
  dev-logs             Show development environment logs  [compose.mk]
  logs                 Show service logs  [compose.mk]
  logs-tail            Show last 100 lines of logs  [compose.mk]
  dev-status           Show development services status  [compose.mk]
  exec-service         특정 서비스에서 명령어 실행 (사용법: make exec-service SERVICE=web COMMAND="ls -la")  [compose.mk]
  restart-service      특정 서비스 재시작 (사용법: make restart-service SERVICE=web)  [compose.mk]
  logs-service         특정 서비스 로그 보기 (사용법: make logs-service SERVICE=web)  [compose.mk]
  scale                Scale services (usage: make scale SERVICE=web REPLICAS=3)  [compose.mk]
  health-check         Check health of all services  [compose.mk]
  compose-test         Run compose-based tests  [compose.mk]
  backup-volumes       Backup Docker volumes  [compose.mk]
  compose-config       Show resolved Docker Compose configuration  [compose.mk]
  compose-images       Show images used by compose services  [compose.mk]
  git-fetch            소스 코드 가져오기 (사용법: make git-fetch SOURCE_REPO=owner/repo REF=main)  [git-flow.mk]
  bump-version         Bump version (patch by default)  [git-flow.mk]
  bump-minor           Bump minor version  [git-flow.mk]
  bump-major           Bump major version  [git-flow.mk]

🧹 Cleanup & Utils:
  docker-clean         Clean Docker resources (containers, images, volumes)  [docker.mk]
  docker-deep-clean    Deep clean Docker (DANGEROUS - removes all unused resources)  [docker.mk]
  clear-build-cache    Clear Docker build cache  [docker.mk]
  compose-clean        Clean Docker Compose resources  [compose.mk]
  clean-old-branches   Delete merged release branches (CAREFUL!)  [git-flow.mk]
  clean-remote-branches Delete merged remote release branches (VERY CAREFUL!)  [git-flow.mk]
  push-release-clean   Also delete remote release/* branch (optional)  [git-flow.mk]
  cleanup              Clean temporary files and safe cleanup  [cleanup.mk]
  clean-temp           Clean temporary files  [cleanup.mk]
  clean-logs           Clean log files  [cleanup.mk]
  clean-cache          Clean cache files and directories  [cleanup.mk]
  clean-build          Clean build artifacts  [cleanup.mk]
  env-clean            Clean environment files  [cleanup.mk]
  clean-node           Clean Node.js specific files  [cleanup.mk]
  clean-python         Clean Python specific files  [cleanup.mk]
  clean-ide            Clean IDE and editor files  [cleanup.mk]
  clean-test           Clean test artifacts  [cleanup.mk]
  clean-recursively    Clean recursively in all subdirectories  [cleanup.mk]
  clean-secrets        Clean potential secret files (BE CAREFUL!)  [cleanup.mk]

📖 Detailed Help:
  make help-docker     Docker-related commands
  make help-git        Git workflow commands
  make help-compose    Docker Compose commands
  make help-cleanup    Cleanup commands
  make help-version    Version management commands
  make help-env        Environment variables helpers
  make help-system     Installer/system commands

💡 Usage Examples:
  make build VERSION=v2.0 DEBUG=true
  make auto-release
  make clean-old-branches
  make help-docker
