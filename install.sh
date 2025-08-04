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

REPO_URL="https://github.com/jinwoo-j/universal-makefile"
MAKEFILE_DIR=".makefile-system"
MAIN_BRANCH="master"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
INSTALLATION_TYPE="submodule"
INSTALLER_SCRIPT_URL="$REPO_URL/raw/$MAIN_BRANCH/install.sh"

FORCE_INSTALL=false
DRY_RUN=false
BACKUP=false
EXISTING_PROJECT=false

usage() {
    cat <<EOF
Universal Makefile System Installer

Usage: $0 <command> [options]

Commands:
    install             Install the Universal Makefile System (default)
    update              Update the Universal Makefile System to the latest version
    uninstall           Remove all files created by this installer
    self-update         Update this installer script itself
    help                Show this help message

Common options:
    --force             Force installation/uninstall/update actions
    --dry-run           Show actions without performing them
    --backup            Backup files before removing (uninstall only)

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


parse_common_args() {
    FORCE_INSTALL=false
    DRY_RUN=false
    BACKUP=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force) FORCE_INSTALL=true; shift ;;
            --dry-run) DRY_RUN=true; shift ;;
            --backup) BACKUP=true; shift ;;
            *)
                log_error "Unknown option: $1"
                usage; exit 1 ;;
        esac
    done
}

parse_install_args() {
    INSTALLATION_TYPE="submodule"
    EXISTING_PROJECT=false

    local POSITIONAL_ARGS=()
    while [[ $# -gt 0 ]]; do
        case $1 in
            --copy)             
                INSTALLATION_TYPE="copy"; shift ;;
            --existing-project) 
                EXISTING_PROJECT=true; shift ;;
            --help|-h)          
                usage; exit 0 ;;
            --*) # 다른 옵션은 공통 옵션 파서로 넘김
                POSITIONAL_ARGS+=("$1"); shift ;;
            *)
                log_error "Unknown option for install: $1"; 
                usage; exit 1 ;;
        esac
    done

    parse_common_args "${POSITIONAL_ARGS[@]+"${POSITIONAL_ARGS[@]}"}"

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


# check_existing_installation() {
#     local has_existing=false

#     if [[ -d "$MAKEFILE_DIR" && ! -f Makefile && ! -f project.mk && ! -d makefiles ]]; then
#         log_info "Only submodule detected; proceeding as new installation."
#         return 0
#     fi

#     [[ -d "makefiles" ]] && log_warn "Makefiles directory exists" && has_existing=true

#     if [[ -f "Makefile" && "$EXISTING_PROJECT" != true ]]; then
#         if ! has_universal_id "Makefile"; then
#             log_warn "Existing Makefile found (not created by universal-makefile)"
#             has_existing=true
#         fi
#     fi

#     log_info "has_existing: $has_existing, FORCE_INSTALL: $FORCE_INSTALL, EXISTING_PROJECT: $EXISTING_PROJECT"
#     if [[ "$has_existing" == true && "$FORCE_INSTALL" == false && "$EXISTING_PROJECT" != true ]]; then
#         echo ""
#         log_warn "Existing installation detected. Options:"
#         echo "  1. Use --force to overwrite"
#         echo "  2. Use --existing-project to preserve existing files"
#         echo "  3. Manually remove existing files"
#         exit 1
#     fi
# }

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

    # # 설치 안내 메시지 추가
    # if [[ "$created_universal" == true ]]; then
    #     echo ""
    #     echo -e "${BLUE}To use Universal Makefile System commands, add the following line to your existing Makefile:${RESET}"
    #     echo -e "${YELLOW}include Makefile.universal${RESET}"
    #     echo ""
    # fi

    if [[ ! -f Makefile ]]; then
        echo -e "# Project Makefile\ninclude Makefile.universal\n" > Makefile
        log_success "Created Makefile with 'include Makefile.universal'"
    else
        # log_warn "Existing Makefile detected. To use Universal Makefile System, add:"
        # echo -e "${YELLOW}include Makefile.universal${RESET}"
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
    [[ -f "docker-compose.yml" && "$FORCE_INSTALL" == false ]] && return
    log_info "Creating docker-compose.yml..."
    cat > docker-compose.yml << 'EOF'
# === Created by Universal Makefile System Installer ===
version: '3.8'
services:
  app:
    build: .
    ports:
      - "3000:3000"
    environment:
      - NODE_ENV=production
    restart: unless-stopped
EOF
    log_success "Sample docker-compose.yml created"
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


self_update() {
    log_info "Updating installer script itself..."
    local tmp_script
    tmp_script=$(mktemp)
    
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$INSTALLER_SCRIPT_URL" -o "$tmp_script"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp_script" "$INSTALLER_SCRIPT_URL"
    else
        log_error "curl or wget required for self-update."
        exit 1
    fi

    if [[ -s "$tmp_script" ]]; then
        chmod +x "$tmp_script"
        mv "$tmp_script" "$0"
        log_success "Installer script updated successfully!"
    else
        rm -f "$tmp_script"
        log_error "Failed to download installer script."
        exit 1
    fi
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
    cp "$MAKEFILE_DIR/github-workflow" .github/workflows
    log_success "GitHub Actions workflow installed"
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
        update)
            parse_update_args "$@"
            update_makefile_system
            ;;
        uninstall)
            parse_uninstall_args "$@"
            uninstall
            ;;
        self-update)
            self_update
            ;;            
        check)
            is_universal_makefile_installed
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
