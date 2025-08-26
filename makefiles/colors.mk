# ANSI Color codes
# RED := \033[0;31m
# GREEN := \033[0;32m
# YELLOW := \033[0;33m
# BLUE := \033[0;34m
# MAGENTA := \033[0;35m
# CYAN := \033[0;36m
# RESET := \033[0m

ESC    := $(shell printf '\033')
BLUE   := $(ESC)[34m
GREEN  := $(ESC)[32m
YELLOW := $(ESC)[33m
RED    := $(ESC)[31m
MAGENTA := $(ESC)[35m
CYAN := $(ESC)[36m
RESET  := $(ESC)[0m

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
	$(ECHO_CMD) " $(1)$(2)$(RESET)"
endef

define print_error
	$(ECHO_CMD) "$(RED) ❌ $(1)$(RESET)"
endef


# define color_echo
# 	echo "$(1)$(2)$(RESET)"
# endef

# define blue
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

# define yellow
# 	@echo "$(YELLOW)$(1)$(RESET)"
# endef

# define colorecho_silent
# 	@echo "$(BLUE)$(1)$(RESET)"
# endef
# define success_silent
# 	@echo "$(GREEN)✅ $(1)$(RESET)"
# endef
# define warn_silent
# 	@echo "$(YELLOW)⚠️  $(1)$(RESET)"
# endef
# define error_silent
# 	@echo "$(RED)❌ $(1)$(RESET)" >&2
# endef

# colorecho = @echo "$(BLUE)$(1)$(RESET)"
# blue = @echo "$(BLUE)$(1)$(RESET)"
# green = @echo "$(GREEN)$(1)$(RESET)"
# yellow = @echo "$(YELLOW)$(1)$(RESET)"
# red = @echo "$(RED)$(1)$(RESET)"

define colorecho
	$(ECHO_CMD) "$(BLUE)$(1) $(2) $(3) $(4) $(5) $(6) $(7) $(8) $(9) $(10)$(RESET)"
endef

define success_silent
	@$(ECHO_CMD) "$(GREEN)✅ $(1) $(2) $(3) $(4) $(5) $(6) $(7) $(8) $(9) $(10)$(RESET)"
endef

define warn_silent
	@$(ECHO_CMD) "$(YELLOW)⚠️  $(1) $(2) $(3) $(4) $(5) $(6) $(7) $(8) $(9) $(10)$(RESET)"
endef

define error_silent
	@$(ECHO_CMD) "$(RED)❌ $(1) $(2) $(3) $(4) $(5) $(6) $(7) $(8) $(9) $(10)$(RESET)" >&2
endef

define blue_silent
	@$(ECHO_CMD) "$(BLUE)$(1) $(2) $(3) $(4) $(5) $(6) $(7) $(8) $(9) $(10)$(RESET)"
endef

define green_silent
	@$(ECHO_CMD) "$(GREEN)$(1) $(2) $(3) $(4) $(5) $(6) $(7) $(8) $(9) $(10)$(RESET)"
endef

define yellow_silent
	@$(ECHO_CMD) "$(YELLOW)$(1) $(2) $(3) $(4) $(5) $(6) $(7) $(8) $(9) $(10)$(RESET)"
endef

define red_silent
	@$(ECHO_CMD) "$(RED)$(1) $(2) $(3) $(4) $(5) $(6) $(7) $(8) $(9) $(10)$(RESET)"
endef

define success
	$(ECHO_CMD) "$(GREEN)✅ $(1) $(2) $(3) $(4) $(5) $(6) $(7) $(8) $(9) $(10)$(RESET)"
endef

define warn
	$(ECHO_CMD) "$(YELLOW)⚠️  $(1) $(2) $(3) $(4) $(5) $(6) $(7) $(8) $(9) $(10)$(RESET)"
endef

define fail
	$(ECHO_CMD) "$(RED)❌ $(1) $(2) $(3) $(4) $(5) $(6) $(7) $(8) $(9) $(10)$(RESET)" >&2
endef

define blue
	$(ECHO_CMD) "$(BLUE)$(1) $(2) $(3) $(4) $(5) $(6) $(7) $(8) $(9) $(10)$(RESET)"
endef

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
