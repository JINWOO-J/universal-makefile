#!/usr/bin/env bash
# scripts/lib_scaffold.sh — Shared scaffolding helpers
# Exposes:
#   - umc_scaffold_project_files
#   - umc_create_main_makefile
#   - umc_create_project_config
#   - umc_update_gitignore
#   - umc_create_environments
#   - umc_create_sample_compose

set -euo pipefail

# log_* should be provided by caller; define no-op fallbacks
type log_info >/dev/null 2>&1 || log_info() { echo "$*"; }
type log_success >/dev/null 2>&1 || log_success() { echo "$*"; }
type log_warn >/dev/null 2>&1 || log_warn() { echo "$*"; }

umc_scaffold_project_files() {
  umc_create_main_makefile "$@"
  umc_create_project_config "$@"
  umc_update_gitignore "$@"
  umc_create_environments "$@"
}

umc_create_main_makefile() {
  local makefile_dir_var
  makefile_dir_var="${MAKEFILE_DIR:-.makefile-system}"

  local universal_makefile="Makefile.universal"
  if [[ ! -f "$universal_makefile" ]]; then
    log_info "Creating ${universal_makefile}..."
    cat > "$universal_makefile" << 'EOF'
# === Created by Universal Makefile System Installer ===
# This file is the entry point for the universal makefile system.
# It should be included by the project's main Makefile.

.DEFAULT_GOAL := help

# 1. Project config
ifeq ($(wildcard project.mk),)
    $(warning project.mk not found. Run 'install.sh install')
endif
-include project.mk
-include .project.local.mk

# 2. Environments
ENV ?= development
-include environments/$(ENV).mk
-include .project.local.mk

# 3. Core system modules
include $(MAKEFILE_DIR)/makefiles/core.mk
include $(MAKEFILE_DIR)/makefiles/help.mk
include $(MAKEFILE_DIR)/makefiles/version.mk
include $(MAKEFILE_DIR)/makefiles/docker.mk
include $(MAKEFILE_DIR)/makefiles/compose.mk
include $(MAKEFILE_DIR)/makefiles/git-flow.mk
include $(MAKEFILE_DIR)/makefiles/cleanup.mk
EOF
    log_success "${universal_makefile} created"
  fi

  local main_makefile="Makefile"
  if [[ ! -f ${main_makefile} ]]; then
    log_info "Creating ${main_makefile}..."
    cat > "${main_makefile}" << EOF
# === Created by Universal Makefile System Installer ===
MAKEFILE_SYSTEM_DIR := ${makefile_dir_var}
MAKEFILE_DIR := \$(MAKEFILE_SYSTEM_DIR)
include Makefile.universal
EOF
    log_success "${main_makefile} created"
  fi
}

umc_create_project_config() {
  if [[ -f "project.mk" ]]; then return 0; fi
  log_info "Creating project.mk..."
  local default_name; default_name=$(basename "$(pwd)")
  local default_repo_hub="mycompany"
  if git remote get-url origin >/dev/null 2>&1; then
    local url; url=$(git remote get-url origin)
    [[ "$url" =~ github.com[:/]([^/]+) ]] && default_repo_hub="${BASH_REMATCH[1]}"
  fi
  cat > "project.mk" << EOF
# === Created by Universal Makefile System Installer ===
REPO_HUB = ${default_repo_hub}
NAME = ${default_name}
VERSION = v1.0.0

MAIN_BRANCH = main
DEVELOP_BRANCH = develop

DOCKERFILE_PATH = Dockerfile
DOCKER_BUILD_ARGS =

COMPOSE_FILE = docker-compose.yml
DEV_COMPOSE_FILE = docker-compose.dev.yml
PROD_COMPOSE_FILE = docker-compose.prod.yml
MAKEFILE_DIR = ${MAKEFILE_DIR:-.makefile-system}
EOF
  log_success "project.mk created"
}

umc_update_gitignore() {
  log_info "Updating .gitignore..."
  local entries=(
    "# Universal Makefile System"
    ".project.local.mk"
    ".NEW_VERSION.tmp"
    ".env"
    "environments/*.local.mk"
  )
  [[ ! -f .gitignore ]] && touch .gitignore
  local e
  for e in "${entries[@]}"; do
    grep -qxF "$e" .gitignore || echo "$e" >> .gitignore
  done
  log_success ".gitignore updated"
}

umc_create_environments() {
  [[ -d "environments" ]] || mkdir -p environments
  if [[ ! -f environments/development.mk ]]; then
    log_info "Creating environments/development.mk..."
    cat > environments/development.mk << 'EOF'
# === Created by Universal Makefile System Installer ===
DEBUG = true
DOCKER_BUILD_OPTION += --progress=plain
COMPOSE_FILE = docker-compose.dev.yml
EOF
  fi
  if [[ ! -f environments/production.mk ]]; then
    log_info "Creating environments/production.mk..."
    cat > environments/production.mk << 'EOF'
# === Created by Universal Makefile System Installer ===
DEBUG = false
DOCKER_BUILD_OPTION += --no-cache
COMPOSE_FILE = docker-compose.prod.yml
EOF
  fi
  log_success "Environment configs ensured"
}

umc_create_sample_compose() {
  if [[ -f "docker-compose.dev.yml" ]]; then return 0; fi
  log_info "Creating docker-compose.dev.yml..."
  cat > docker-compose.dev.yml << 'EOF'
# === Created by Universal Makefile System Installer ===
#version: '3.8'
services:
  app:
    image: ${REPO_HUB}/${NAME}:${TAGNAME}
    ports:
      - "3000:3000"
    environment:
      - NODE_ENV=production
    restart: unless-stopped
EOF
  log_success "Sample docker-compose.dev.yml created"
}

#!/usr/bin/env bash
# scripts/lib_scaffold.sh
# Shared scaffolding helpers for Universal Makefile System
# - Safe to source. Uses caller's log_* if available; falls back to echo.

# ----- Logging fallbacks -----
if ! declare -F log_info >/dev/null 2>&1; then log_info() { echo "$*"; }; fi
if ! declare -F log_success >/dev/null 2>&1; then log_success() { echo "$*"; }; fi
if ! declare -F log_warn >/dev/null 2>&1; then log_warn() { echo "$*"; }; fi

# ----- Scaffold project files minimal set -----
umc_scaffold_project_files() {
  # usage: umc_scaffold_project_files MAKEFILE_SYSTEM_DIR
  local mf_dir="${1:-.makefile-system}"

  if [ ! -f "Makefile.universal" ]; then
    cat > Makefile.universal << 'EOF'
# === Created by Universal Makefile System (scaffold) ===
MAKEFILE_SYSTEM_DIR ?= .makefile-system
MAKEFILE_DIR ?= $(MAKEFILE_SYSTEM_DIR)
-include project.mk
-include .project.local.mk
ENV ?= development
-include environments/$(ENV).mk
-include .project.local.mk
include $(MAKEFILE_DIR)/makefiles/core.mk
include $(MAKEFILE_DIR)/makefiles/help.mk
include $(MAKEFILE_DIR)/makefiles/version.mk
include $(MAKEFILE_DIR)/makefiles/docker.mk
include $(MAKEFILE_DIR)/makefiles/compose.mk
include $(MAKEFILE_DIR)/makefiles/git-flow.mk
include $(MAKEFILE_DIR)/makefiles/cleanup.mk
EOF
    log_success "Makefile.universal scaffolded"
  fi

  if [ ! -f "Makefile" ]; then
    cat > Makefile << 'EOF'
# === Created by Universal Makefile System (scaffold) ===
MAKEFILE_SYSTEM_DIR := .makefile-system
MAKEFILE_DIR := $(MAKEFILE_SYSTEM_DIR)
include Makefile.universal
EOF
    log_success "Makefile scaffolded"
  fi

  if [ ! -f "project.mk" ]; then
    if [ -f "${mf_dir}/templates/project.mk.template" ]; then
      cp "${mf_dir}/templates/project.mk.template" project.mk
      log_success "project.mk created from template"
    else
      cat > project.mk << 'EOF'
# === Created by Universal Makefile System (scaffold) ===
NAME = $(notdir $(CURDIR))
MAKEFILE_DIR = .makefile-system
EOF
      log_success "project.mk scaffolded (minimal)"
    fi
  fi
}

# ----- Create main Makefile set (Universal) -----
umc_create_main_makefile() {
  # usage: umc_create_main_makefile MAKEFILE_DIR
  local mf_dir="$1"
  local universal_makefile="Makefile.universal"
  log_info "Creating ${universal_makefile}..."
  cat > "$universal_makefile" << 'EOF'
# === Created by Universal Makefile System Installer ===
# Entry point for the universal makefile system. Include in main Makefile.

.DEFAULT_GOAL := help

ifeq ($(wildcard project.mk),)
    $(error project.mk not found. Please run installer to generate it.)
endif
include project.mk

ENV ?= development
-include environments/$(ENV).mk
-include .project.local.mk

include $(MAKEFILE_DIR)/makefiles/core.mk
include $(MAKEFILE_DIR)/makefiles/help.mk
include $(MAKEFILE_DIR)/makefiles/version.mk
include $(MAKEFILE_DIR)/makefiles/docker.mk
include $(MAKEFILE_DIR)/makefiles/compose.mk
include $(MAKEFILE_DIR)/makefiles/git-flow.mk
include $(MAKEFILE_DIR)/makefiles/cleanup.mk
EOF
  log_success "${universal_makefile} created"

  local main_makefile="Makefile"
  if [[ ! -f ${main_makefile} ]]; then
    log_info "Creating main ${main_makefile}..."
    cat > "${main_makefile}" << EOF
# === Created by Universal Makefile System Installer ===
MAKEFILE_SYSTEM_DIR := ${mf_dir}
MAKEFILE_DIR := \$(MAKEFILE_SYSTEM_DIR)
include Makefile.universal
EOF
    log_success "${main_makefile} created"
  fi
}

# ----- Create project.mk with defaults -----
umc_create_project_config() {
  # usage: umc_create_project_config MAKEFILE_DIR FORCE_INSTALL
  local mf_dir="$1" force_flag="${2:-false}"
  [[ -f "project.mk" && "${force_flag}" != true ]] && return 0
  log_info "Creating project.mk..."
  local default_name=$(basename "$(pwd)")
  local default_repo_hub="mycompany"
  if git remote get-url origin >/dev/null 2>&1; then
    local url=$(git remote get-url origin)
    [[ "$url" =~ github.com[:/]([^/]+) ]] && default_repo_hub="${BASH_REMATCH[1]}"
  fi
  cat > "project.mk" << EOF
# === Created by Universal Makefile System Installer ===
REPO_HUB = $default_repo_hub
NAME = $default_name
VERSION = v1.0.0

MAIN_BRANCH = main
DEVELOP_BRANCH = develop

DOCKERFILE_PATH = Dockerfile
DOCKER_BUILD_ARGS =

COMPOSE_FILE = docker-compose.yml
DEV_COMPOSE_FILE = docker-compose.dev.yml
PROD_COMPOSE_FILE = docker-compose.prod.yml
MAKEFILE_DIR = $mf_dir
EOF
  log_success "project.mk created"
}

# ----- Update .gitignore with common entries -----
umc_update_gitignore() {
  log_info "Updating .gitignore..."
  local entries=(
    "# Universal Makefile System"
    ".project.local.mk"
    ".NEW_VERSION.tmp"
    ".env"
    "environments/*.local.mk"
  )
  [[ ! -f .gitignore ]] && touch .gitignore
  for e in "${entries[@]}"; do grep -qxF "$e" .gitignore || echo "$e" >> .gitignore; done
  log_success ".gitignore updated"
}

# ----- Create environments configs -----
umc_create_environments() {
  # usage: umc_create_environments FORCE_INSTALL
  local force_flag="${1:-false}"
  [[ -d "environments" && "${force_flag}" != true ]] && return 0
  log_info "Creating environments/..."
  mkdir -p environments
  cat > environments/development.mk << 'EOF'
# === Created by Universal Makefile System Installer ===
DEBUG = true
DOCKER_BUILD_OPTION += --progress=plain
COMPOSE_FILE = docker-compose.dev.yml
EOF
  cat > environments/production.mk << 'EOF'
# === Created by Universal Makefile System Installer ===
DEBUG = false
DOCKER_BUILD_OPTION += --no-cache
COMPOSE_FILE = docker-compose.prod.yml
EOF
  log_success "Environment configs created"
}

# ----- Create sample compose (dev) -----
umc_create_sample_compose() {
  # usage: umc_create_sample_compose FORCE_INSTALL
  local force_flag="${1:-false}"
  [[ -f "docker-compose.dev.yml" && "${force_flag}" != true ]] && return 0
  log_info "Creating docker-compose.dev.yml..."
  cat > docker-compose.dev.yml << 'EOF'
# === Created by Universal Makefile System Installer ===
#version: '3.8'
services:
  app:
    image: ${REPO_HUB}/${NAME}:${TAGNAME}
    ports:
      - "3000:3000"
    environment:
      - NODE_ENV=production
    restart: unless-stopped
EOF
  log_success "Sample docker-compose.dev.yml created"
}
