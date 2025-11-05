#!/bin/bash
# 버전 파일 파싱 스크립트
# 사용법: ./parse_version.sh <file_path> [pattern]

set -e

FILE="$1"
PATTERN="${2:-}"

if [ ! -f "$FILE" ]; then
  echo "File not found: $FILE" >&2
  exit 1
fi

# 파일 확장자로 자동 감지
EXT="${FILE##*.}"

case "$EXT" in
  ts|js|tsx|jsx)
    # 0) 주석 제거: /* ... */ 와 // ... (라인 끝까지)
    CLEAN=$(sed -E 's%/\*([^*]|\*+[^/])*\*/% %g; s%//.*$%%' "$FILE")

    # 1) current: "..."
    VERSION=$(printf '%s\n' "$CLEAN" \
      | sed -n -E 's/^[[:space:]]*current[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' \
      | head -1)

    # 2) "version": "..." (JSON 스타일)
    if [ -z "$VERSION" ]; then
      VERSION=$(printf '%s\n' "$CLEAN" \
        | sed -n -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' \
        | head -1)
    fi

    # 3) export const VERSION = "..." | '...'
    if [ -z "$VERSION" ]; then
      VERSION=$(printf '%s\n' "$CLEAN" \
        | sed -n -E "s/.*VERSION[[:space:]]*=[[:space:]]*['\"]([^'\"]*)['\"].*/\1/p" \
        | head -1)
    fi

    # 4) version: '...' | "..."  ← 새로 추가 (BSD sed 호환, 라인 시작 anchor)
    if [ -z "$VERSION" ]; then
      VERSION=$(printf '%s\n' "$CLEAN" \
        | sed -n -E "s/^[[:space:]]*version[[:space:]]*:[[:space:]]*['\"]([^'\"]*)['\"].*/\1/p" \
        | head -1)
    fi

    echo "$VERSION"
    ;;


  json)
    # JSON (package.json)
    if command -v jq >/dev/null 2>&1; then
      jq -r '.version // empty' "$FILE" 2>/dev/null
    else
      sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$FILE" | head -1
    fi
    ;;

  toml)
    # TOML (pyproject.toml, Cargo.toml)
    sed -n 's/^version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$FILE" | head -1
    ;;

  txt|version)
    # Plain text VERSION file
    head -n1 "$FILE" | tr -d '[:space:]'
    ;;

  *)
    echo "Unknown file type: $EXT" >&2
    exit 1
    ;;
esac
