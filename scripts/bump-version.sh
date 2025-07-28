#!/bin/bash

# ================================================================
# Version Bump Script
# 복잡한 버전 관리 로직을 Makefile에서 분리
# ================================================================

set -euo pipefail

# 색상 정의
GREEN=$(tput setaf 2 2>/dev/null || echo "")
YELLOW=$(tput setaf 3 2>/dev/null || echo "")
BLUE=$(tput setaf 4 2>/dev/null || echo "")
RED=$(tput setaf 1 2>/dev/null || echo "")
RESET=$(tput sgr0 2>/dev/null || echo "")

log_info() {
    echo "${BLUE}ℹ️  $1${RESET}"
}

log_success() {
    echo "${GREEN}✅ $1${RESET}"
}

log_warn() {
    echo "${YELLOW}⚠️  $1${RESET}"
}

log_error() {
    echo "${RED}❌ $1${RESET}" >&2
}

# 사용법 표시
usage() {
    cat << EOF
Usage: $0 [OPTIONS] [VERSION_TYPE]

VERSION_TYPE:
    patch    Bump patch version (1.0.0 -> 1.0.1) [default]
    minor    Bump minor version (1.0.0 -> 1.1.0)
    major    Bump major version (1.0.0 -> 2.0.0)
    
OPTIONS:
    --dry-run    Show what would be done without making changes
    --help       Show this help message

EXAMPLES:
    $0                    # Bump patch version
    $0 minor              # Bump minor version
    $0 major --dry-run    # Show what major bump would do
EOF
}

# 기본값 설정
VERSION_TYPE="patch"
DRY_RUN=false

# 명령행 인수 처리
while [[ $# -gt 0 ]]; do
    case $1 in
        patch|minor|major)
            VERSION_TYPE="$1"
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Git 태그에서 현재 버전 가져오기
get_current_version() {
    git fetch --tags >/dev/null 2>&1 || true
    local latest_tag=$(git describe --tags `git rev-list --tags --max-count=1` 2>/dev/null || echo "v0.0.0")
    echo "$latest_tag"
}

# 버전 파싱
parse_version() {
    local version="$1"
    # v 접두사 제거
    version=${version#v}
    
    # 버전을 점으로 분리
    IFS='.' read -ra VERSION_PARTS <<< "$version"
    
    MAJOR=${VERSION_PARTS[0]:-0}
    MINOR=${VERSION_PARTS[1]:-0}
    PATCH=${VERSION_PARTS[2]:-0}
}

# 새 버전 계산
calculate_new_version() {
    local version_type="$1"
    
    case $version_type in
        patch)
            NEW_PATCH=$((PATCH + 1))
            NEW_VERSION="v${MAJOR}.${MINOR}.${NEW_PATCH}"
            ;;
        minor)
            NEW_MINOR=$((MINOR + 1))
            NEW_VERSION="v${MAJOR}.${NEW_MINOR}.0"
            ;;
        major)
            NEW_MAJOR=$((MAJOR + 1))
            NEW_VERSION="v${NEW_MAJOR}.0.0"
            ;;
        *)
            log_error "Invalid version type: $version_type"
            exit 1
            ;;
    esac
}

# 버전 파일 업데이트
update_version_files() {
    local new_version="$1"
    local version_no_v="${new_version#v}"
    
    log_info "Updating version files..."
    
    # package.json 업데이트
    if [[ -f "package.json" ]]; then
        if [[ "$DRY_RUN" == "false" ]]; then
            if command -v jq >/dev/null 2>&1; then
                jq ".version = \"$version_no_v\"" package.json > package.json.tmp && mv package.json.tmp package.json
            else
                sed -i.bak "s/\"version\": \"[^\"]*\"/\"version\": \"$version_no_v\"/" package.json && rm package.json.bak
            fi
        fi
        log_info "  📦 package.json: $version_no_v"
    fi
    
    # pyproject.toml 업데이트
    if [[ -f "pyproject.toml" ]]; then
        if [[ "$DRY_RUN" == "false" ]]; then
            sed -i.bak "s/version = \"[^\"]*\"/version = \"$version_no_v\"/" pyproject.toml && rm pyproject.toml.bak
        fi
        log_info "  🐍 pyproject.toml: $version_no_v"
    fi
    
    # Cargo.toml 업데이트
    if [[ -f "Cargo.toml" ]]; then
        if [[ "$DRY_RUN" == "false" ]]; then
            sed -i.bak "s/version = \"[^\"]*\"/version = \"$version_no_v\"/" Cargo.toml && rm Cargo.toml.bak
        fi
        log_info "  🦀 Cargo.toml: $version_no_v"
    fi
    
    # VERSION 파일 업데이트
    if [[ -f "VERSION" ]]; then
        if [[ "$DRY_RUN" == "false" ]]; then
            echo "$new_version" > VERSION
        fi
        log_info "  📄 VERSION: $new_version"
    fi
}

# 메인 실행
main() {
    log_info "🏷️  Version Bump Script"
    
    # 현재 버전 가져오기
    CURRENT_VERSION=$(get_current_version)
    log_info "Current version: $CURRENT_VERSION"
    
    # 버전 파싱
    parse_version "$CURRENT_VERSION"
    
    # 새 버전 계산
    calculate_new_version "$VERSION_TYPE"
    
    log_info "New version: $NEW_VERSION (${VERSION_TYPE} bump)"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "DRY RUN - No changes will be made"
        update_version_files "$NEW_VERSION"
        log_info "Would create git tag: $NEW_VERSION"
    else
        # 버전 파일 업데이트
        update_version_files "$NEW_VERSION"
        
        # 임시 파일에 새 버전 저장 (Makefile에서 사용)
        echo "$NEW_VERSION" > .NEW_VERSION.tmp
        
        log_success "Version bumped from $CURRENT_VERSION to $NEW_VERSION"
        log_info "Run 'make version-tag' to create git tag"
    fi
}

# 스크립트 실행
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi