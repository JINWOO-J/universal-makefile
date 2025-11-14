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

set -e  # 에러 발생 시 즉시 종료

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 인자 받기
SOURCE_DIR="$1"
SOURCE_REPO="$2"
REF="$3"
SYNC_MODE="${4:-reset}"  # 기본값: reset (remote 우선)
FETCH_ALL="${5:-false}"  # 기본값: false

# 인자 검증
if [ -z "$SOURCE_DIR" ] || [ -z "$SOURCE_REPO" ] || [ -z "$REF" ]; then
    echo -e "${RED}❌ 에러: 필수 인자가 누락되었습니다${NC}"
    echo "사용법: $0 <SOURCE_DIR> <SOURCE_REPO> <REF> [SYNC_MODE] [FETCH_ALL]"
    exit 1
fi

# SYNC_MODE 검증
case "$SYNC_MODE" in
    clone|reset|pull|keep) ;;
    *)
        echo -e "${RED}❌ 에러: 잘못된 SYNC_MODE: $SYNC_MODE${NC}"
        echo "사용 가능한 값: clone, reset, pull, keep"
        exit 1
        ;;
esac

echo -e "${BLUE}[INFO]${NC} 소스 코드 가져오기 시작..."
echo "  SOURCE_DIR: $SOURCE_DIR"
echo "  SOURCE_REPO: $SOURCE_REPO"
echo "  REF: $REF"
echo "  SYNC_MODE: $SYNC_MODE"
echo "  FETCH_ALL: $FETCH_ALL"
echo ""

# 동기화 모드별 동작 판단
NEED_CLONE=false
FORCE_RESET=false
DO_PULL=false
FETCH_ONLY=false

if [ -d "$SOURCE_DIR" ]; then
    case "$SYNC_MODE" in
        clone)
            echo "🗑️  SYNC_MODE=clone: 기존 소스 디렉토리 삭제 후 새로 clone"
            rm -rf "$SOURCE_DIR"
            NEED_CLONE=true
            ;;
        reset)
            echo "🔄 SYNC_MODE=reset: remote 강제 적용 (로컬 무시)"
            if [ ! -d "$SOURCE_DIR/.git" ]; then
                echo -e "${RED}❌ 에러: $SOURCE_DIR는 git 저장소가 아닙니다${NC}"
                echo -e "${YELLOW}💡 SYNC_MODE=clone으로 다시 시도하세요${NC}"
                exit 1
            fi
            FORCE_RESET=true
            ;;
        pull)
            echo "⬇️  SYNC_MODE=pull: 로컬 변경사항 병합 시도"
            if [ ! -d "$SOURCE_DIR/.git" ]; then
                echo -e "${RED}❌ 에러: $SOURCE_DIR는 git 저장소가 아닙니다${NC}"
                echo -e "${YELLOW}💡 SYNC_MODE=clone으로 다시 시도하세요${NC}"
                exit 1
            fi
            DO_PULL=true
            ;;
        keep)
            echo "♻️  SYNC_MODE=keep: fetch만 실행 (로컬 유지)"
            if [ ! -d "$SOURCE_DIR/.git" ]; then
                echo -e "${RED}❌ 에러: $SOURCE_DIR는 git 저장소가 아닙니다${NC}"
                echo -e "${YELLOW}💡 SYNC_MODE=clone으로 다시 시도하세요${NC}"
                exit 1
            fi
            FETCH_ONLY=true
            ;;
    esac
else
    echo "📁 소스 디렉토리가 없습니다. clone 실행..."
    NEED_CLONE=true
fi

# Git URL 생성 함수
build_git_url() {
    local repo="$1"
    
    # 이미 완전한 URL인 경우 (https:// 또는 git@)
    if [[ "$repo" =~ ^https:// ]] || [[ "$repo" =~ ^git@ ]]; then
        echo "$repo"
        return
    fi
    
    # SSH 형식 감지 (git@github.com:owner/repo)
    if [[ "$repo" =~ ^git@ ]]; then
        echo "$repo"
        return
    fi
    
    # owner/repo 형식 → HTTPS URL 생성
    # GH_TOKEN이 있으면 포함
    if [ -n "$GH_TOKEN" ]; then
        echo "https://${GH_TOKEN}@github.com/${repo}.git"
    else
        echo "https://github.com/${repo}.git"
    fi
}

# Clone 또는 Fetch/Pull
if [ "$NEED_CLONE" = "true" ]; then
    mkdir -p "$SOURCE_DIR"
    echo ""
    
    # Git URL 생성
    GIT_URL=$(build_git_url "$SOURCE_REPO")
    
    # 토큰 마스킹된 URL (로그용)
    if [ -n "$GH_TOKEN" ]; then
        DISPLAY_URL=$(echo "$GIT_URL" | sed "s/${GH_TOKEN}/***TOKEN***/g")
        echo -e "${BLUE}[INFO]${NC} 저장소 클론: $DISPLAY_URL"
    else
        echo -e "${BLUE}[INFO]${NC} 저장소 클론: $GIT_URL"
    fi
    
    git clone "$GIT_URL" "$SOURCE_DIR" || {
        echo -e "${RED}❌ 저장소 클론 실패${NC}"
        exit 1
    }
else
    echo ""
    cd "$SOURCE_DIR"
    
    # Fetch 실행
    if [ "$FETCH_ALL" = "true" ]; then
        echo -e "${BLUE}[INFO]${NC} 모든 remote 가져오는 중..."
        git fetch --all --prune || {
            echo -e "${RED}❌ git fetch --all 실패${NC}"
            exit 1
        }
    else
        echo -e "${BLUE}[INFO]${NC} 기존 저장소 업데이트: $SOURCE_REPO"
        git fetch origin --prune || {
            echo -e "${RED}❌ git fetch 실패${NC}"
            exit 1
        }
    fi
    
    # SYNC_MODE별 후속 처리
    if [ "$FORCE_RESET" = "true" ]; then
        echo -e "${YELLOW}⚠️  로컬 변경사항 무시하고 remote로 강제 리셋${NC}"
        # 아직 체크아웃 전이므로, REF 체크아웃 후 reset 수행
    elif [ "$DO_PULL" = "true" ]; then
        echo -e "${BLUE}[INFO]${NC} 로컬 변경사항 병합 시도 (pull)"
        # 현재 브랜치에서 pull 수행
        git pull origin "$(git rev-parse --abbrev-ref HEAD)" || {
            echo -e "${YELLOW}⚠️  병합 충돌 발생. 수동으로 해결이 필요합니다.${NC}"
            exit 1
        }
    elif [ "$FETCH_ONLY" = "true" ]; then
        echo -e "${GREEN}✓ fetch 완료 (로컬 유지)${NC}"
    fi
fi

# REF 체크아웃
echo ""
echo -e "${BLUE}[INFO]${NC} 참조 체크아웃: $REF"
cd "$SOURCE_DIR"

if [[ "$REF" == refs/pull/* ]]; then
    echo -e "${BLUE}[INFO]${NC} PR 참조 감지, fetch 실행: $REF"
    
    # PR 번호 추출 (refs/pull/17/head -> pr-17)
    PR_NUMBER=$(echo "$REF" | sed -n 's|refs/pull/\([0-9]*\)/.*|\1|p')
    BRANCH_NAME="pr-${PR_NUMBER}"
    
    echo "  PR 번호: $PR_NUMBER"
    echo "  브랜치 이름: $BRANCH_NAME"
    
    # 해당 브랜치가 이미 체크아웃되어 있으면 임시로 detached HEAD로 이동
    CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")
    if [ "$CURRENT_BRANCH" = "$BRANCH_NAME" ]; then
        echo "  현재 $BRANCH_NAME에 있음, 임시로 HEAD로 이동..."
        git checkout --detach HEAD
    fi
    
    # 기존 브랜치 삭제 후 다시 생성 (강제 업데이트)
    git branch -D "$BRANCH_NAME" 2>/dev/null || true
    git fetch origin "$REF:$BRANCH_NAME" && git checkout "$BRANCH_NAME"
else
    git checkout "$REF"
fi || {
    echo -e "${RED}❌ 참조 체크아웃 실패${NC}"
    exit 1
}

# FORCE_RESET 처리 (체크아웃 후)
if [ "$FORCE_RESET" = "true" ]; then
    echo ""
    echo -e "${YELLOW}⚠️  remote로 강제 리셋 중...${NC}"
    git reset --hard "origin/$REF" 2>/dev/null || git reset --hard "$REF" || {
        echo -e "${YELLOW}⚠️  reset 실패 (브랜치가 remote에 없거나 detached 상태)${NC}"
    }
fi

# 완료 메시지
echo ""
BRANCH=$(git branch --show-current 2>/dev/null || echo 'detached')
COMMIT_HASH=$(git rev-parse --short HEAD)
echo -e "✓ ${GREEN}완료: (브랜치: $BRANCH, 커밋: $COMMIT_HASH)${NC}"
echo "--------------------------------------------------"
git --no-pager log -4 --pretty=format:"%C(yellow)%h%Creset %C(blue)%ad%Creset  %s" --date=short
echo ""
echo "--------------------------------------------------"
echo ""
echo -e "${GREEN}✅ 소스 코드 가져오기 완료${NC}"
