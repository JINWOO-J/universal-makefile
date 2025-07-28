# ================================================================
# Node.js Project Configuration Example
# ================================================================

# 프로젝트 기본 정보
REPO_HUB = mycompany
NAME = my-nodejs-app
VERSION = v1.0.0

# Git 브랜치 설정
MAIN_BRANCH = main
DEVELOP_BRANCH = develop

# Docker 설정
DOCKERFILE_PATH = Dockerfile
DOCKER_BUILD_ARGS = --build-arg NODE_ENV=production

# Docker Compose 설정
COMPOSE_FILE = docker-compose.yml
DEV_COMPOSE_FILE = docker-compose.dev.yml
PROD_COMPOSE_FILE = docker-compose.prod.yml

# 버전 관리 (Node.js는 package.json 사용)
VERSION_UPDATE_TOOL = yarn
VERSION_FILE = package.json

# 테스트 및 린트 설정
TEST_COMMAND = npm test
LINT_COMMAND = npm run lint

# 빌드 설정
BUILD_DIR = dist

# ================================================================
# Node.js 프로젝트별 커스텀 타겟들
# ================================================================

# npm/yarn 의존성 설치
install: ## 📦 Install Node.js dependencies
	@$(call colorecho, "📦 Installing Node.js dependencies...")
	@if [ -f "yarn.lock" ]; then \
		yarn install; \
	else \
		npm install; \
	fi
	@$(call success, "Dependencies installed")

# 개발 서버 시작
dev-server: ## 🚀 Start development server
	@$(call colorecho, "🚀 Starting development server...")
	@if [ -f "yarn.lock" ]; then \
		yarn dev; \
	else \
		npm run dev; \
	fi

# 프로덕션 빌드
build-assets: ## 🎨 Build production assets
	@$(call colorecho, "🎨 Building production assets...")
	@if [ -f "yarn.lock" ]; then \
		yarn build; \
	else \
		npm run build; \
	fi
	@$(call success, "Assets built successfully")

# 테스트 실행
test-unit: ## 🧪 Run unit tests
	@$(call colorecho, "🧪 Running unit tests...")
	@if [ -f "yarn.lock" ]; then \
		yarn test; \
	else \
		npm test; \
	fi

test-e2e: ## 🧪 Run end-to-end tests
	@$(call colorecho, "🧪 Running E2E tests...")
	@if [ -f "yarn.lock" ]; then \
		yarn test:e2e; \
	else \
		npm run test:e2e; \
	fi

# 코드 린팅
lint-fix: ## 🔧 Run linter and fix issues
	@$(call colorecho, "🔧 Running linter with auto-fix...")
	@if [ -f "yarn.lock" ]; then \
		yarn lint --fix; \
	else \
		npm run lint -- --fix; \
	fi

# 보안 감사
security-audit: ## 🔒 Run npm security audit
	@$(call colorecho, "🔒 Running security audit...")
	@if [ -f "yarn.lock" ]; then \
		yarn audit; \
	else \
		npm audit; \
	fi

# 의존성 업데이트
update-deps: ## 📦 Update dependencies
	@$(call colorecho, "📦 Updating dependencies...")
	@if [ -f "yarn.lock" ]; then \
		yarn upgrade-interactive; \
	else \
		npm update; \
	fi

# 프로덕션 배포 (예시)
deploy-prod: build-assets build test-unit ## 🚀 Deploy to production
	@$(call colorecho, "🚀 Deploying to production...")
	@# 여기에 실제 배포 로직 추가
	@# 예: pm2 deploy ecosystem.config.js production
	@# 예: docker push $(FULL_TAG) && kubectl apply -f k8s/
	@$(call success, "Deployed to production")