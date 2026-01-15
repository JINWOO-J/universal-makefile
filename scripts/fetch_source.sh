#!/bin/bash
# 소스 코드 fetch 스크립트
# 사용법: ./scripts/fetch_source.sh <SOURCE_DIR> <SOURCE_REPO> <REF> [SYNC_MODE] [FETCH_ALL]
#
# 환경 변수:
#   GH_TOKEN - GitHub Personal Access Token (private repo 접근용)
#
# SOURCE_REPO 형식:
#   - owner/repo                    → https://github.com/owner/repo.git
#   - https://github.com/owner/repo → 그대로 사용
#   - git@github.com:owner/repo     → SSH 사용
#
# SYNC_MODE:
#   - clone : 기존 삭제 후 새로 clone (가장 강력)
#   - reset : git fetch + reset --hard (로컬 무시, remote 우선) [기본값]
#   - pull  : git pull (로컬 변경사항 병합 시도)
#   - keep  : fetch만 실행 (로컬 유지)

set -euo pipefail

#=============================================================================
# 색상 및 로깅
#=============================================================================
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $*"; }

die() {
    log_error "$1"
    exit "${2:-1}"
}

# Git URL 생성 함수
build_git_url() {
    local repo="$1"

    # 이미 완전한 URL인 경우 (https:// 또는 git@)
    if [[ "$repo" =~ ^(https://|git@) ]]; then
        echo "$repo"
        return
    fi

    # owner/repo 형식 → HTTPS URL 생성
    if [[ -n "${GH_TOKEN:-}" ]]; then
        echo "https://${GH_TOKEN}@github.com/${repo}.git"
    else
        echo "https://github.com/${repo}.git"
    fi
}

# 토큰이 마스킹된 URL 반환 (로그용)
mask_token_url() {
    local url="$1"
    if [[ -n "${GH_TOKEN:-}" ]]; then
        echo "${url//${GH_TOKEN}/***TOKEN***}"
    else
        echo "$url"
    fi
}

# git 저장소 검증
validate_git_repo() {
    local dir="$1"
    if [[ ! -d "$dir/.git" ]]; then
        log_error "$dir 는 git 저장소가 아닙니다"
        log_warn "SYNC_MODE=clone으로 다시 시도하세요"
        exit 1
    fi
}

# Clone 수행
do_clone() {
    local git_url="$1"
    local target_dir="$2"

    mkdir -p "$target_dir"
    log_info "저장소 클론: $(mask_token_url "$git_url")"

    if ! git clone "$git_url" "$target_dir"; then
        die "저장소 클론 실패"
    fi
}

# Fetch 수행
do_fetch() {
    local fetch_all="$1"

    if [[ "$fetch_all" == "true" ]]; then
        log_info "모든 remote 가져오는 중..."
        git fetch --all --prune || die "git fetch --all 실패"
    else
        log_info "기존 저장소 업데이트 중..."
        git fetch origin --prune || die "git fetch 실패"
    fi
}

# REF 체크아웃 (PR 또는 일반 브랜치)
checkout_ref() {
    local ref="$1"
    local force_reset="$2"

    if [[ "$ref" == refs/pull/* ]]; then
        checkout_pr_ref "$ref" "$force_reset"
    else
        checkout_branch_ref "$ref" "$force_reset"
    fi
}

# PR 참조 체크아웃
checkout_pr_ref() {
    local ref="$1"
    local force_reset="$2"

    # PR 번호 추출 (refs/pull/17/head -> pr-17)
    local pr_number
    pr_number=$(echo "$ref" | sed -n 's|refs/pull/\([0-9]*\)/.*|\1|p')
    local branch_name="pr-${pr_number}"

    log_info "PR 참조 감지: #$pr_number → $branch_name"

    # 해당 브랜치에 있으면 임시로 detached HEAD로 이동
    local current_branch
    current_branch=$(git branch --show-current 2>/dev/null || echo "")
    if [[ "$current_branch" == "$branch_name" ]]; then
        git checkout --detach HEAD 2>/dev/null
    fi

    # 기존 브랜치 삭제 후 다시 생성
    git branch -D "$branch_name" 2>/dev/null || true
    git fetch origin "$ref:$branch_name" || die "PR fetch 실패: $ref"

    if [[ "$force_reset" == "true" ]]; then
        git checkout -f "$branch_name" || die "PR 체크아웃 실패: $branch_name"
    else
        git checkout "$branch_name" || die "PR 체크아웃 실패: $branch_name"
    fi
}

# 일반 브랜치 체크아웃
checkout_branch_ref() {
    local ref="$1"
    local force_reset="$2"

    if [[ "$force_reset" == "true" ]]; then
        # 로컬 변경사항 무시하고 강제 체크아웃
        git checkout -f -B "$ref" "origin/$ref" 2>/dev/null || git checkout -f "$ref"
    else
        git checkout "$ref"
    fi || die "참조 체크아웃 실패: $ref"
}

# Reset 수행 (체크아웃 후)
do_reset() {
    local ref="$1"

    log_warn "remote로 강제 리셋 중..."

    local reset_target
    if [[ "$ref" == refs/pull/* ]]; then
        # PR의 경우 현재 브랜치 (pr-XX)를 대상으로
        reset_target="HEAD"
    else
        reset_target="origin/$ref"
    fi

    if ! git reset --hard "$reset_target" 2>/dev/null; then
        log_warn "reset 실패 (브랜치가 remote에 없거나 detached 상태)"
    fi
}

# Pull 수행
do_pull() {
    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD)

    log_info "로컬 변경사항 병합 시도 (pull)"
    if ! git pull origin "$current_branch"; then
        die "병합 충돌 발생. 수동으로 해결이 필요합니다."
    fi
}

# 완료 메시지 출력
print_summary() {
    local branch commit_hash
    branch=$(git branch --show-current 2>/dev/null || echo 'detached')
    commit_hash=$(git rev-parse --short HEAD)

    echo ""
    log_ok "완료: (브랜치: $branch, 커밋: $commit_hash)"
    echo "--------------------------------------------------"
    git --no-pager log -4 --pretty=format:"%C(yellow)%h%Creset %C(blue)%ad%Creset  %s" --date=short
    echo ""
    echo "--------------------------------------------------"
    echo ""
    echo -e "${GREEN}✅ 소스 코드 가져오기 완료${NC}"
}


main() {
    local source_dir="${1:-}"
    local source_repo="${2:-}"
    local ref="${3:-}"
    local sync_mode="${4:-reset}"
    local fetch_all="${5:-false}"
    if [[ -z "$source_dir" ]] || [[ -z "$source_repo" ]] || [[ -z "$ref" ]]; then
        die "필수 인자가 누락되었습니다
사용법: $0 <SOURCE_DIR> <SOURCE_REPO> <REF> [SYNC_MODE] [FETCH_ALL]"
    fi

    case "$sync_mode" in
        clone|reset|pull|keep) ;;
        *) die "잘못된 SYNC_MODE: $sync_mode (사용 가능: clone, reset, pull, keep)" ;;
    esac

    log_info "소스 코드 가져오기 시작..."
    echo "  SOURCE_DIR:  $source_dir"
    echo "  SOURCE_REPO: $source_repo"
    echo "  REF:         $ref"
    echo "  SYNC_MODE:   $sync_mode"
    echo "  FETCH_ALL:   $fetch_all"
    echo ""

    local need_clone=false
    local force_reset=false
    local do_pull_flag=false

    if [[ -d "$source_dir" ]]; then
        case "$sync_mode" in
            clone)
                log_info "SYNC_MODE=clone: 기존 소스 디렉토리 삭제 후 새로 clone"
                rm -rf "$source_dir"
                need_clone=true
                ;;
            reset)
                log_info "SYNC_MODE=reset: remote 강제 적용 (로컬 무시)"
                validate_git_repo "$source_dir"
                force_reset=true
                ;;
            pull)
                log_info "SYNC_MODE=pull: 로컬 변경사항 병합 시도"
                validate_git_repo "$source_dir"
                do_pull_flag=true
                ;;
            keep)
                log_info "SYNC_MODE=keep: fetch만 실행 (로컬 유지)"
                validate_git_repo "$source_dir"
                ;;
        esac
    else
        log_info "소스 디렉토리가 없습니다. clone 실행..."
        need_clone=true
    fi

    if [[ "$need_clone" == "true" ]]; then
        local git_url
        git_url=$(build_git_url "$source_repo")
        do_clone "$git_url" "$source_dir"
    else
        cd "$source_dir"
        do_fetch "$fetch_all"

        if [[ "$do_pull_flag" == "true" ]]; then
            do_pull
        fi
    fi

    echo ""
    log_info "참조 체크아웃: $ref"
    cd "$source_dir"
    checkout_ref "$ref" "$force_reset"

    if [[ "$force_reset" == "true" ]]; then
        do_reset "$ref"
    fi

    print_summary
}

main "$@"
