#!/bin/bash
# 소스 코드 fetch 스크립트
# 사용법: ./scripts/fetch_source.sh <SOURCE_DIR> <SOURCE_REPO> <REF> [CLEAN]
#
# 환경 변수:
#   GH_TOKEN - GitHub Personal Access Token (private repo 접근용)
#
# SOURCE_REPO 형식:
#   - owner/repo                    → https://github.com/owner/repo.git
#   - https://github.com/owner/repo → 그대로 사용
#   - git@github.com:owner/repo     → SSH 사용

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
CLEAN="${4:-true}"  # 기본값 true

# 인자 검증
if [ -z "$SOURCE_DIR" ] || [ -z "$SOURCE_REPO" ] || [ -z "$REF" ]; then
    echo -e "${RED}❌ 에러: 필수 인자가 누락되었습니다${NC}"
    echo "사용법: $0 <SOURCE_DIR> <SOURCE_REPO> <REF> [CLEAN]"
    exit 1
fi

echo -e "${BLUE}[INFO]${NC} 소스 코드 가져오기 시작..."
echo "  SOURCE_DIR: $SOURCE_DIR"
echo "  SOURCE_REPO: $SOURCE_REPO"
echo "  REF: $REF"
echo "  CLEAN: $CLEAN"
echo ""

# clone 필요 여부 판단
NEED_CLONE=false

if [ -d "$SOURCE_DIR" ]; then
    if [ "$CLEAN" = "true" ]; then
        echo "🗑️  CLEAN=true: 기존 소스 디렉토리 삭제 중..."
        rm -rf "$SOURCE_DIR"
        NEED_CLONE=true
    else
        echo "♻️  CLEAN=false: 기존 소스 디렉토리 유지"
        if [ ! -d "$SOURCE_DIR/.git" ]; then
            echo -e "${RED}❌ 에러: $SOURCE_DIR는 git 저장소가 아닙니다${NC}"
            echo -e "${YELLOW}💡 CLEAN=true로 다시 시도하세요${NC}"
            exit 1
        fi
    fi
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

# Clone 또는 Fetch
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
    echo -e "${BLUE}[INFO]${NC} 기존 저장소 업데이트: $SOURCE_REPO"
    cd "$SOURCE_DIR" && git fetch origin || {
        echo -e "${RED}❌ git fetch 실패${NC}"
        exit 1
    }
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

# 완료 메시지
echo ""
BRANCH=$(git branch --show-current 2>/dev/null || echo 'detached')
echo -e "✓ ${GREEN}완료: (브랜치: $BRANCH)${NC}"
echo "--------------------------------------------------"
git --no-pager log -4 --oneline --no-decorate
echo "--------------------------------------------------"
echo ""
echo -e "${GREEN}✅ 소스 코드 가져오기 완료${NC}"
