# ================================================================
# Staging Environment Configuration
# ================================================================

# 스테이징 환경 설정
DEBUG = false
DOCKER_BUILD_OPTION += --no-cache

# 스테이징용 Docker Compose 파일
COMPOSE_FILE = docker-compose.staging.yml

# 스테이징 환경 변수
NODE_ENV = staging
PYTHON_ENV = staging
LOG_LEVEL = info

# 스테이징 인프라 설정
STAGING_CLUSTER = staging-cluster
STAGING_NAMESPACE = staging

# ================================================================
# 스테이징 환경 전용 타겟들
# ================================================================

staging-deploy: check-git-clean build test ## 🚀 Deploy to staging environment
	@$(call colorecho, 🚀 Deploying to staging environment...)
	@# 스테이징 배포 로직
	@if command -v kubectl >/dev/null 2>&1; then \
		kubectl apply -f k8s/staging/ --namespace=$(STAGING_NAMESPACE); \
	elif [ -f "docker-compose.staging.yml" ]; then \
		docker-compose -f docker-compose.staging.yml up -d; \
	else \
		$(call warn, No staging deployment configuration found); \
	fi
	@$(call success, Deployed to staging)

staging-status: ## 📊 Show staging deployment status
	@$(call colorecho, 📊 Checking staging status...)
	@if command -v kubectl >/dev/null 2>&1; then \
		kubectl get pods --namespace=$(STAGING_NAMESPACE); \
		kubectl get services --namespace=$(STAGING_NAMESPACE); \
	elif [ -f "docker-compose.staging.yml" ]; then \
		docker-compose -f docker-compose.staging.yml ps; \
	fi

staging-logs: ## 📋 Show staging application logs
	@$(call colorecho, 📋 Showing staging logs...)
	@if command -v kubectl >/dev/null 2>&1; then \
		kubectl logs -f deployment/$(NAME) --namespace=$(STAGING_NAMESPACE); \
	elif [ -f "docker-compose.staging.yml" ]; then \
		docker-compose -f docker-compose.staging.yml logs -f; \
	fi

staging-rollback: ## 🔄 Rollback staging deployment
	@$(call warn, Rolling back staging deployment)
	@echo "Continue? [y/N] " && read ans && [ $${ans:-N} = y ]
	@$(call colorecho, 🔄 Rolling back staging...)
	@if command -v kubectl >/dev/null 2>&1; then \
		kubectl rollout undo deployment/$(NAME) --namespace=$(STAGING_NAMESPACE); \
	else \
		$(call warn, Rollback only supported for Kubernetes deployments); \
	fi

staging-test: ## 🧪 Run integration tests against staging
	@$(call colorecho, 🧪 Running staging integration tests...)
	@# 스테이징 환경에 대한 통합 테스트 실행
	@if [ -f "tests/staging.test.js" ]; then \
		npm run test:staging; \
	elif [ -f "tests/test_staging.py" ]; then \
		pytest tests/test_staging.py; \
	else \
		$(call warn, No staging tests found); \
	fi

staging-health-check: ## 🩺 Check staging environment health
	@$(call colorecho, 🩺 Checking staging health...)
	@if [ -n "$(STAGING_URL)" ]; then \
		curl -f $(STAGING_URL)/health || $(call fail, Staging health check failed); \
	else \
		$(call warn, STAGING_URL not configured); \
	fi

# ================================================================
# 스테이징 데이터 관리
# ================================================================

staging-backup: ## 💾 Backup staging data
	@$(call colorecho, 💾 Backing up staging data...)
	@# 스테이징 데이터 백업 로직
	@if command -v kubectl >/dev/null 2>&1; then \
		kubectl exec deployment/$(NAME)-db --namespace=$(STAGING_NAMESPACE) -- \
			pg_dump -U postgres $(NAME) > staging-backup-$(shell date +%Y%m%d_%H%M%S).sql; \
	fi
	@$(call success, Staging backup completed)

staging-restore: ## 🔄 Restore staging from backup
	@$(call warn, This will restore staging data from backup)
	@echo "Backup file: " && read backup_file
	@echo "Continue? [y/N] " && read ans && [ $${ans:-N} = y ]
	@$(call colorecho, 🔄 Restoring staging data...)
	@# 스테이징 데이터 복원 로직
	@$(call success, Staging restore completed)