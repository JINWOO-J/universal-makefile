#!/bin/bash
set -euo pipefail
unalias -a 2>/dev/null || true

# 색상 정의
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    BLUE=$(tput setaf 4)
    RESET=$(tput sgr0)
else
    RED=""; GREEN=""; YELLOW=""; BLUE=""; RESET=""
fi

# 로깅 함수
log_info()    { echo "${BLUE}ℹ️  $1${RESET}"; }
log_success() { echo "${GREEN}✅ $1${RESET}"; }
log_warn()    { echo "${YELLOW}⚠️  $1${RESET}"; }
log_error()   { echo "${RED}❌ $1${RESET}" >&2; }

MAKEFILE_DIR=".makefile-system"

GITHUB_OWNER="jinwoo-j"
GITHUB_REPO="universal-makefile"
GITHUB_REPO_SLUG="${GITHUB_OWNER}/${GITHUB_REPO}"
MAIN_BRANCH="master"

REPO_URL="https://github.com/${GITHUB_REPO_SLUG}"
INSTALLER_SCRIPT_URL="https://raw.githubusercontent.com/${GITHUB_REPO_SLUG}/${MAIN_BRANCH}/install.sh"

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
INSTALLATION_TYPE="submodule"

FORCE_INSTALL=false
DRY_RUN=false
BACKUP=false
EXISTING_PROJECT=false
DEBUG_MODE=false

usage() {
    cat <<EOF
Universal Makefile System Installer

Usage: $0 <command> [options]

Commands:
    install             Install the Universal Makefile System (default)
    update | pull       Update the Universal Makefile System to the latest version
    uninstall           Remove all files created by this installer
    self-update         Update this installer script itself
    app | setup-app     Setup example app
    diff                Show differences between local and remote files
    help                Show this help message

Common options:
    --force             Force installation/uninstall/update actions
    --dry-run           Show actions without performing them
    --backup            Backup files before removing (uninstall only)
    -d, --debug         Show detailed debug info on failure # <-- 이 줄을 추가합니다.

Install options:
    --copy              Install by copying files instead of submodule
    --existing-project  Setup in existing project (preserve existing files)

Examples:
    $0 install --copy
    $0 uninstall --dry-run --backup
    $0 self-update
    $0 help

Repository: $REPO_URL
EOF
}

resolve_flag() {
    local env_var_name=$1
    local long_flag=$2
    local short_flag=$3
    local all_args=("${@:4}")

    for arg in "${all_args[@]:-}"; do
        if [[ "$arg" == "$long_flag" || (-n "$short_flag" && "$arg" == "$short_flag") ]]; then
            echo "true"
            return
        fi
    done

    eval "local env_val=\"\${$env_var_name:-}\""
    if [ -n "${env_val+x}" ]; then
        if [[ "$(echo "$env_val" | tr '[:upper:]' '[:lower:]')" == "true" ]]; then
            echo "true"
        else
            echo "false"
        fi
    else
        echo "false"
    fi
}

parse_common_args() {
    FORCE_INSTALL=$(resolve_flag "FORCE" "--force" "" "$@")
    DRY_RUN=$(resolve_flag "DRY_RUN" "--dry-run" "" "$@")
    BACKUP=$(resolve_flag "BACKUP" "--backup" "" "$@")
    DEBUG_MODE=$(resolve_flag "DEBUG" "--debug" "-d" "$@")

    if [[ "${DEBUG_MODE}" == "true" ]]; then
        log_info "Common flags resolved as follows:"
        echo "  - FORCE_INSTALL: ${FORCE_INSTALL}"
        echo "  - DRY_RUN      : ${DRY_RUN}"
        echo "  - BACKUP       : ${BACKUP}"
        echo "  - DEBUG_MODE   : ${DEBUG_MODE}"
    fi

    local POSITIONAL_ARGS=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force|--dry-run|--backup|-d|--debug)
                shift ;;
            *)
                POSITIONAL_ARGS+=("$1")
                shift ;;
        esac
    done
    eval set -- "${POSITIONAL_ARGS[@]:-}"
}


parse_install_args() {
    INSTALLATION_TYPE="submodule"
    EXISTING_PROJECT=false

    local remaining_args=()
    while [[ $# -gt 0 ]]; do
        case $1 in
            --copy)
                INSTALLATION_TYPE="copy"; shift ;;
            --existing-project)
                EXISTING_PROJECT=true; shift ;;
            --help|-h)
                usage; exit 0 ;;
            *)
                remaining_args+=("$1"); shift ;;
        esac
    done
    parse_common_args "${remaining_args[@]:-}"

    log_info "Installation type: $INSTALLATION_TYPE"
}

parse_uninstall_args() {
    parse_common_args "$@"
}


parse_update_args() {
    parse_common_args "$@"
}


has_universal_id() {
    local file=$1
    [[ -f "$file" ]] && grep -q "Universal Makefile System" "$file"
}

check_requirements() {
    log_info "Checking requirements..."
    if [[ "$INSTALLATION_TYPE" == "submodule" ]]; then
        if ! command -v git >/dev/null 2>&1; then
            log_error "Git is required for submodule installation"
            exit 1
        fi
        if ! git rev-parse --git-dir >/dev/null 2>&1; then
            log_error "Not in a git repository. Initialize git first or use --copy"
            exit 1
        fi
    fi
    if ! command -v make >/dev/null 2>&1; then
        log_error "Make is required"
        exit 1
    fi
    log_success "Requirements check passed"
}


check_existing_installation() {
    if [[ -d "$MAKEFILE_DIR" && ! -f Makefile && ! -f project.mk && ! -d makefiles && ! -f Makefile.universal ]]; then
        log_info "Only submodule detected; proceeding as new installation."
        return 0
    fi

    if [[ -f "Makefile.universal" && "$FORCE_INSTALL" != true ]]; then
        log_error "Makefile.universal already exists. Use --force to overwrite."
        exit 1
    fi

    [[ -d "makefiles" ]] && log_warn "Makefiles directory exists (will not be overwritten)."

    if [[ -f "Makefile" && "$EXISTING_PROJECT" != true ]]; then
        if ! has_universal_id "Makefile"; then
            log_warn "Existing Makefile found (not created by universal-makefile, will NOT be overwritten)."
            log_info "To use Universal Makefile System, add this line to your Makefile:"
            echo -e "${YELLOW}include Makefile.universal${RESET}"
        fi
    fi
}


install_submodule() {
    log_info "Installing as git submodule..."
    if [[ "$FORCE_INSTALL" == true && -d "$MAKEFILE_DIR" ]]; then
        log_info "Removing existing submodule..."
        git submodule deinit -f "$MAKEFILE_DIR" || true
        git rm -f "$MAKEFILE_DIR" || true
        rm -rf ".git/modules/$MAKEFILE_DIR" "$MAKEFILE_DIR"
    fi
    if ! git submodule add "$REPO_URL" "$MAKEFILE_DIR"; then
        if git config --file .gitmodules --get "submodule.$MAKEFILE_DIR.url" >/dev/null 2>&1; then
            log_info "Submodule already exists, continuing..."
        else
            log_error "Failed to add submodule"
            exit 1
        fi
    fi
    git submodule update --init --recursive
    log_success "Submodule installation completed"
}

install_copy() {
    log_info "Installing by copying files..."
    local temp_dir=$(mktemp -d)
    trap "rm -rf $temp_dir" EXIT
    if [[ -f "$SCRIPT_DIR/makefiles/core.mk" ]]; then
        log_info "Using local repository files"
        local source_dir="$SCRIPT_DIR"
    else
        log_info "Cloning from $REPO_URL"
        git clone "$REPO_URL" "$temp_dir/universal-makefile"
        local source_dir="$temp_dir/universal-makefile"
    fi
    [[ "$FORCE_INSTALL" == true || ! -d "makefiles" ]] && cp -r "$source_dir/makefiles" .
    [[ "$FORCE_INSTALL" == true || ! -d "scripts" ]] && cp -r "$source_dir/scripts" . 2>/dev/null || true
    [[ "$FORCE_INSTALL" == true || ! -d "templates" ]] && cp -r "$source_dir/templates" . 2>/dev/null || true
    [[ -f "$source_dir/VERSION" ]] && cp "$source_dir/VERSION" .
    log_success "Copy installation completed"
}

create_main_makefile() {
    local target_file="Makefile.universal"
    local created_universal=false

    if [[ -f "$target_file" ]]; then
        target_file="Makefile.universal"
        created_universal=true
        log_warn "Existing Makefile detected. Creating $target_file instead."
        log_info "To use Universal Makefile System rules, add the following line to your Makefile:"
        echo -e "${YELLOW}include Makefile.universal${RESET}\n"
    fi

    log_info "Creating $target_file..."
    cat > "$target_file" << EOF
# === Created by Universal Makefile System Installer ===
# See universal-makefile system for details

.DEFAULT_GOAL := help

ifneq (,\$(wildcard $MAKEFILE_DIR/))
    MAKEFILE_DIR := $MAKEFILE_DIR
    MAKEFILE_TYPE := $INSTALLATION_TYPE
else ifneq (,\$(wildcard makefiles/core.mk))
    MAKEFILE_DIR := .
    MAKEFILE_TYPE := script
else
    \$(error Universal Makefile System not found)
endif

ifeq (,\$(wildcard project.mk))
    \$(error project.mk not found)
endif
include project.mk

ENV ?= development
-include environments/\$(ENV).mk
-include .project.local.mk

include \$(MAKEFILE_DIR)/makefiles/core.mk
include \$(MAKEFILE_DIR)/makefiles/help.mk
include \$(MAKEFILE_DIR)/makefiles/version.mk
include \$(MAKEFILE_DIR)/makefiles/docker.mk
include \$(MAKEFILE_DIR)/makefiles/compose.mk
include \$(MAKEFILE_DIR)/makefiles/git-flow.mk
include \$(MAKEFILE_DIR)/makefiles/cleanup.mk
EOF
    log_success "$target_file created"

    if [[ ! -f Makefile ]]; then
        echo -e "# Project Makefile\ninclude Makefile.universal\n" > Makefile
        log_success "Created Makefile with 'include Makefile.universal'"
    else
        echo ""
        log_info "To use Universal Makefile System commands, add the following line to your existing Makefile:"
        echo -e "${YELLOW}include Makefile.universal${RESET}"
        echo ""
    fi
}


create_project_config() {
    [[ -f "project.mk" && "$FORCE_INSTALL" == false ]] && return
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
MAKEFILE_DIR = $MAKEFILE_DIR
EOF
    log_success "project.mk created"
}

update_gitignore() {
    log_info "Updating .gitignore..."
    local entries=(
        "# Universal Makefile System"
        ".project.local.mk"
        ".NEW_VERSION.tmp"
        ".env"
        "environments/*.local.mk"
    )
    [[ ! -f .gitignore ]] && touch .gitignore
    for e in "${entries[@]}"; do
        grep -qxF "$e" .gitignore || echo "$e" >> .gitignore
    done
    log_success ".gitignore updated"
}

create_environments() {
    [[ -d "environments" && "$FORCE_INSTALL" == false ]] && return
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

create_sample_compose() {
    [[ -f "docker-compose.dev.yml" && "$FORCE_INSTALL" == false ]] && return
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

show_completion_message() {
    echo ""
    log_success "🎉 Universal Makefile System installation completed!"
    echo "${BLUE}Next steps:${RESET}"
    echo "  make help                # Show all commands"
    echo "  make build               # Build the application"
    echo "  make getting-started     # Guide"
    [[ "$INSTALLATION_TYPE" == "submodule" ]] && echo "  make update-makefile-system  # Update system (submodule)"
    echo ""
}

show_changelog() {
    local repo_dir=$1
    local old_commit="$2"
    local new_commit="$3"

    if [[ -n "$old_commit" && "$old_commit" != "$new_commit" ]]; then
        echo ""
        log_info "Universal Makefile System: Updates applied ($old_commit..$new_commit):"
        git --no-pager -C "$repo_dir" log --oneline "$old_commit..$new_commit"
        echo ""
    fi
}

safe_rm() {
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[dry-run] Would remove: $*"
    else
        [[ "$BACKUP" == true ]] && cp -r "$@" "$backup_dir/" 2>/dev/null || true
        rm -rf "$@"
        log_info "Removed $*"
    fi
}

uninstall() {
    echo "${BLUE}Uninstalling Universal Makefile System...${RESET}"

    local backup_dir=""
    if [[ "$BACKUP" == true ]]; then
        backup_dir=".backup_universal_makefile_$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$backup_dir"
        log_info "Backup enabled. Files will be backed up to $backup_dir"
    fi

    for f in Makefile Makefile.universal project.mk; do
        if has_universal_id "$f"; then
            safe_rm "$f"
            log_info "Removed $f"
        fi
    done

    [[ -f .project.local.mk ]] && safe_rm .project.local.mk
    [[ -f .NEW_VERSION.tmp ]] && safe_rm .NEW_VERSION.tmp
    [[ -f .env ]] && safe_rm .env
    [[ -d environments ]] && safe_rm environments
    [[ -d makefiles ]] && safe_rm makefiles
    [[ -d scripts ]] && safe_rm scripts
    [[ -d templates ]] && safe_rm templates

    if [[ -d "$MAKEFILE_DIR" ]]; then
        if [[ "$FORCE_INSTALL" == true ]]; then
            git submodule deinit -f "$MAKEFILE_DIR" || true
            git rm -f "$MAKEFILE_DIR" || true
            rm -rf ".git/modules/$MAKEFILE_DIR" "$MAKEFILE_DIR"
            log_info "Removed submodule directory ($MAKEFILE_DIR)"
        else
            log_warn "Submodule directory ($MAKEFILE_DIR) not removed. Use --force option to remove."
        fi
    fi

    sed -i.bak '/Universal Makefile System/d;/.project.local.mk/d;/\.env/d' .gitignore 2>/dev/null || true
    rm -f .gitignore.bak

    [[ -f docker-compose.yml ]] && log_warn "docker-compose.yml is not removed (user/project file)."
    [[ -f project.mk ]] && ! has_universal_id project.mk && log_warn "project.mk is not removed (user/project file)."

    log_warn "User project files such as docker-compose.yml are not removed for safety."
    log_success "Uninstallation complete"
}

check_token_validity() {
    if [[ -z "${GITHUB_TOKEN:-}" ]]; then
        log_error "GITHUB_TOKEN is not set or is empty. Aborting."
        return 1
    fi

    log_info "Download failed with a GITHUB_TOKEN. Running automatic authentication check..."

    local owner; owner=$(echo "${REPO_URL}" | sed -E 's|https?://github.com/([^/]+)/.*|\1|')
    local repo; repo=$(echo "${REPO_URL}" | sed -E 's|https?://github.com/[^/]+/([^/]+)|\1|')

    local http_code; http_code=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer ${GITHUB_TOKEN}" https://api.github.com/user)
    if [[ "$http_code" == "401" ]]; then
        log_error "GITHUB_TOKEN Check Failed: HTTP ${http_code} - Bad credentials."
        log_warn "The token is invalid, expired, or has been revoked. Please generate a new token."
        return
    elif [[ "$http_code" != "200" ]]; then
        log_error "Token Check Failed: Received HTTP ${http_code} when checking token validity."
        return
    fi
    log_success "Token Check OK: Token is valid."

    http_code=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer ${GITHUB_TOKEN}" "https://api.github.com/repos/${owner}/${repo}")
    if [[ "$http_code" == "404" ]]; then
        log_error "Permission Check Failed: HTTP ${http_code} - Not Found."
        log_warn "The GITHUB_TOKEN is valid, but it does not have permission to access the '${owner}/${repo}' repository."
        log_warn "Please ensure the GITHUB_TOKEN has the correct 'repo' scope (for Classic PAT) or has been granted access to the repository (for Fine-grained PAT)."
        log_warn "If this is an organization repository, ensure SSO has been authorized for the token."
    elif [[ "$http_code" != "200" ]]; then
        log_error "Permission Check Failed: Received HTTP ${http_code} when checking repository access."
    else
        log_success "Permission Check OK: GITHUB_TOKEN has access to the repository."
        log_warn "All checks passed, but download still failed. There might be a temporary network issue or a problem with the file path/branch name."
    fi
}


self_update() {
    log_info "Updating installer script itself..."
    local tmp_script; tmp_script=$(mktemp)
    local curl_args=("-fsSL"); local wget_args=("-q")

    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        log_info "GITHUB_TOKEN is set. Adding authentication header."
        local auth_header="Authorization: Bearer ${GITHUB_TOKEN}"
        curl_args+=(-H "${auth_header}")
        wget_args+=(--header="${auth_header}")
    fi

    local download_success=true
    if command -v curl >/dev/null 2>&1; then
        curl "${curl_args[@]}" "$INSTALLER_SCRIPT_URL" -o "$tmp_script" || download_success=false
    elif command -v wget >/dev/null 2>&1; then
        wget "${wget_args[@]}" -O "$tmp_script" "$INSTALLER_SCRIPT_URL" || download_success=false
    else
        log_error "curl or wget required for self-update."; exit 1
    fi

    if [[ "$download_success" == true && -s "$tmp_script" ]]; then
        chmod +x "$tmp_script"
        mv "$tmp_script" "$0"
        log_success "Installer script updated successfully!"
    else
        rm -f "$tmp_script"
        log_error "Failed to download installer script."        
        if [[ -n "${GITHUB_TOKEN:-}" ]]; then
            check_token_validity
        else
            log_warn "If this is a private repository, please set the GITHUB_TOKEN environment variable."
        fi
        exit 1
    fi
}


show_diff() {
    echo ""
    log_info "Debug mode enabled. Showing local changes that are blocking the update:"
    git --no-pager -C "$MAKEFILE_DIR" diff --color=always
    echo ""
}

update_makefile_system() {
    log_info "Updating Universal Makefile System..."

    if [[ "$INSTALLATION_TYPE" == "submodule" && -d "$MAKEFILE_DIR" ]]; then
        local old_commit
        old_commit=$(git -C "$MAKEFILE_DIR" rev-parse HEAD 2>/dev/null || echo "")

        git -C "$MAKEFILE_DIR" fetch origin "$MAIN_BRANCH"
        if [[ "$FORCE_INSTALL" == true ]]; then
            git -C "$MAKEFILE_DIR" reset --hard "origin/$MAIN_BRANCH"
            log_success "Submodule forcibly updated to latest commit from remote."
        else
            if ! git -C "$MAKEFILE_DIR" merge "origin/$MAIN_BRANCH"; then
                echo ""
                log_warn "Merge aborted. Showing local changes in '$MAKEFILE_DIR' that are blocking the update:"

                if [[ "$DEBUG_MODE" == true ]]; then
                    show_diff
                else
                    log_info "To see the conflicting changes, run the update again with the --debug flag."
                fi

                echo ""
                log_error "Merge conflict occurred in submodule."
                log_warn "You can resolve manually, or run update again with --force to overwrite local changes."
                exit 1
            fi


            log_success "Submodule updated with merge."
        fi

        local new_commit
        new_commit=$(git -C "$MAKEFILE_DIR" rev-parse HEAD 2>/dev/null || echo "")
        show_changelog "$MAKEFILE_DIR" "$old_commit" "$new_commit"
        echo "👉 Don't forget: git add $MAKEFILE_DIR && git commit to update the submodule pointer!"

    elif [[ "$INSTALLATION_TYPE" == "copy" && -d "makefiles" ]]; then
        local old_commit=""
        if [[ -d makefiles/.git ]]; then
            old_commit=$(git -C makefiles rev-parse HEAD 2>/dev/null || echo "")
        fi

        local temp_dir
        temp_dir=$(mktemp -d)
        trap "rm -rf $temp_dir" EXIT
        log_info "Cloning latest version from $REPO_URL"
        git clone "$REPO_URL" "$temp_dir/universal-makefile"

        cp -r "$temp_dir/universal-makefile/makefiles" .
        cp -r "$temp_dir/universal-makefile/scripts" . 2>/dev/null || true
        cp -r "$temp_dir/universal-makefile/templates" . 2>/dev/null || true
        [[ -f "$temp_dir/universal-makefile/VERSION" ]] && cp "$temp_dir/universal-makefile/VERSION" .
        log_success "Copied latest files from remote."

        local new_commit
        new_commit=$(git -C "$temp_dir/universal-makefile" rev-parse HEAD 2>/dev/null || echo "")

        show_changelog "$temp_dir/universal-makefile" "$old_commit" "$new_commit"
    else
        log_error "Universal Makefile System installation not found. Cannot update."
        exit 1
    fi
}


is_universal_makefile_installed() {
    local ok=true

    if [[ ! -d "${MAKEFILE_DIR}" && ! -d "makefiles" ]]; then
        log_error "Universal Makefile System directory (.makefile-system or makefiles) not found."
        ok=false
    fi

    if [[ ! -f "Makefile.universal" ]]; then
        log_error "Makefile.universal not found."
        ok=false
    fi

    if [[ ! -f "project.mk" ]]; then
        log_error "project.mk not found."
        ok=false
    fi

    if [[ ! -d "environments" || -z "$(ls environments/*.mk 2>/dev/null)" ]]; then
        log_error "No environments/*.mk files found."
        ok=false
    fi

    if [[ -f Makefile ]]; then
        echo ""
        if ! grep -q '^[[:space:]]*include[[:space:]]\+Makefile\.universal' Makefile; then
            log_warn "Makefile does NOT include 'include Makefile.universal'."
            log_info "Add this line to your Makefile to enable Universal Makefile System:"
            echo -e "${YELLOW}include Makefile.universal${RESET} \n\n"
        fi
    fi

    if [[ "$ok" == true ]]; then
        log_success "Universal Makefile System is properly installed 🎉"
        return 0
    else
        log_warn "Universal Makefile System is NOT fully installed."
        return 1
    fi
}


install_github_workflow() {
    log_info "Installing GitHub Actions workflow..."
    mkdir -p .github/workflows

    local src_dir="$MAKEFILE_DIR/github/workflows"
    shopt -s nullglob
    local files=("$src_dir"/*)
    shopt -u nullglob

    if [[ ${#files[@]} -eq 0 ]]; then
        log_warn "No workflows to install in $src_dir"
        return 0
    fi

    log_info "Copying the following workflow files:"
    for f in "${files[@]}"; do
        echo "  - $f"
    done

    cp -rf "${files[@]}" .github/workflows/
    log_success "GitHub Actions workflow installed"
}

setup_app_example() {
    local app_type="${1:-}"

    local examples_dir="$MAKEFILE_DIR/examples"
    [[ ! -d "$examples_dir" ]] && log_error "examples directory not found!" && exit 1

    if [[ -z "$app_type" ]]; then
        echo ""
        log_info "Available example apps:"
        local apps=()
        local i=1
        for dir in "$examples_dir"/*/; do
            local app_name=$(basename "$dir")
            [[ "$app_name" == "environments" ]] && continue
            apps+=("$app_name")
            echo "  $i) $app_name"
            ((i++))
        done
        if [[ ${#apps[@]} -eq 0 ]]; then
            log_warn "No app examples found!"
            exit 1
        fi
        echo ""
        read -rp "Select example to setup (1-${#apps[@]}) [q to quit]: " choice
        [[ "$choice" == "q" || "$choice" == "Q" ]] && log_warn "Aborted by user." && exit 0
        [[ "$choice" =~ ^[0-9]+$ ]] || { log_error "Invalid input"; exit 1; }
        app_type="${apps[$((choice-1))]}"
        [[ -z "$app_type" ]] && log_error "Invalid selection" && exit 1
    fi

    local template_dir="$examples_dir/$app_type"
    [[ ! -d "$template_dir" ]] && log_error "No template directory for '$app_type'" && exit 1

    log_info "Setting up example for '$app_type'..."

    for file in "$template_dir"/*; do
        fname=$(basename "$file")
        if [[ -e "$fname" && "$FORCE_INSTALL" != true ]]; then
            read -rp "File $fname already exists. Overwrite? [y/N]: " yn
            [[ "$yn" =~ ^[Yy]$ ]] || { log_warn "Skipped $fname"; continue; }
        fi
        cp -rf "$file" .

        log_success "Installed $fname"
    done

    log_success "$app_type example setup complete!"
    echo "Try: make help"
}

show_status() {
    log_info "Checking status of the installed Universal Makefile System..."
    echo ""

    if [[ -d "$MAKEFILE_DIR" ]] && (cd "$MAKEFILE_DIR" && git rev-parse --is-inside-work-tree >/dev/null 2>&1); then
        local git_dir="$MAKEFILE_DIR"
        local remote; remote=$(git -C "$git_dir" remote get-url origin 2>/dev/null || echo "N/A")
        local branch; branch=$(git -C "$git_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "N/A")
        local commit; commit=$(git -C "$git_dir" rev-parse --short HEAD 2>/dev/null || echo "N/A")
        local status; status=$(git -C "$git_dir" status --porcelain 2>/dev/null)

        echo "  Installation Type : Submodule"
        echo "  Path              : ${git_dir}"
        echo "  Remote URL        : ${remote}"
        echo "  Branch            : ${branch}"
        echo "  Commit            : ${commit}"
        
        if [[ -n "$status" ]]; then
            log_warn "Status            : Modified (Local changes detected in system files)"
            if [[ "$DEBUG_MODE" == "true" ]]; then
                echo ""
                log_info "Showing local modifications (--debug enabled):"
                git --no-pager -C "$git_dir" diff --color=always
            fi
        else
            log_success "  Status            : Clean"
        fi
    elif [[ -d "makefiles" ]]; then
        echo "  Installation Type : Copied Files"
        if [[ -f "VERSION" ]]; then
            local version; version=$(cat VERSION)
            echo "  Version File      : ${version}"
        else
            echo "  Version File      : Not found"
        fi
        log_warn "  Cannot determine specific git commit for copied files."
    else
        log_error "Universal Makefile System installation not found."
        exit 1
    fi
    echo ""
}


main() {
    local cmd=${1:-install}
    shift || true

    case "$cmd" in
        install)
            parse_install_args "$@"
            check_requirements            
            check_existing_installation
            case "$INSTALLATION_TYPE" in
                submodule) install_submodule ;;
                copy) install_copy ;;
                *) log_error "Invalid installation type: $INSTALLATION_TYPE"; exit 1 ;;
            esac
            create_main_makefile
            create_project_config
            update_gitignore
            create_environments
            [[ "$EXISTING_PROJECT" == false ]] && create_sample_compose
            install_github_workflow
            show_completion_message
            ;;
        app|setup-app)
            local app_type="${1:-}"
            parse_common_args "${@:2}"
            check_requirements
            setup_app_example "$app_type"
            ;;
        status)
            parse_common_args "$@"
            show_status
            ;;            
        update|pull)            
            parse_update_args "$@"
            check_requirements
            show_status
            update_makefile_system
            ;;
        uninstall)
            parse_uninstall_args "$@"
            check_requirements
            uninstall
            ;;
        self-update)
            self_update
            ;;
        check)
            is_universal_makefile_installed
            ;;
        diff)
            show_diff
            ;;
        help|-h|--help|'')
            usage
            ;;
        *)
            log_error "Unknown command: $cmd"
            usage
            exit 1
            ;;
    esac
}


if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
