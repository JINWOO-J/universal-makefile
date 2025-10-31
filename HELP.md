
📋 Universal Makefile System v1.0.176(B
Project: universal-makefile vv1.0.176(B
Repository: jinwoo/universal-makefile(B
Current Branch: develop(B
Environment: development(B
Show Source:  Makefile project.mk makefiles/core.mk makefiles/colors.mk makefiles/help.mk makefiles/version.mk makefiles/colors.mk makefiles/docker.mk makefiles/compose.mk makefiles/git-flow.mk makefiles/colors.mk makefiles/cleanup.mk(B

🎯 Main Build Targets:(B
  all                 (B Build everything (env + version + build)  [Makefile]
  build               (B Build the Docker image  [docker.mk]
  build-clean         (B Build without cache  [docker.mk]
  build-local         (B Build locally without any cache (for testing)  [docker.mk]
  build-legacy        (B Build the Docker image  [docker.mk]
  build-multi         (B Build multi-platform image (amd64, arm64)  [docker.mk]

🚀 Release & Deploy:(B
  release             (B Full release process (build + push + tag latest)  [Makefile]
  tag-latest          (B Tag image as 'latest' and push  [docker.mk]
  push                (B Push image to registry  [docker.mk]
  build-push          (B Build then push  [docker.mk]
  push-latest         (B Push 'latest' tag only  [docker.mk]
  publish-all         (B Publish versioned + latest  [docker.mk]
  up                  (B Start services (자동으로 .env 갱신 체크)	  [compose.mk]
  bump-and-push-tag-remote(B One-shot: compute next (remote) + create + push (BUMP=patch|minor|major)  [git-flow.mk]
  finish-release      (B Complete release process (merge to main and develop, create tag)  [git-flow.mk]
  auto-release        (B Automated release process  [git-flow.mk]
  update-and-release  (B Update version, then run auto-release (alias: ur)  [git-flow.mk]
  ur                  (B Alias for 'update-and-release'  [git-flow.mk]
  finish-hotfix       (B Finish hotfix (merge to main and develop)  [git-flow.mk]

🌿 Git Workflow:(B
  ensure-clean        (B Ensure clean working directory  [git-flow.mk]
  git-status          (B Show comprehensive git status  [git-flow.mk]
  git-branches        (B Show all branches with status  [git-flow.mk]
  sync-develop        (B Sync current branch to develop branch  [git-flow.mk]
  push-all-branches   (B Push all local branches to remote ($(REMOTE))  [git-flow.mk]
  start-release       (B Start new release branch from develop  [git-flow.mk]
  list-old-branches   (B List merged release branches that can be deleted  [git-flow.mk]
  check-git-repo      (B Check if current directory is a git repository  [git-flow.mk]
  ensure-develop-branch(B Ensure develop branch exists  [git-flow.mk]
  get-release-version (B Get release version  [git-flow.mk]
  create-release-branch(B Create release branch  [git-flow.mk]
  push-release-branch (B Push current release branch to origin  [git-flow.mk]
  start-hotfix        (B Start hotfix branch from main  [git-flow.mk]

🔧 Development & Debug:(B
  update-makefile-system(B Update makefile system  [Makefile]
  show-makefile-info  (B Show makefile system information  [Makefile]
  check-deps          (B Check if required tools are installed  [core.mk]
  check-docker        (B Check if Docker is running  [core.mk]
  check-git-clean     (B Check if working directory is clean  [core.mk]
  debug-vars          (B Show all Makefile variables in a structured way  [core.mk]
  help-git            (B Git workflow commands help (auto, grouped)  [help.mk]
  help-compose        (B Docker Compose commands help (auto, grouped)  [help.mk]
  help-cleanup        (B Cleanup commands help (auto, grouped)  [help.mk]
  help-version        (B Version management commands help (auto, grouped)  [help.mk]
  help-env            (B Environment variable helpers help (auto, grouped)  [help.mk]
  help-system         (B Installer/system commands help (auto, grouped)  [help.mk]
  list-targets        (B List all available targets  [help.mk]
  search-targets      (B Search targets by keyword (usage: make search-targets KEYWORD=docker)  [help.mk]
  help-md             (B Generate help.md file  [help.mk]
  version-info        (B Show version information  [help.mk]
  getting-started     (B Show getting started guide  [help.mk]
  show-version        (B Show current version	  [version.mk]
  uv                  (B Update version (shortcut)  [version.mk]
  update-version      (B Bump & sync from project.mk VERSION (prefix-aware)  [version.mk]
  version-sync-ts     (B Sync version.ts placeholders (@VERSION, @VERSION_DETAIL, @VERSION_NAME)  [version.mk]
  version-tag         (B Create version tag without release  [version.mk]
  push-tags           (B Push all tags to remote  [version.mk]
  delete-tag          (B Delete version tag (usage: make delete-tag TAG=v1.0.0)	  [version.mk]
  version-changelog   (B Generate changelog since last version  [version.mk]
  version-release-notes(B Generate release notes for current version  [version.mk]
  version-compare     (B Compare current version with remote tags  [version.mk]
  version-next        (B Show what the next version would be  [version.mk]
  version-patch       (B Bump patch version and create tag  [version.mk]
  version-minor       (B Bump minor version and create tag  [version.mk]
  version-major       (B Bump major version and create tag  [version.mk]
  bump-from-project   (B Bump from project.mk VERSION and update all files  [version.mk]
  validate-version    (B Validate version format  [version.mk]
  check-version-consistency(B Check version consistency across files  [version.mk]
  um-version          (B Show UMF version (installed/pinned/bootstrap)  [version.mk]
  um-check            (B Check UMF version sync with pinned  [version.mk]
  export-version-info (B Export version information to file  [version.mk]
  version-help        (B Show version management help  [version.mk]
  bash                (B Run bash in the container  [docker.mk]
  run                 (B Run the container interactively  [docker.mk]
  exec                (B Execute command in running container  [docker.mk]
  docker-info         (B Show Docker and image information  [docker.mk]
  docker-logs         (B Show Docker container logs  [docker.mk]
  up-force            (B Start services (.env 강제 갱신)  [compose.mk]
  up-quick            (B Start services (.env 갱신 없이 빠른 시작)  [compose.mk]
  restart             (B Restart services for the current ENV  [compose.mk]
  rebuild             (B Rebuild services for the current ENV  [compose.mk]
  dev-up              (B Start development environment  [compose.mk]
  dev-down            (B Stop development environment  [compose.mk]
  dev-restart         (B Restart development environment  [compose.mk]
  dev-logs            (B Show development environment logs  [compose.mk]
  logs                (B Show service logs  [compose.mk]
  logs-tail           (B Show last 100 lines of logs  [compose.mk]
  dev-status          (B Show development services status  [compose.mk]
  exec-service        (B 특정 서비스에서 명령어 실행 (사용법: make exec-service SERVICE=web COMMAND="ls -la")  [compose.mk]
  restart-service     (B 특정 서비스 재시작 (사용법: make restart-service SERVICE=web)  [compose.mk]
  logs-service        (B 특정 서비스 로그 보기 (사용법: make logs-service SERVICE=web)  [compose.mk]
  scale               (B Scale services (usage: make scale SERVICE=web REPLICAS=3)  [compose.mk]
  health-check        (B Check health of all services  [compose.mk]
  compose-test        (B Run compose-based tests  [compose.mk]
  backup-volumes      (B Backup Docker volumes  [compose.mk]
  compose-config      (B Show resolved Docker Compose configuration  [compose.mk]
  compose-images      (B Show images used by compose services  [compose.mk]
  bump-version        (B Bump version (patch by default)  [git-flow.mk]
  bump-minor          (B Bump minor version  [git-flow.mk]
  bump-major          (B Bump major version  [git-flow.mk]

🧹 Cleanup & Utils:(B
  docker-clean        (B Clean Docker resources (containers, images, volumes)  [docker.mk]
  docker-deep-clean   (B Deep clean Docker (DANGEROUS - removes all unused resources)  [docker.mk]
  clear-build-cache   (B Clear Docker build cache  [docker.mk]
  compose-clean       (B Clean Docker Compose resources  [compose.mk]
  clean-old-branches  (B Delete merged release branches (CAREFUL!)  [git-flow.mk]
  clean-remote-branches(B Delete merged remote release branches (VERY CAREFUL!)  [git-flow.mk]
  push-release-clean  (B Also delete remote release/* branch (optional)  [git-flow.mk]
  clean               (B Clean temporary files and safe cleanup  [cleanup.mk]
  clean-temp          (B Clean temporary files  [cleanup.mk]
  clean-logs          (B Clean log files  [cleanup.mk]
  clean-cache         (B Clean cache files and directories  [cleanup.mk]
  clean-build         (B Clean build artifacts  [cleanup.mk]
  env-clean           (B Clean environment files  [cleanup.mk]
  clean-node          (B Clean Node.js specific files  [cleanup.mk]
  clean-python        (B Clean Python specific files  [cleanup.mk]
  clean-ide           (B Clean IDE and editor files  [cleanup.mk]
  clean-test          (B Clean test artifacts  [cleanup.mk]
  clean-recursively   (B Clean recursively in all subdirectories  [cleanup.mk]
  clean-secrets       (B Clean potential secret files (BE CAREFUL!)  [cleanup.mk]

📖 Detailed Help:(B
  make help-docker(B     Docker-related commands
  make help-git(B        Git workflow commands
  make help-compose(B    Docker Compose commands
  make help-cleanup(B    Cleanup commands
  make help-version(B    Version management commands
  make help-env(B        Environment variables helpers
  make help-system(B     Installer/system commands

💡 Usage Examples:(B
  make build VERSION=v2.0 DEBUG=true
  make auto-release
  make clean-old-branches
  make help-docker
