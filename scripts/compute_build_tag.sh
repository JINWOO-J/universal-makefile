#!/bin/bash
# compute_build_tag.sh
# 동적으로 Docker 이미지 태그를 계산하는 스크립트
#
# make(core.mk)가 계산한 정식 값을 환경변수로 받으면 그대로 사용한다 (공통화):
#   UMF_BRANCH : core.mk SAFE_BRANCH (이미 정규화된 브랜치명)
#   UMF_DATE   : core.mk DATE (make 파싱 시점 타임스탬프)
#   UMF_SHA    : core.mk CURRENT_COMMIT_SHORT
# 미지정 시 스스로 계산한다 (단독 호출 호환).

set -e

# 인자 파싱
SOURCE_DIR="${1:-source}"
REF="${2:-}"
IMAGE_NAME="${3:-repo/app}"
SERVICE_KIND="${4:-be}"
VERSION="${5:-v1.0.0}"
TAG_SUFFIX_RAW="${6:-${TAG_SUFFIX:-}}"  # CHANGED: optional suffix (env or 6th arg)

UMF_BRANCH="${UMF_BRANCH:-}"
UMF_DATE="${UMF_DATE:-}"
UMF_SHA="${UMF_SHA:-}"

# suffix 정규화 (CHANGED)
TAG_SUFFIX="$(echo "${TAG_SUFFIX_RAW}" | tr -d '[:space:]' | sed 's/[^a-zA-Z0-9_.-]/-/g; s/-\\+/-/g')"
if [ -n "$TAG_SUFFIX" ] && [[ "$TAG_SUFFIX" != -* ]]; then
  TAG_SUFFIX="-$TAG_SUFFIX"
fi

# Git 정보가 없으면 기본값 사용 (make가 넘긴 정식 값이 있으면 우선)
if [ ! -d "$SOURCE_DIR" ] || [ ! -d "$SOURCE_DIR/.git" ]; then
    echo "Warning: No git repository found in $SOURCE_DIR" >&2
    echo "$IMAGE_NAME:$SERVICE_KIND-$VERSION-${UMF_BRANCH:-unknown}-${UMF_DATE:-$(date +%Y%m%d_%H%M%S)}-${UMF_SHA:-unknown}${TAG_SUFFIX}"
    exit 0
fi

# Git 디렉토리로 이동
cd "$SOURCE_DIR"

# 커밋 해시: make가 넘긴 값(core.mk CURRENT_COMMIT_SHORT) 우선, 없으면 직접 계산
if [ -n "$UMF_SHA" ]; then
    SHA8="$UMF_SHA"
else
    COMMIT_SHA=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
    SHA8="${COMMIT_SHA:0:8}"
fi

# 브랜치명: make가 넘긴 값(core.mk SAFE_BRANCH) 우선, 없으면 REF/git에서 추출
if [ -n "$UMF_BRANCH" ]; then
    BRANCH_NAME="$UMF_BRANCH"
else
    if [ -n "$REF" ]; then
        # refs/pull/15/head, refs/pull/15/merge -> pr-15 (core.mk와 동일)
        if printf '%s\n' "$REF" | grep -q "^refs/pull/"; then
            PR_NUM=$(printf '%s\n' "$REF" | sed 's|refs/pull/\([0-9]*\)/.*|\1|')
            BRANCH_NAME="pr-$PR_NUM"
        # refs/heads/feature/X -> feature/X (prefix만 제거, 네임스페이스 보존)
        else
            BRANCH_NAME=$(printf '%s\n' "$REF" | sed -E 's,^refs/(heads|tags)/,,')
        fi
    else
        # REF가 없으면 현재 브랜치 사용
        BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
        if [ "$BRANCH_NAME" = "HEAD" ]; then
            BRANCH_NAME="detached"
        fi
    fi
    # core.mk SAFE_BRANCH와 동일 규칙으로 정규화 (슬래시 등 → '-', 연속 '-' 축약)
    BRANCH_NAME=$(printf '%s\n' "$BRANCH_NAME" | sed -E 's/[^a-zA-Z0-9._-]/-/g; s/-+/-/g')
fi

# 날짜: make가 넘긴 값(core.mk DATE) 우선
CURRENT_DATE="${UMF_DATE:-$(date +%Y%m%d_%H%M%S)}"

# 최종 이미지 태그 생성
IMAGE_TAG="$IMAGE_NAME:$SERVICE_KIND-$VERSION-$BRANCH_NAME-$CURRENT_DATE-$SHA8${TAG_SUFFIX}"

echo "$IMAGE_TAG"
