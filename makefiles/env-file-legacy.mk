include $(MAKEFILE_DIR)/makefiles/colors.mk

env-keys: ## 🔧 env-show 기본/전체 키 목록 출력
	@echo "DEFAULT: $(ENV_VARS_DEFAULT)"
	@echo "ALL:     $(ENV_VARS_ALL)"

env-get: ## 🔧 지정 변수 값만 출력 (사용법: make env-get VAR=NAME)
	@[ -n "$(VAR)" ] || { echo "VAR is required (e.g., make env-get VAR=NAME)" >&2; exit 1; }
	@printf "%s\n" "$($(VAR))"

# 사용 예:
#  - make env-show -s >> $$GITHUB_ENV
#  - make env-show FORMAT=kv
#  - make env-show VARS="REPO_HUB NAME ROLE"
#  - make env-show PREFIX=DOCKER_
#  - make env-show ALL=true SKIP_EMPTY=true
#  - make env-show SHOW_SECRETS=true
env-show: ## 🔧 key=value 형식 출력(FORMAT=kv|dotenv|github, VARS/ENV_VARS/PREFIX/ALL/SKIP_EMPTY/SHOW_SECRETS)
	@FORMAT='$(FORMAT)'; [ -n "$$FORMAT" ] || FORMAT="dotenv"; \
	SKIP_EMPTY='$(SKIP_EMPTY)'; [ -n "$$SKIP_EMPTY" ] || SKIP_EMPTY="false"; \
	SHOW_SECRETS='$(SHOW_SECRETS)'; [ -n "$$SHOW_SECRETS" ] || SHOW_SECRETS="false"; \
	for k in $(if $(strip $(PREFIX)),$(filter $(PREFIX)%,$(if $(filter true,$(ALL)),$(ENV_VARS_ALL),$(if $(strip $(VARS)),$(VARS),$(if $(strip $(ENV_VARS)),$(ENV_VARS),$(ENV_VARS_DEFAULT))))) ,$(if $(filter true,$(ALL)),$(ENV_VARS_ALL),$(if $(strip $(VARS)),$(VARS),$(if $(strip $(ENV_VARS)),$(ENV_VARS),$(ENV_VARS_DEFAULT))))) ; do \
		v=$$(printenv "$$k"); \
		if [ "$$SKIP_EMPTY" = "true" ] && [ -z "$$v" ]; then continue; fi; \
		case "$$k" in *TOKEN*|*PASSWORD*|*SECRET*|*KEY*|*WEBHOOK*) \
			if [ "$$SHOW_SECRETS" != "true" ]; then v="****"; fi ;; \
		esac; \
		if [ "$$FORMAT" = "github" ]; then \
			one=$$(printf '%s' "$$v" | tr '\n' ' '); \
			printf '%s=%s\n' "$$k" "$$one"; \
		else \
			one=$$(printf '%s' "$$v" | tr '\n' ' ' | sed 's/"/\\"/g'); \
			printf '%s="%s"\n' "$$k" "$$one"; \
		fi; \
	done

# .env 파일로 저장 (기본: .env). 비어있는 값 건너뛰기(SKIP_EMPTY), 비밀값 마스킹 제어(SHOW_SECRETS)
env-file: ## 🔧 선택한 환경 변수를 .env 파일로 저장 (FILE=.env, VARS/ENV_VARS/PREFIX/ALL/SKIP_EMPTY/SHOW_SECRETS)
	@FILE='$(FILE)'; [ -n "$$FILE" ] || FILE=".env"; \
	SKIP_EMPTY='$(SKIP_EMPTY)'; [ -n "$$SKIP_EMPTY" ] || SKIP_EMPTY="false"; \
	SHOW_SECRETS='$(SHOW_SECRETS)'; [ -n "$$SHOW_SECRETS" ] || SHOW_SECRETS="false"; \
	echo "# Generated .env - $$(date)" > "$$FILE"; \
	for k in $(if $(strip $(PREFIX)),$(filter $(PREFIX)%,$(if $(filter true,$(ALL)),$(ENV_VARS_ALL),$(if $(strip $(VARS)),$(VARS),$(if $(strip $(ENV_VARS)),$(ENV_VARS),$(ENV_VARS_DEFAULT))))) ,$(if $(filter true,$(ALL)),$(ENV_VARS_ALL),$(if $(strip $(VARS)),$(VARS),$(if $(strip $(ENV_VARS)),$(ENV_VARS),$(ENV_VARS_DEFAULT))))) ; do \
		v=$$(printenv "$$k"); \
		if [ "$$SKIP_EMPTY" = "true" ] && [ -z "$$v" ]; then continue; fi; \
		case "$$k" in *TOKEN*|*PASSWORD*|*SECRET*|*KEY*|*WEBHOOK*) \
			if [ "$$SHOW_SECRETS" != "true" ]; then v="****"; fi ;; \
		esac; \
		one=$$(printf '%s' "$$v" | tr '\n' ' ' | sed 's/"/\\"/g'); \
		printf '%s="%s"\n' "$$k" "$$one" >> "$$FILE"; \
	done; \
	$(call success_echo, Wrote $$FILE)

# 간단 별칭: 디폴트로 .env 저장. 필요 시 FILE=path로 변경
env: ## 🔧 현재 환경 변수를 .env로 저장 (별칭: env-file)
	@$(MAKE) --no-print-directory -f $(firstword $(MAKEFILE_LIST)) env-file FILE='$(FILE)' VARS='$(VARS)' ENV_VARS='$(ENV_VARS)' PREFIX='$(PREFIX)' ALL='$(ALL)' SKIP_EMPTY='$(SKIP_EMPTY)' SHOW_SECRETS='$(SHOW_SECRETS)'

# 가독성 출력 모드(표 형태). 마스킹 규칙은 env-show와 동일
env-pretty: ## 🔧 표 형태로 환경 변수 출력 (VARS/ENV_VARS/PREFIX/ALL/SKIP_EMPTY/SHOW_SECRETS)
	@SKIP_EMPTY='$(SKIP_EMPTY)'; [ -n "$$SKIP_EMPTY" ] || SKIP_EMPTY="false"; \
	SHOW_SECRETS='$(SHOW_SECRETS)'; [ -n "$$SHOW_SECRETS" ] || SHOW_SECRETS="false"; \
	printf "$(BLUE)%-22s$(RESET) : $(BLUE)%s$(RESET)\n" "Variable" "Value"; \
	printf "%-22s : %s\n" "----------------------" "----------------"; \
	for k in $(if $(strip $(PREFIX)),$(filter $(PREFIX)%,$(if $(filter true,$(ALL)),$(ENV_VARS_ALL),$(if $(strip $(VARS)),$(VARS),$(if $(strip $(ENV_VARS)),$(ENV_VARS),$(ENV_VARS_DEFAULT))))) ,$(if $(filter true,$(ALL)),$(ENV_VARS_ALL),$(if $(strip $(VARS)),$(VARS),$(if $(strip $(ENV_VARS)),$(ENV_VARS),$(ENV_VARS_DEFAULT))))) ; do \
		v=$$(printenv "$$k"); \
		if [ "$$SKIP_EMPTY" = "true" ] && [ -z "$$v" ]; then continue; fi; \
		case "$$k" in *TOKEN*|*PASSWORD*|*SECRET*|*KEY*|*WEBHOOK*) \
			if [ "$$SHOW_SECRETS" != "true" ]; then v="****"; fi ;; \
		esac; \
	one=$$(printf '%s' "$$v" | tr '\n' ' '); \
	printf "  %-20s = %s\n" "$$k" "$$one"; \
	done

# GitHub Actions 출력용 포맷 래퍼
env-github: ## 🔧 GitHub Actions용 형식으로 출력 (VARS/ENV_VARS/PREFIX/ALL/SKIP_EMPTY/SHOW_SECRETS)
	@$(MAKE) --no-print-directory -f $(firstword $(MAKEFILE_LIST)) env-show FORMAT=github VARS='$(VARS)' ENV_VARS='$(ENV_VARS)' PREFIX='$(PREFIX)' ALL='$(ALL)' SKIP_EMPTY='$(SKIP_EMPTY)' SHOW_SECRETS='$(SHOW_SECRETS)'