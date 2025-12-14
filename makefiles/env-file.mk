include $(MAKEFILE_DIR)/makefiles/colors.mk

ENV_MANAGER := python3 $(SCRIPTS_DIR)/env_manager.py
ENVIRONMENT := $(ENV)
SHOW_OVERRIDE := true

# 중복 로드 방지 가드
ifndef ENV_FILE_LOADED
ENV_FILE_LOADED := true

ifneq (,$(wildcard .env.common))
    include .env.common
    export
    $(info [INFO] .env.common 파일 로드됨)
endif

ifneq (,$(wildcard .env.local))
    include .env.local
    export
    $(info [INFO] .env.local 파일 로드됨 (오버라이드))
else
    $(shell touch .env.local)
    $(info [INFO] .env.local 파일이 없어서 빈 파일로 생성했습니다)
endif

endif # ENV_FILE_LOADED

# .env.runtime 파일 확인 및 생성
ifeq (,$(wildcard .env.runtime))
    $(shell touch .env.runtime)
    $(info [INFO] .env.runtime 파일이 없어서 빈 파일로 생성했습니다)
endif

prepare-env: ## 🔧 .env.resolved 파일 준비 (docker-compose용, 빌드 후 자동 감지)
	@echo "$(BLUE)📝 .env.resolved 파일 생성 중...$(NC)"
	@echo ""
	@$(ENV_MANAGER) export --environment $(ENVIRONMENT) > .env.resolved  
	@# 빌드된 이미지가 있으면 DEPLOY_IMAGE만 오버라이드
	@if [ -f .build-info ]; then \
		BUILD_IMAGE=$$(cat .build-info); \
		echo "$(CYAN)🔍 빌드된 이미지 감지: $$BUILD_IMAGE$(NC)"; \
		TMP=$$(mktemp .env.XXXXXX); \
		awk -v img="$$BUILD_IMAGE" '\
			/^DEPLOY_IMAGE=/ { print "DEPLOY_IMAGE=" img; next } \
			{ print }' .env.resolved   > "$$TMP"; \
		if ! grep -q '^DEPLOY_IMAGE=' "$$TMP"; then \
			echo "DEPLOY_IMAGE=$$BUILD_IMAGE" >> "$$TMP"; \
		fi; \
		mv "$$TMP" .env.resolved  ; \
	fi
	@echo "$(YELLOW)배포 환경:$(NC)"
	@echo "  ENVIRONMENT     : $(ENVIRONMENT)"
	@DEPLOY_IMG=$$(grep '^DEPLOY_IMAGE=' .env.resolved 2>/dev/null | cut -d= -f2); \
	if [ -n "$$DEPLOY_IMG" ]; then \
		echo "  DEPLOY_IMAGE    : $$DEPLOY_IMG"; \
		if [ -f .build-info ]; then \
			echo "  $(CYAN)소스           : 로컬 빌드 (.build-info)$(NC)"; \
		else \
			echo "  $(GRAY)소스           : .env.$(ENVIRONMENT)$(NC)"; \
		fi; \
	else \
		echo "  DEPLOY_IMAGE    : $(GRAY)(설정 안됨)$(NC)"; \
	fi
	@echo ""
	@echo "$(YELLOW)빌드 컨텍스트 (현재 계산된 값):$(NC)"
	@echo "  REPO_HUB        : $(REPO_HUB)"
	@echo "  NAME            : $(NAME)"
	@echo "  VERSION         : $(VERSION)"
	@echo "  TAGNAME         : $(TAGNAME)"
	@echo "  FULL_TAG        : $(FULL_TAG)"
	@if [ "$(UMF_MODE)" = "global" ]; then \
		echo "  GIT_WORK_DIR    : $(GIT_WORK_DIR)"; \
		echo "  CURRENT_BRANCH  : $(CURRENT_BRANCH)"; \
		echo "  CURRENT_COMMIT  : $(CURRENT_COMMIT_SHORT)"; \
	fi
	@echo ""
	@echo "$(GREEN)✓ .env.resolved 파일 생성 완료 (Environment: $(ENVIRONMENT))$(NC)"
	@if [ ! -f .build-info ]; then \
		echo "$(GRAY)💡 Tip: 'make build' 후에는 빌드된 이미지가 자동으로 사용됩니다$(NC)"; \
		echo "$(GRAY)💡 Tip: 'make reset-build' 로 .env.$(ENVIRONMENT) 기준으로 리셋할 수 있습니다$(NC)"; \
	fi

# prepare-runtime-env: ## .env.resolved + DEPLOY_IMAGE 생성 (docker-compose/로컬 실행용)
# 	@$(ENV_MANAGER) export --environment "$(ENVIRONMENT)" > .env
# 	@{ \
# 	  if [ -d "$(SOURCE_DIR)" ] && cd "$(SOURCE_DIR)" >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1; then \
# 	    $(compute_build_vars); \
# 	    cd - >/dev/null 2>&1 || true; \
# 	    echo "[INFO] Calculated IMAGE_TAG: $$IMAGE_TAG"; \
# 	    TMP=$$(mktemp .env.XXXXXX); \
# 	    awk -v img="$$IMAGE_TAG" '\
# 	      $$0 !~ /^DEPLOY_IMAGE=/ { print $$0 } \
# 	      END { print "DEPLOY_IMAGE=" img }' .env > "$$TMP"; \
# 	    mv "$$TMP" .env; \
# 	  else \
# 	    echo "[WARNING] SOURCE_DIR or git not ready; skipping DEPLOY_IMAGE calculation"; \
# 	  fi; \
# 	}
# 	@echo ""
# 	@echo "$(GREEN)✓ .env 파일 생성 완료 (Environment: $(ENVIRONMENT), DEPLOY_IMAGE 포함)$(NC)"

prepare-runtime-env: ## 🔧 .env + DEPLOY_IMAGE 생성 (docker-compose/로컬 실행용)
	@echo "$(BLUE)📝 .env.resolved 파일 생성 중 (DEPLOY_IMAGE 자동 계산)...$(NC)"
	@echo ""
	@$(ENV_MANAGER) export --environment "$(ENVIRONMENT)" > .env.resolved
	@{ \
	  if [ -d "$(SOURCE_DIR)" ] && cd "$(SOURCE_DIR)" >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1; then \
	    $(compute_build_vars); \
	    cd - >/dev/null 2>&1 || true; \
	    printf "$(YELLOW)계산된 이미지 태그:$(NC)\n"; \
	    printf "  IMAGE_TAG       : %s\n" "$$IMAGE_TAG"; \
	    printf "  DEPLOY_IMAGE    : %s\n" "$$IMAGE_TAG"; \
	    printf "\n"; \
	    TMP=$$(mktemp .env.XXXXXX); \
	    awk -v img="$$IMAGE_TAG" '\
	      $$0 !~ /^DEPLOY_IMAGE=/ { print $$0 } \
	      END { print "DEPLOY_IMAGE=" img }' .env.resolved > "$$TMP"; \
	    mv "$$TMP" .env.resolved ; \
	  else \
	    echo "$(YELLOW)[WARNING]$(NC) SOURCE_DIR or git not ready; skipping DEPLOY_IMAGE calculation"; \
	  fi; \
	}
	@echo "$(GREEN)✓ .env.resolved 파일 생성 완료 (Environment: $(ENVIRONMENT), DEPLOY_IMAGE 포함)$(NC)"


# env: ## .env.runtime 생성 (SSM + 공개 구성 병합)
# 	$(call log_info,".env.runtime 생성 시작...")
	
# 	@if [ "$(FETCH_SECRETS)" = "true" ]; then \
# 		echo "🔐 SSM에서 시크릿 가져오는 중..."; \
# 		python $(SCRIPTS_DIR)/fetch_secrets.py $(ENVIRONMENT) || { \
# 			$(call sh_log_error,.env.runtime 생성 실패); \
# 			exit 1; \
# 		}; \
# 	else \
# 		echo "⚠️  FETCH_SECRETS=false - SSM 시크릿 건너뜀"; \
# 		echo "📝 공개 구성만으로 .env.runtime 생성"; \
# 		if [ -f "config/$(ENVIRONMENT)/app.env.public" ]; then \
# 			cp config/$(ENVIRONMENT)/app.env.public .env.runtime; \
# 			chmod 600 .env.runtime; \
# 		else \
# 			touch .env.runtime; \
# 			chmod 600 .env.runtime; \
# 		fi; \
# 	fi
	
# 	$(call log_success,".env.runtime 생성 완료")


reset-build: ## 🔧 빌드 정보 리셋 (.env.{ENV} 기준으로 복원)
	@if [ -f .build-info ]; then \
		echo "$(YELLOW)🔄 빌드 정보 리셋 중...$(NC)"; \
		rm -f .build-info; \
		echo "$(GREEN)✓ .build-info 삭제됨$(NC)"; \
		echo "$(BLUE)💡 다음 'make prepare-env'는 .env.$(ENVIRONMENT) 기준으로 실행됩니다$(NC)"; \
	else \
		echo "$(GRAY)ℹ️  빌드 정보가 없습니다 (이미 리셋 상태)$(NC)"; \
	fi

env-list: ## 🔧 환경 변수 목록 조회 (FILTER=키워드로 필터링 가능, SHOW_OVERRIDE=true로 오버라이드 표시)
	@echo "=== 환경 변수 목록 (환경: $(ENVIRONMENT)) ==="
	@echo ""
	@if [ "$(SHOW_OVERRIDE)" = "true" ]; then \
		if [ -z "$(FILTER)" ]; then \
			echo "전체 환경 변수 (오버라이드 정보 포함):"; \
		else \
			echo "필터: $(FILTER) (오버라이드 정보 포함):"; \
		fi; \
		echo ""; \
		if [ -n "$(FILTER)" ]; then \
			$(ENV_MANAGER) export-sources --environment $(ENVIRONMENT) --format colored --show-override | grep -i "$(FILTER)"; \
		else \
			$(ENV_MANAGER) export-sources --environment $(ENVIRONMENT) --format colored --show-override; \
		fi; \
		echo ""; \
		echo "💡 범례:"; \
		echo "  $(RED)[Override]$(NC) - 여러 파일에서 정의됨"; \
		echo "  $(YELLOW)✓$(NC) - 최종 적용된 값"; \
		echo "  $(GRAY)[source]$(NC) - 단일 소스에서만 정의됨"; \
	else \
		if [ -z "$(FILTER)" ]; then \
			echo "전체 환경 변수:"; \
			echo ""; \
			$(ENV_MANAGER) export-sources --environment $(ENVIRONMENT) --format colored | grep -v "^$$"; \
		else \
			echo "필터: $(FILTER)"; \
			echo ""; \
			$(ENV_MANAGER) export-sources --environment $(ENVIRONMENT) --format colored | grep -i "$(FILTER)"; \
		fi; \
	fi
	@echo ""
	@echo "💡 사용법:"
	@echo "  make env-list                           # 전체 출력"
	@echo "  make env-list FILTER=LOG                # LOG 포함된 변수만"
	@echo "  make env-list SHOW_OVERRIDE=true        # 오버라이드 정보 포함"
	@echo "  make env-list FILTER=LOG SHOW_OVERRIDE=true  # 필터 + 오버라이드"
