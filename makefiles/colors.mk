# ANSI Color codes
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[0;33m
BLUE := \033[0;34m
MAGENTA := \033[0;35m
CYAN := \033[0;36m
RESET := \033[0m

# define colorecho
# 	@echo "$(BLUE)$(1)$(RESET)"
# endef

# define success
# 	@echo "$(GREEN)$(1)$(RESET)"
# endef

# define warn
# 	@echo "$(YELLOW)$(1)$(RESET)"
# endef

# define error
# 	@echo "$(RED)$(1)$(RESET)"
# endef


# define colorecho
# 	@printf '\033[0;34m%s\033[0m\n' $(1)
# endef

# define success
# 	@printf '\033[0;32m%s\033[0m\n' $(1)
# endef

# define warn
# 	@printf '\033[0;33m%s\033[0m\n' $(1)
# endef

define print_color
	echo "$(1)$(2)$(RESET)"
endef

define print_error
	echo "$(RED) ❌ $(2)$(RESET)"
endef


# Makefile에서 모든 인자를 받는 옵션은 없고 ","를 다른 아규먼트로 인식하는 경우가 있음. "을 없애고 쓰거나, 아래 형태로 10개 받기
define colorecho
	echo "$(BLUE)$(1) $(2) $(3) $(4) $(5) $(6) $(7) $(8) $(9) $(10)$(RESET)"
endef

# define color_echo
# 	echo "$(1)$(2)$(RESET)"
# endef

define success_silent
	@echo "$(GREEN)✅ $(1) $(2) $(3) $(4) $(5) $(6) $(7) $(8) $(9) $(10)$(RESET)"
endef

define warn_silent
	@echo "$(YELLOW)⚠️  $(1) $(2) $(3) $(4) $(5) $(6) $(7) $(8) $(9) $(10)$(RESET)"
endef

define error_silent
	@echo "$(RED)❌ $(1) $(2) $(3) $(4) $(5) $(6) $(7) $(8) $(9) $(10)$(RESET)" >&2
endef

define blue_silent
	@echo "$(BLUE)$(1) $(2) $(3) $(4) $(5) $(6) $(7) $(8) $(9) $(10)$(RESET)"
endef

define green_silent
	@echo "$(GREEN)$(1) $(2) $(3) $(4) $(5) $(6) $(7) $(8) $(9) $(10)$(RESET)"
endef

define yellow_silent
	@echo "$(YELLOW)$(1) $(2) $(3) $(4) $(5) $(6) $(7) $(8) $(9) $(10)$(RESET)"
endef

define red_silent
	@echo "$(RED)$(1) $(2) $(3) $(4) $(5) $(6) $(7) $(8) $(9) $(10)$(RESET)"
endef

define success
	echo "$(GREEN)✅ $(1) $(2) $(3) $(4) $(5) $(6) $(7) $(8) $(9) $(10)$(RESET)"
endef

define warn
	echo "$(YELLOW)⚠️  $(1) $(2) $(3) $(4) $(5) $(6) $(7) $(8) $(9) $(10)$(RESET)"
endef

define error
	echo "$(RED)❌ $(1) $(2) $(3) $(4) $(5) $(6) $(7) $(8) $(9) $(10)$(RESET)" >&2
endef

define blue
	echo "$(BLUE)$(1) $(2) $(3) $(4) $(5) $(6) $(7) $(8) $(9) $(10)$(RESET)"
endef

# ----------------------------------------------------------------
# 별칭 (Aliases)
# - 중복을 피하고 일관성을 유지하기 위해 기존 이름들을 새 이름에 연결합니다.
# ----------------------------------------------------------------
colorecho = $(call blue)
yellow = $(call warn)
colorecho_silent = $(call blue_silent)

# colorecho = @echo "$(BLUE)$(1)$(RESET)"
# blue = @echo "$(BLUE)$(1)$(RESET)"
# green = @echo "$(GREEN)$(1)$(RESET)"
# yellow = @echo "$(YELLOW)$(1)$(RESET)"
# red = @echo "$(RED)$(1)$(RESET)"


# Shell script 용 color 함수 export
export COLORECHO = 'printf "%b%s%b\n" "$(BLUE)" "$$1" "$(RESET)"'
export SUCCESS = 'printf "%b%s%b\n" "$(GREEN)" "$$1" "$(RESET)"'
export WARNING = 'printf "%b%s%b\n" "$(YELLOW)" "$$1" "$(RESET)"'
export ERROR = 'printf "%b%s%b\n" "$(RED)" "$$1" "$(RESET)"'

# Shell에서 사용할 함수들을 환경변수로 export
export BLUE
export GREEN
export YELLOW
export RED
export RESET
