include $(MAKEFILE_DIR)/makefiles/colors.mk

ENV_MANAGER := python3 $(SCRIPTS_DIR)/env_manager.py
ENVIRONMENT ?= $(ENV)
SHOW_OVERRIDE := true
CONSUL_ENV_FILE ?= .env.runtime
USE_CONSUL ?= false
CONSUL_CLIENT ?= python3 $(SCRIPTS_DIR)/consul_web.py
CONSUL_API_URL ?= http://localhost:8000
CONSUL_API_KEY ?= 
CONSUL_APP ?= 
CONSUL_PREFIX ?= 


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

prepare-env: ## 🔧 .env.resolved 파일 준비 (docker-compose용, Consul+로컬 환경 병합)
	@echo "$(BLUE)📝 .env.resolved 파일 생성 중...$(NC)"
	@echo ""
	@if [ "$(USE_CONSUL)" = "true" ]; then \
		echo "$(CYAN)🌐 Consul 모드: Consul + 로컬 환경 변수 병합$(NC)"; \
		$(MAKE) --no-print-directory prepare-consul-runtime-env; \
	else \
		echo "$(CYAN)� 로컬 모드미: 로컬 환경 변수만 사용$(NC)"; \
		$(ENV_MANAGER) export --environment $(ENVIRONMENT) > .env.resolved; \
		if [ -f .build-info ]; then \
			BUILD_IMAGE=$$(cat .build-info); \
			echo "$(CYAN)🔍 빌드된 이미지 감지: $$BUILD_IMAGE$(NC)"; \
			TMP=$$(mktemp .env.XXXXXX); \
			awk -v img="$$BUILD_IMAGE" '\
				/^DEPLOY_IMAGE=/ { print "DEPLOY_IMAGE=" img; next } \
				{ print }' .env.resolved > "$$TMP"; \
			if ! grep -q '^DEPLOY_IMAGE=' "$$TMP"; then \
				echo "DEPLOY_IMAGE=$$BUILD_IMAGE" >> "$$TMP"; \
			fi; \
			mv "$$TMP" .env.resolved; \
		fi; \
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

prepare-consul-env: ## 🔧 Consul에서 환경 변수 가져와서 .env.consul 생성
	@echo "$(BLUE)📝 Consul에서 환경 변수 가져오는 중...$(NC)"
	@echo ""
	@if [ "$(USE_CONSUL)" != "true" ]; then \
		echo "$(YELLOW)[WARNING]$(NC) USE_CONSUL이 true가 아닙니다. 현재 값: $(USE_CONSUL)"; \
		echo "$(GRAY)💡 USE_CONSUL=true로 설정하고 다시 실행하세요$(NC)"; \
		exit 1; \
	fi
	@echo "$(CYAN)🔍 Consul 연결 정보:$(NC)"
	@if [ -n "$(CONSUL_API_KEY)" ]; then \
		echo "  CONSUL_API_KEY  : $(GRAY)***설정됨***$(NC)"; \
	else \
		echo "  CONSUL_API_KEY  : $(GRAY)(설정 안됨)$(NC)"; \
	fi
	@if [ -n "$(CONSUL_API_URL)" ]; then \
		echo "  CONSUL_API_URL  : $(CONSUL_API_URL)"; \
	else \
		echo "  CONSUL_API_URL  : $(GRAY)(기본값 사용)$(NC)"; \
	fi
	@if [ -n "$(CONSUL_APP)" ]; then \
		echo "  CONSUL_APP      : $(CONSUL_APP)"; \
	else \
		echo "  CONSUL_APP      : $(GRAY)(설정 안됨)$(NC)"; \
	fi
	@echo "  ENVIRONMENT     : $(ENVIRONMENT)"
	@echo ""
	@{ \
	  echo "$(CYAN)🌐 Consul에서 환경 변수 조회 중...$(NC)"; \
	  if [ -n "$(CONSUL_APP)" ] && [ -n "$(ENVIRONMENT)" ]; then \
	    CONSUL_CMD="$(CONSUL_CLIENT) export --app $(CONSUL_APP) --env $(ENVIRONMENT) --output $(CONSUL_ENV_FILE) --overwrite"; \
	  elif [ -n "$(CONSUL_PREFIX)" ]; then \
	    CONSUL_CMD="$(CONSUL_CLIENT) export --prefix $(CONSUL_PREFIX) --output $(CONSUL_ENV_FILE) --overwrite"; \
	  else \
	    echo "$(RED)❌ CONSUL_APP+ENVIRONMENT 또는 CONSUL_PREFIX가 필요합니다$(NC)"; \
	    echo "$(GRAY)💡 CONSUL_APP=myapp ENVIRONMENT=prod 또는 CONSUL_PREFIX=myapp/prod 설정$(NC)"; \
	    exit 1; \
	  fi; \
	  echo "$(GRAY)🔧 실행할 명령: $$CONSUL_CMD$(NC)"; \
	  if [ "$(DEBUG)" = "true" ] || [ "$(CONSUL_DEBUG)" = "true" ]; then \
	    echo "$(YELLOW)[DEBUG]$(NC) 디버그 모드로 실행 중..."; \
	    eval "$$CONSUL_CMD --verbose" || CONSUL_EXIT=$$?; \
	  else \
	    eval "$$CONSUL_CMD" 2>consul_error.tmp || CONSUL_EXIT=$$?; \
	  fi; \
	  if [ "$${CONSUL_EXIT:-0}" -eq 0 ]; then \
	    echo "$(GREEN)✓ Consul에서 환경 변수를 성공적으로 가져왔습니다$(NC)"; \
	    if [ -f "$(CONSUL_ENV_FILE)" ]; then \
	      VAR_COUNT=$$(grep -c '^[A-Z]' $(CONSUL_ENV_FILE) 2>/dev/null || echo "0"); \
	      echo "$(YELLOW)📊 가져온 환경 변수 개수: $$VAR_COUNT$(NC)"; \
	    fi; \
	    rm -f consul_error.tmp; \
	  else \
	    echo "$(RED)❌ Consul에서 환경 변수를 가져오는데 실패했습니다$(NC)"; \
	    if [ -f consul_error.tmp ]; then \
	      echo "$(YELLOW)🔍 에러 상세:$(NC)"; \
	      cat consul_error.tmp; \
	      rm -f consul_error.tmp; \
	    fi; \
	    echo "$(GRAY)💡 Consul 서버 상태와 API 키를 확인하세요$(NC)"; \
	    echo "$(GRAY)💡 DEBUG=true로 실행하면 더 자세한 정보를 볼 수 있습니다$(NC)"; \
	    exit 1; \
	  fi; \
	}
	@echo ""
	@echo "$(GREEN)✓ $(CONSUL_ENV_FILE) 파일 생성 완료 (Environment: $(ENVIRONMENT))$(NC)"
	@echo "$(GRAY)💡 Tip: 'make env-list-consul'로 가져온 변수들을 확인할 수 있습니다$(NC)"

consul-debug: ## 🔧 Consul 연결 디버깅 (상세한 에러 정보 출력)
	@echo "$(BLUE)🔍 Consul 연결 디버깅...$(NC)"
	@echo ""
	@echo "$(CYAN)📋 설정 정보:$(NC)"
	@echo "  USE_CONSUL      : $(USE_CONSUL)"
	@echo "  CONSUL_CLIENT   : $(CONSUL_CLIENT)"
	@echo "  CONSUL_API_URL  : $(CONSUL_API_URL)"
	@echo "  CONSUL_API_KEY  : $$(if [ -n '$(CONSUL_API_KEY)' ]; then echo '***설정됨***'; else echo '(설정 안됨)'; fi)"
	@echo "  CONSUL_APP      : $(CONSUL_APP)"
	@echo "  CONSUL_PREFIX   : $(CONSUL_PREFIX)"
	@echo "  ENVIRONMENT     : $(ENVIRONMENT)"
	@echo ""
	@echo "$(CYAN)🧪 스크립트 존재 확인:$(NC)"
	@if [ -f "$(SCRIPTS_DIR)/consul_web.py" ]; then \
		echo "  ✓ $(SCRIPTS_DIR)/consul_web.py 존재"; \
	else \
		echo "  ❌ $(SCRIPTS_DIR)/consul_web.py 없음"; \
	fi
	@echo ""
	@echo "$(CYAN)🔌 Python 및 의존성 확인:$(NC)"
	@python3 --version 2>/dev/null || echo "  ❌ Python3 없음"
	@python3 -c "import requests; print('  ✓ requests 모듈 사용 가능')" 2>/dev/null || echo "  ❌ requests 모듈 없음"
	@echo ""
	@echo "$(CYAN)🌐 네트워크 연결 테스트:$(NC)"
	@if command -v curl >/dev/null 2>&1; then \
		echo "  Consul API 서버 연결 테스트..."; \
		if curl -s --connect-timeout 5 "$(CONSUL_API_URL)/health" >/dev/null 2>&1; then \
			echo "  ✓ $(CONSUL_API_URL) 연결 가능"; \
		else \
			echo "  ❌ $(CONSUL_API_URL) 연결 실패"; \
		fi; \
	else \
		echo "  (curl 없음 - 네트워크 테스트 건너뜀)"; \
	fi
	@echo ""
	@echo "$(CYAN)🧪 Consul 클라이언트 테스트:$(NC)"
	@if [ -n "$(CONSUL_API_KEY)" ]; then \
		echo "  API 키로 간단한 요청 테스트..."; \
		$(CONSUL_CLIENT) --help 2>/dev/null | head -3 || echo "  ❌ 클라이언트 실행 실패"; \
	else \
		echo "  ❌ CONSUL_API_KEY가 설정되지 않음"; \
	fi
	@echo ""
	@echo "$(YELLOW)💡 디버그 실행 방법:$(NC)"
	@echo "  make prepare-consul-env DEBUG=true"
	@echo "  make prepare-consul-env CONSUL_DEBUG=true"

prepare-consul-runtime-env: ## 🔧 Consul + 로컬 환경 변수 병합하여 .env.resolved 생성
	@echo "$(BLUE)📝 Consul + 로컬 환경 변수 병합 중...$(NC)"
	@echo ""
	@if [ "$(USE_CONSUL)" != "true" ]; then \
		echo "$(YELLOW)[WARNING]$(NC) USE_CONSUL이 true가 아닙니다. 현재 값: $(USE_CONSUL)"; \
		echo "$(GRAY)💡 USE_CONSUL=true로 설정하고 다시 실행하세요$(NC)"; \
		exit 1; \
	fi
	@# 먼저 Consul에서 환경 변수 가져오기
	@$(MAKE) --no-print-directory prepare-consul-env
	@echo ""
	@echo "$(CYAN)🔄 환경 변수 병합 중...$(NC)"
	@{ \
	  TMP=$$(mktemp .env.XXXXXX); \
	  echo "# Consul 환경 변수 ($(ENVIRONMENT))" > "$$TMP"; \
	  echo "# 생성 시간: $$(date)" >> "$$TMP"; \
	  echo "" >> "$$TMP"; \
	  if [ -f "$(CONSUL_ENV_FILE)" ]; then \
	    cat "$(CONSUL_ENV_FILE)" >> "$$TMP"; \
	    echo "" >> "$$TMP"; \
	  fi; \
	  echo "# 로컬 환경 변수 오버라이드" >> "$$TMP"; \
	  $(ENV_MANAGER) export --environment "$(ENVIRONMENT)" --use-consul >> "$$TMP"; \
	  if [ -d "$(SOURCE_DIR)" ] && cd "$(SOURCE_DIR)" >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1; then \
	    $(compute_build_vars); \
	    cd - >/dev/null 2>&1 || true; \
	    printf "\n# 빌드 정보\n" >> "$$TMP"; \
	    printf "IMAGE_TAG=%s\n" "$$IMAGE_TAG" >> "$$TMP"; \
	    printf "DEPLOY_IMAGE=%s\n" "$$IMAGE_TAG" >> "$$TMP"; \
	    printf "$(YELLOW)계산된 이미지 태그:$(NC)\n"; \
	    printf "  IMAGE_TAG       : %s\n" "$$IMAGE_TAG"; \
	    printf "  DEPLOY_IMAGE    : %s\n" "$$IMAGE_TAG"; \
	  else \
	    echo "$(YELLOW)[WARNING]$(NC) SOURCE_DIR or git not ready; skipping DEPLOY_IMAGE calculation"; \
	  fi; \
	  mv "$$TMP" .env.resolved; \
	}
	@echo ""
	@echo "$(GREEN)✓ .env.resolved 파일 생성 완료 (Consul + 로컬 환경 병합)$(NC)"
	@echo "$(YELLOW)📊 최종 환경 변수 통계:$(NC)"
	@TOTAL_VARS=$$(grep -c '^[A-Z]' .env.resolved 2>/dev/null || echo "0"); \
	CONSUL_VARS=$$(grep -c '^[A-Z]' $(CONSUL_ENV_FILE) 2>/dev/null || echo "0"); \
	echo "  Consul 변수     : $$CONSUL_VARS개"; \
	echo "  전체 변수       : $$TOTAL_VARS개"

env-list-consul: ## 🔧 Consul 환경 변수 목록 조회 (FILTER=키워드로 필터링 가능)
	@echo "=== Consul 환경 변수 목록 (환경: $(ENVIRONMENT)) ==="
	@echo ""
	@if [ "$(USE_CONSUL)" != "true" ]; then \
		echo "$(YELLOW)[WARNING]$(NC) USE_CONSUL이 true가 아닙니다. 현재 값: $(USE_CONSUL)"; \
		echo "$(GRAY)💡 USE_CONSUL=true로 설정하고 다시 실행하세요$(NC)"; \
		exit 1; \
	fi
	@{ \
	  if [ -n "$(CONSUL_APP)" ] && [ -n "$(ENVIRONMENT)" ]; then \
	    LIST_CMD="$(CONSUL_CLIENT) list --app $(CONSUL_APP) --env $(ENVIRONMENT)"; \
	  elif [ -n "$(CONSUL_PREFIX)" ]; then \
	    LIST_CMD="$(CONSUL_CLIENT) list --prefix $(CONSUL_PREFIX)"; \
	  else \
	    echo "$(RED)❌ CONSUL_APP+ENVIRONMENT 또는 CONSUL_PREFIX가 필요합니다$(NC)"; \
	    echo "$(GRAY)💡 CONSUL_APP=myapp ENVIRONMENT=prod 또는 CONSUL_PREFIX=myapp/prod 설정$(NC)"; \
	    exit 1; \
	  fi; \
	  if [ -n "$(FILTER)" ]; then \
	    LIST_CMD="$$LIST_CMD --match $(FILTER)"; \
	  fi; \
	  echo "$(CYAN)🌐 Consul에서 환경 변수 목록 조회 중...$(NC)"; \
	  if eval "$$LIST_CMD" 2>/dev/null; then \
	    echo ""; \
	    echo "$(GREEN)✓ 조회 완료$(NC)"; \
	  else \
	    echo "$(RED)❌ Consul에서 환경 변수 목록을 가져오는데 실패했습니다$(NC)"; \
	    echo "$(GRAY)� ConsRul 서버 상태와 API 키를 확인하세요$(NC)"; \
	    exit 1; \
	  fi; \
	}
	@echo ""
	@echo "💡 사용법:"
	@echo "  make env-list-consul                    # 전체 출력"
	@echo "  make env-list-consul FILTER=LOG         # LOG 포함된 변수만"

consul-count: ## 🔧 Consul 환경 변수 개수 조회
	@if [ "$(USE_CONSUL)" != "true" ]; then \
		echo "$(YELLOW)[WARNING]$(NC) USE_CONSUL이 true가 아닙니다. 현재 값: $(USE_CONSUL)"; \
		echo "$(GRAY)💡 USE_CONSUL=true로 설정하고 다시 실행하세요$(NC)"; \
		exit 1; \
	fi
	@{ \
	  if [ -n "$(CONSUL_APP)" ] && [ -n "$(ENVIRONMENT)" ]; then \
	    COUNT_CMD="$(CONSUL_CLIENT) count --app $(CONSUL_APP) --env $(ENVIRONMENT)"; \
	  elif [ -n "$(CONSUL_PREFIX)" ]; then \
	    COUNT_CMD="$(CONSUL_CLIENT) count --prefix $(CONSUL_PREFIX)"; \
	  else \
	    echo "$(RED)❌ CONSUL_APP+ENVIRONMENT 또는 CONSUL_PREFIX가 필요합니다$(NC)"; \
	    echo "$(GRAY)💡 CONSUL_APP=myapp ENVIRONMENT=prod 또는 CONSUL_PREFIX=myapp/prod 설정$(NC)"; \
	    exit 1; \
	  fi; \
	  echo "$(CYAN)🌐 Consul 환경 변수 개수 조회 중...$(NC)"; \
	  if COUNT=$$(eval "$$COUNT_CMD" 2>/dev/null); then \
	    echo "$(YELLOW)📊 총 $$COUNT개의 환경 변수$(NC)"; \
	  else \
	    echo "$(RED)❌ Consul에서 환경 변수 개수를 가져오는데 실패했습니다$(NC)"; \
	    echo "$(GRAY)💡 Consul 서버 상태와 API 키를 확인하세요$(NC)"; \
	    exit 1; \
	  fi; \
	}

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

env-list: ## 🔧 환경 변수 목록 조회 (Consul+로컬 통합, FILTER=키워드로 필터링 가능)
	@echo "=== 환경 변수 목록 (환경: $(ENVIRONMENT)) ==="
	@if [ "$(USE_CONSUL)" = "true" ]; then \
		echo "$(CYAN)🌐 모드: Consul + 로컬 환경 변수$(NC)"; \
	else \
		echo "$(CYAN)📁 모드: 로컬 환경 변수만$(NC)"; \
	fi
	@echo ""
	@if [ "$(USE_CONSUL)" = "true" ]; then \
		if [ ! -f "$(CONSUL_ENV_FILE)" ]; then \
			echo "$(YELLOW)[INFO]$(NC) Consul 환경 변수 파일이 없습니다. 먼저 가져오는 중..."; \
			$(MAKE) --no-print-directory prepare-consul-env >/dev/null 2>&1 || true; \
		fi; \
	fi
	@CONSUL_FLAG=""; \
	if [ "$(USE_CONSUL)" = "true" ]; then \
		CONSUL_FLAG="--use-consul"; \
	fi; \
	if [ "$(SHOW_OVERRIDE)" = "true" ]; then \
		if [ -z "$(FILTER)" ]; then \
			echo "전체 환경 변수 (오버라이드 정보 포함):"; \
		else \
			echo "필터: $(FILTER) (오버라이드 정보 포함):"; \
		fi; \
		echo ""; \
		if [ -n "$(FILTER)" ]; then \
			$(ENV_MANAGER) export-sources --environment $(ENVIRONMENT) --format colored --show-override $$CONSUL_FLAG | grep -i "$(FILTER)"; \
		else \
			$(ENV_MANAGER) export-sources --environment $(ENVIRONMENT) --format colored --show-override $$CONSUL_FLAG; \
		fi; \
		echo ""; \
		echo "💡 범례:"; \
		echo "  $(RED)[Override]$(NC) - 여러 파일에서 정의됨"; \
		echo "  $(YELLOW)✓$(NC) - 최종 적용된 값"; \
		echo "  $(GRAY)[source]$(NC) - 단일 소스에서만 정의됨"; \
		if [ "$(USE_CONSUL)" = "true" ]; then \
			echo "  $(CYAN)[Consul]$(NC) - Consul 값이 로컬 값을 오버라이드"; \
		fi; \
	else \
		if [ -z "$(FILTER)" ]; then \
			echo "전체 환경 변수:"; \
			echo ""; \
			$(ENV_MANAGER) export-sources --environment $(ENVIRONMENT) --format colored $$CONSUL_FLAG | grep -v "^$$"; \
		else \
			echo "필터: $(FILTER)"; \
			echo ""; \
			$(ENV_MANAGER) export-sources --environment $(ENVIRONMENT) --format colored $$CONSUL_FLAG | grep -i "$(FILTER)"; \
		fi; \
	fi
	@echo ""

	@echo "💡 사용법:"
	@echo "  make env-list                           # 전체 출력"
	@echo "  make env-list FILTER=LOG                # LOG 포함된 변수만"
	@echo "  make env-list SHOW_OVERRIDE=true        # 오버라이드 정보 포함"
	@echo "  make env-list USE_CONSUL=true           # Consul + 로컬 환경 변수"
