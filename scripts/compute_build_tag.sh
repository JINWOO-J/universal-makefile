#!/bin/bash
# compute_build_tag.sh
# 동적으로 Docker 이미지 태그를 계산하는 스크립트

set -e

# 인자 파싱
SOURCE_DIR="${1:-source}"
REF="${2:-}"
IMAGE_NAME="${3:-repo/app}"
SERVICE_KIND="${4:-be}"
VERSION="${5:-v1.0.0}"

# Git 정보가 없으면 기본값 사용
if [ ! -d "$SOURCE_DIR" ] || [ ! -d "$SOURCE_DIR/.git" ]; then
    echo "Warning: No git repository found in $SOURCE_DIR" >&2
    echo "$IMAGE_NAME:$SERVICE_KIND-$VERSION-unknown-$(date +%Y%m%d)-unknown"
    exit 0
fi

# Git 디렉토리로 이동
cd "$SOURCE_DIR"

# 커밋 해시 가져오기
COMMIT_SHA=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
SHA8="${COMMIT_SHA:0:8}"

# REF에서 브랜치명 추출
if [ -n "$REF" ]; then
    # refs/pull/15/head -> pr-15
    if echo "$REF" | grep -q "^refs/pull/"; then
        PR_NUM=$(echo "$REF" | sed 's|refs/pull/\([0-9]*\)/.*|\1|')
        if echo "$REF" | grep -q "/merge$"; then
            BRANCH_NAME="pr-$PR_NUM-merge"
        else
            BRANCH_NAME="pr-$PR_NUM"
        fi
    # refs/heads/develop -> develop
    else
        BRANCH_NAME=$(echo "$REF" | sed 's|.*/||')
    fi
else
    # REF가 없으면 현재 브랜치 사용
    BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    if [ "$BRANCH_NAME" = "HEAD" ]; then
        BRANCH_NAME="detached"
    fi
fi

# 날짜
CURRENT_DATE=$(date +%Y%m%d)

# 최종 이미지 태그 생성
IMAGE_TAG="$IMAGE_NAME:$SERVICE_KIND-$VERSION-$BRANCH_NAME-$CURRENT_DATE-$SHA8"

echo "$IMAGE_TAG"
