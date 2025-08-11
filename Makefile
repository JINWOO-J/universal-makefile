# ================================================================
# Universal Makefile System - Main Entry Point
# ================================================================

.DEFAULT_GOAL := help

# 설치 방식 자동 감지
ifneq (,$(wildcard .makefile-system/))
    # Submodule 방식
    MAKEFILE_DIR := .makefile-system
    MAKEFILE_TYPE := submodule
else ifneq (,$(wildcard makefiles/core.mk))
    # Script 설치 방식
    MAKEFILE_DIR := .
    MAKEFILE_TYPE := script
else
    $(error Universal Makefile System not found. Please run install script first.)
endif

# 프로젝트 설정 로드 (필수)
ifeq (,$(wildcard project.mk))
    $(error project.mk not found. Please create it from template: cp $(MAKEFILE_DIR)/templates/project.mk.template project.mk)
endif
include project.mk

# 환경별 설정 로드 (선택)
ENV ?= development
-include environments/$(ENV).mk

# 로컬 개발자 설정 로드 (선택, 최고 우선순위)
-include .project.local.mk

# 공통 모듈들 로드 (순서 중요!)
include $(MAKEFILE_DIR)/makefiles/core.mk
include $(MAKEFILE_DIR)/makefiles/help.mk
include $(MAKEFILE_DIR)/makefiles/version.mk
include $(MAKEFILE_DIR)/makefiles/docker.mk
include $(MAKEFILE_DIR)/makefiles/compose.mk
include $(MAKEFILE_DIR)/makefiles/git-flow.mk
include $(MAKEFILE_DIR)/makefiles/cleanup.mk

# 메인 타겟들 정의
.PHONY: all release

all: env update-version build ## 🎯 Build everything (env + version + build)
release: all push tag-latest ## 🚀 Full release process (build + push + tag latest)

# 시스템 관리 타겟들
update-makefile-system: ## 🔧 Update makefile system
ifeq ($(MAKEFILE_TYPE),submodule)
	@$(call colorecho, "🔄 Updating makefile system via git submodule...")
	@git submodule update --remote $(MAKEFILE_DIR)
	@$(call colorecho, "✅ Makefile system updated successfully")
else
	@$(call colorecho, "⚠️  Script installation detected. Please run install.sh manually to update")
endif

show-makefile-info: ## 🔧 Show makefile system information
	@echo "$(BLUE)Makefile System Information:$(RESET)"
	@echo "  Installation Type: $(MAKEFILE_TYPE)"
	@echo "  Makefile Directory: $(MAKEFILE_DIR)"
	@echo "  System Version: $(shell cat $(MAKEFILE_DIR)/VERSION 2>/dev/null || echo 'unknown')"
	@echo "  Project: $(NAME) $(VERSION)"

# 프로젝트별 커스텀 타겟들은 여기 아래에 추가
# 예시:
# custom-deploy: ## 🚀 Deploy to custom infrastructure
# 	@echo "Custom deployment for $(NAME)..."