# ANSI Color codes
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[0;33m
BLUE := \033[0;34m
MAGENTA := \033[0;35m
CYAN := \033[0;36m
RESET := \033[0m

# Makefile 함수용
# define colorecho
# 	@printf '\033[0;34m%s\033[0m\n' "$(1)"
# endef

# define success
# 	@printf '\033[0;32m%s\033[0m\n' "$(1)"
# endef

# define warn
# 	@printf '\033[0;33m%s\033[0m\n' "$(1)"
# endef

# define error
# 	@printf '\033[0;31m%s\033[0m\n' "$(1)"
# endef

colorecho = printf '\033[0;34m%s\033[0m\n' "$(1)"
success   = printf '\033[0;32m%s\033[0m\n' "$(1)"
warn      = printf '\033[0;33m%s\033[0m\n' "$(1)"
error     = printf '\033[0;31m%s\033[0m\n' "$(1)"


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
