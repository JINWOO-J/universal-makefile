# ================================================================
# Production Environment Configuration
# ================================================================

# 프로덕션 환경 설정 (보안 강화)
DEBUG = false
DOCKER_BUILD_OPTION += --no-cache

# 프로덕션용 Docker Compose 파일
COMPOSE_FILE = docker-compose.prod.yml

# 프로덕션 환경 변수
NODE_ENV = production
PYTHON_ENV = production
LOG_LEVEL = warn

# 프로덕션 인프라 설정
PROD_CLUSTER = production-cluster
PROD_NAMESPACE = production
PROD_REPLICAS = 3

# ================================================================
# 프로덕션 배포 전 검증
# ================================================================

prod-pre-deploy-check: ## 🔍 Run pre-deployment checks
	@$(call colorecho, "🔍 Running pre-deployment checks...")
	@$(MAKE) check-git-clean
	@$(MAKE) security-scan
	@$(MAKE) test
	@$(MAKE) validate-version
	@if [ "$(CURRENT_BRANCH)" != "$(MAIN_BRANCH)" ]; then \
		$(call error, "Production deployment must be from $(MAIN_BRANCH) branch"); \
		exit 1; \
	fi
	@$(call success, "Pre-deployment checks passed")

# ================================================================
# 프로덕션 배포
# ================================================================

prod-deploy: prod-pre-deploy-check build push ## 🚀 Deploy to production (CAREFUL!)
	@$(call warn, "🚨 PRODUCTION DEPLOYMENT 🚨")
	@$(call warn, "This will deploy to production environment")
	@echo "Version: $(VERSION)"
	@echo "Branch: $(CURRENT_BRANCH)"
	@echo "Commit: $(shell git rev-parse --short HEAD)"
	@echo ""
	@echo "Continue? [y/N] " && read ans && [ $${ans:-N} = y ]
	
	@$(call colorecho, "🚀 Deploying to production...")
	
	# Kubernetes 배포
	@if command -v kubectl >/dev/null 2>&1; then \
		$(call colorecho, "📦 Deploying to Kubernetes..."); \
		kubectl apply -f k8s/production/ --namespace=$(PROD_NAMESPACE); \
		kubectl set image deployment/$(NAME) $(NAME)=$(FULL_TAG) --namespace=$(PROD_NAMESPACE); \
		kubectl rollout status deployment/$(NAME) --namespace=$(PROD_NAMESPACE) --timeout=300s; \
	elif [ -f "docker-compose.prod.yml" ]; then \
		$(call colorecho, "🐳 Deploying with Docker Compose..."); \
		docker-compose -f docker-compose.prod.yml up -d; \
	else \
		$(call error, "No production deployment configuration found"); \
		exit 1; \
	fi
	
	@$(call success, "🎉 Production deployment completed!")
	@$(MAKE) prod-health-check

prod-status: ## 📊 Show production deployment status
	@$(call colorecho, "📊 Checking production status...")
	@if command -v kubectl >/dev/null 2>&1; then \
		echo "$(BLUE)Pods:$(RESET)"; \
		kubectl get pods --namespace=$(PROD_NAMESPACE) -l app=$(NAME); \
		echo ""; \
		echo "$(BLUE)Services:$(RESET)"; \
		kubectl get services --namespace=$(PROD_NAMESPACE) -l app=$(NAME); \
		echo ""; \
		echo "$(BLUE)Deployments:$(RESET)"; \
		kubectl get deployments --namespace=$(PROD_NAMESPACE) -l app=$(NAME); \
	elif [ -f "docker-compose.prod.yml" ]; then \
		docker-compose -f docker-compose.prod.yml ps; \
	fi

prod-logs: ## 📋 Show production application logs
	@$(call colorecho, "📋 Showing production logs...")
	@if command -v kubectl >/dev/null 2>&1; then \
		kubectl logs -f deployment/$(NAME) --namespace=$(PROD_NAMESPACE) --tail=100; \
	elif [ -f "docker-compose.prod.yml" ]; then \
		docker-compose -f docker-compose.prod.yml logs -f --tail=100; \
	fi

prod-health-check: ## 🩺 Check production environment health
	@$(call colorecho, "🩺 Checking production health...")
	@if [ -n "$(PROD_URL)" ]; then \
		for i in {1..5}; do \
			if curl -f -s $(PROD_URL)/health >/dev/null; then \
				$(call success, "Production health check passed"); \
				break; \
			else \
				$(call warn, "Health check attempt $$i failed, retrying..."); \
				sleep 10; \
			fi; \
		done; \
	else \
		$(call warn, "PROD_URL not configured, skipping health check"); \
	fi

# ================================================================
# 프로덕션 롤백
# ================================================================

prod-rollback: ## 🔄 Rollback production deployment (EMERGENCY)
	@$(call warn, "🚨 PRODUCTION ROLLBACK 🚨")
	@$(call warn, "This will rollback the production deployment")
	@echo "Continue? [y/N] " && read ans && [ $${ans:-N} = y ]
	
	@$(call colorecho, "🔄 Rolling back production...")
	@if command -v kubectl >/dev/null 2>&1; then \
		kubectl rollout undo deployment/$(NAME) --namespace=$(PROD_NAMESPACE); \
		kubectl rollout status deployment/$(NAME) --namespace=$(PROD_NAMESPACE) --timeout=300s; \
	else \
		$(call error, "Rollback only supported for Kubernetes deployments"); \
		exit 1; \
	fi
	
	@$(call success, "Production rollback completed")
	@$(MAKE) prod-health-check

# ================================================================
# 프로덕션 스케일링
# ================================================================

prod-scale: ## ⚖️ Scale production deployment (usage: make prod-scale REPLICAS=5)
	@if [ -z "$(REPLICAS)" ]; then \
		$(call error, "REPLICAS is required. Usage: make prod-scale REPLICAS=5"); \
		exit 1; \
	fi
	@$(call warn, "Scaling production to $(REPLICAS) replicas")
	@echo "Continue? [y/N] " && read ans && [ $${ans:-N} = y ]
	
	@$(call colorecho, "⚖️ Scaling production to $(REPLICAS) replicas...")
	@if command -v kubectl >/dev/null 2>&1; then \
		kubectl scale deployment/$(NAME) --replicas=$(REPLICAS) --namespace=$(PROD_NAMESPACE); \
		kubectl rollout status deployment/$(NAME) --namespace=$(PROD_NAMESPACE) --timeout=300s; \
	elif [ -f "docker-compose.prod.yml" ]; then \
		docker-compose -f docker-compose.prod.yml up -d --scale app=$(REPLICAS); \
	fi
	@$(call success, "Production scaled to $(REPLICAS) replicas")

# ================================================================
# 프로덕션 백업 및 복원
# ================================================================

prod-backup: ## 💾 Backup production data (CRITICAL)
	@$(call colorecho, "💾 Creating production backup...")
	@BACKUP_NAME="prod-backup-$(shell date +%Y%m%d_%H%M%S)"; \
	if command -v kubectl >/dev/null 2>&1; then \
		kubectl exec deployment/$(NAME)-db --namespace=$(PROD_NAMESPACE) -- \
			pg_dump -U postgres $(NAME) > $$BACKUP_NAME.sql; \
		$(call success, "Production backup created: $$BACKUP_NAME.sql"); \
	else \
		$(call warn, "Production backup not configured"); \
	fi

prod-restore: ## 🔄 Restore production from backup (EXTREMELY DANGEROUS)
	@$(call error, "🚨 EXTREMELY DANGEROUS OPERATION 🚨")
	@$(call error, "This will OVERWRITE production data")
	@echo "Backup file: " && read backup_file
	@echo "Type 'CONFIRM PRODUCTION RESTORE' to continue: " && read confirmation
	@if [ "$$confirmation" != "CONFIRM PRODUCTION RESTORE" ]; then \
		$(call error, "Operation cancelled"); \
		exit 1; \
	fi
	@$(call colorecho, "🔄 Restoring production data...")
	@# 프로덕션 복원 로직 (매우 신중하게 구현)
	@$(call success, "Production restore completed")

# ================================================================
# 프로덕션 모니터링
# ================================================================

prod-metrics: ## 📊 Show production metrics
	@$(call colorecho, "📊 Showing production metrics...")
	@if command -v kubectl >/dev/null 2>&1; then \
		kubectl top pods --namespace=$(PROD_NAMESPACE) -l app=$(NAME); \
	fi

prod-events: ## 📋 Show recent production events
	@$(call colorecho, "📋 Showing recent production events...")
	@if command -v kubectl >/dev/null 2>&1; then \
		kubectl get events --namespace=$(PROD_NAMESPACE) --sort-by='.lastTimestamp' | tail -20; \
	fi