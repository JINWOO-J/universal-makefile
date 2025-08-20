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
type log_info    >/dev/null 2>&1 || log_info()    { echo "$*"; }
type log_success >/dev/null 2>&1 || log_success() { echo "$*"; }
type log_warn    >/dev/null 2>&1 || log_warn()    { echo "$*"; }

# debug helper (enabled when DEBUG_MODE=true)
umc_debug() {
  if [[ "${DEBUG_MODE:-false}" == "true" ]]; then
    log_info "[scaffold][debug] $*"
  fi
}

umc_scaffold_project_files() {
  umc_debug "begin: MAKEFILE_DIR=${MAKEFILE_DIR:-universal-makefile} PWD=$(pwd) $*"
  umc_create_main_makefile "${makefile_dir}"
  umc_create_project_config "${makefile_dir}"
  umc_update_gitignore "$@"
  umc_create_environments "$@"
  umc_debug "end"
}

umc_create_main_makefile() {
  local makefile_dir_var="${1:-${MAKEFILE_DIR:-universal-makefile}}" # CHANGED: 첫 번째 인자 우선 사용
  makefile_dir_var="${MAKEFILE_DIR:-universal-makefile}"
  umc_debug "umc_create_main_makefile: makefile_dir_var=${makefile_dir_var}"

  local universal_makefile="Makefile.universal"
  if [[ ! -f "${universal_makefile}" ]]; then
    log_info "Creating ${universal_makefile}..."
    umc_debug "writing ${universal_makefile}"

    # header (literal)
    cat > "${universal_makefile}" << 'EOF_HEAD'
# === Created by Universal Makefile System Installer ===
# This file is the entry point for the universal makefile system.
# It should be included by the project's main Makefile.
EOF_HEAD

    # MAKEFILE_DIR 기본값 (이미 정의되어 있으면 그대로 사용)
    echo "MAKEFILE_DIR ?= ${makefile_dir_var}" >> "${universal_makefile}"

    # body (literal)
    cat >> "${universal_makefile}" << 'EOF_BODY'

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
EOF_BODY
    log_success "${universal_makefile} created"
  fi

  local main_makefile="Makefile"
  if [[ ! -f "${main_makefile}" ]]; then
    log_info "Creating ${main_makefile}..."
    umc_debug "writing ${main_makefile} (MAKEFILE_SYSTEM_DIR=${makefile_dir_var})"
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
  if [[ -f "project.mk" ]]; then
    umc_debug "project.mk already exists; skipping"
    return 0
  fi

  log_info "Creating project.mk..."
  local default_name default_repo_hub url
  default_name="$(basename "$(pwd)")"
  default_repo_hub="mycompany"

  if git remote get-url origin >/dev/null 2>&1; then
    url="$(git remote get-url origin || true)"
    if [[ "${url:-}" =~ github\.com[:/]([^/]+) ]]; then
      default_repo_hub="${BASH_REMATCH[1]}"
    fi
  fi

  umc_debug "umc_create_project_config: NAME=${default_name} REPO_HUB=${default_repo_hub} MAKEFILE_DIR=${MAKEFILE_DIR:-universal-makefile}"

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
MAKEFILE_DIR = ${MAKEFILE_DIR:-universal-makefile}
EOF
  log_success "project.mk created"
}

umc_update_gitignore() {
  log_info "Updating .gitignore..."
  umc_debug "ensuring common entries in .gitignore"

  local entries=(
    "# Universal Makefile System"
    ".project.local.mk"
    ".NEW_VERSION.tmp"
    ".env"
    "environments/*.local.mk"
  )

  [[ -f ".gitignore" ]] || : > .gitignore

  local e
  for e in "${entries[@]}"; do
    # 중복 방지(정확히 같은 줄이 없을 때만 추가)
    if ! grep -qxF "$e" .gitignore 2>/dev/null; then
      echo "$e" >> .gitignore
    fi
  done
  log_success ".gitignore updated"
}

umc_create_environments() {
  [[ -d "environments" ]] || mkdir -p "environments"

  if [[ ! -f "environments/development.mk" ]]; then
    log_info "Creating environments/development.mk..."
    umc_debug "writing environments/development.mk"
    cat > "environments/development.mk" << 'EOF'
# === Created by Universal Makefile System Installer ===
DEBUG = true
DOCKER_BUILD_OPTION += --progress=plain
COMPOSE_FILE = docker-compose.dev.yml
EOF
  fi

  if [[ ! -f "environments/production.mk" ]]; then
    log_info "Creating environments/production.mk..."
    umc_debug "writing environments/production.mk"
    cat > "environments/production.mk" << 'EOF'
# === Created by Universal Makefile System Installer ===
DEBUG = false
DOCKER_BUILD_OPTION += --no-cache
COMPOSE_FILE = docker-compose.prod.yml
EOF
  fi

  log_success "Environment configs ensured"
}

umc_create_sample_compose() {
  if [[ -f "docker-compose.dev.yml" ]]; then
    umc_debug "docker-compose.dev.yml already exists; skipping"
    return 0
  fi

  log_info "Creating docker-compose.dev.yml..."
  umc_debug "writing docker-compose.dev.yml"
  cat > "docker-compose.dev.yml" << 'EOF'
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
