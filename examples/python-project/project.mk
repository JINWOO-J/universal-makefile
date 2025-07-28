# ================================================================
# Python Project Configuration Example
# ================================================================

# 프로젝트 기본 정보
REPO_HUB = mycompany
NAME = my-python-app
VERSION = v1.0.0

# Git 브랜치 설정
MAIN_BRANCH = main
DEVELOP_BRANCH = develop

# Docker 설정
DOCKERFILE_PATH = Dockerfile
DOCKER_BUILD_ARGS = --build-arg PYTHON_ENV=production

# Docker Compose 설정
COMPOSE_FILE = docker-compose.yml
DEV_COMPOSE_FILE = docker-compose.dev.yml
PROD_COMPOSE_FILE = docker-compose.prod.yml

# 버전 관리 (Poetry 사용)
VERSION_UPDATE_TOOL = poetry
VERSION_FILE = pyproject.toml

# 테스트 및 린트 설정
TEST_COMMAND = pytest
LINT_COMMAND = flake8

# 빌드 설정
BUILD_DIR = dist

# ================================================================
# Python 프로젝트별 커스텀 타겟들
# ================================================================

# 가상환경 및 의존성 설치
install: ## 📦 Install Python dependencies
	@$(call colorecho, "📦 Installing Python dependencies...")
	@if command -v poetry >/dev/null 2>&1; then \
		poetry install; \
	else \
		pip install -r requirements.txt; \
	fi
	@$(call success, "Dependencies installed")

# 개발 서버 시작
dev-server: ## 🚀 Start development server
	@$(call colorecho, "🚀 Starting development server...")
	@if command -v poetry >/dev/null 2>&1; then \
		poetry run python app/main.py; \
	else \
		python app/main.py; \
	fi

# 테스트 실행
test-unit: ## 🧪 Run unit tests with pytest
	@$(call colorecho, "🧪 Running unit tests...")
	@if command -v poetry >/dev/null 2>&1; then \
		poetry run pytest tests/ -v; \
	else \
		pytest tests/ -v; \
	fi

test-coverage: ## 🧪 Run tests with coverage report
	@$(call colorecho, "🧪 Running tests with coverage...")
	@if command -v poetry >/dev/null 2>&1; then \
		poetry run pytest --cov=app tests/ --cov-report=html; \
	else \
		pytest --cov=app tests/ --cov-report=html; \
	fi

# 코드 품질 검사
lint: ## 🔧 Run code linting
	@$(call colorecho, "🔧 Running linter...")
	@if command -v poetry >/dev/null 2>&1; then \
		poetry run flake8 app/ tests/; \
		poetry run black --check app/ tests/; \
		poetry run isort --check-only app/ tests/; \
	else \
		flake8 app/ tests/; \
		black --check app/ tests/; \
		isort --check-only app/ tests/; \
	fi

lint-fix: ## 🔧 Run linter and fix issues
	@$(call colorecho, "🔧 Running linter with auto-fix...")
	@if command -v poetry >/dev/null 2>&1; then \
		poetry run black app/ tests/; \
		poetry run isort app/ tests/; \
	else \
		black app/ tests/; \
		isort app/ tests/; \
	fi

# 타입 체크
type-check: ## 🔍 Run type checking with mypy
	@$(call colorecho, "🔍 Running type checker...")
	@if command -v poetry >/dev/null 2>&1; then \
		poetry run mypy app/; \
	else \
		mypy app/; \
	fi

# 보안 검사
security-audit: ## 🔒 Run security audit
	@$(call colorecho, "🔒 Running security audit...")
	@if command -v poetry >/dev/null 2>&1; then \
		poetry run safety check; \
		poetry run bandit -r app/; \
	else \
		safety check; \
		bandit -r app/; \
	fi

# 의존성 업데이트
update-deps: ## 📦 Update dependencies
	@$(call colorecho, "📦 Updating dependencies...")
	@if command -v poetry >/dev/null 2>&1; then \
		poetry update; \
	else \
		pip-compile --upgrade requirements.in; \
	fi

# 데이터베이스 마이그레이션 (예시 - FastAPI/Django)
migrate: ## 🗄️ Run database migrations
	@$(call colorecho, "🗄️ Running database migrations...")
	@if command -v poetry >/dev/null 2>&1; then \
		poetry run alembic upgrade head; \
	else \
		alembic upgrade head; \
	fi

# 프로덕션 배포
deploy-prod: lint test-unit build ## 🚀 Deploy to production
	@$(call colorecho, "🚀 Deploying to production...")
	@# 여기에 실제 배포 로직 추가
	@# 예: docker push $(FULL_TAG) && kubectl apply -f k8s/
	@$(call success, "Deployed to production")