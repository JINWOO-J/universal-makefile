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
        # TypeScript/JavaScript
        # 1. current: /* comment */ "version"
        VERSION=$(sed -n 's/.*current:.*"\([^"]*\)".*/\1/p' "$FILE" | head -1)
        if [ -z "$VERSION" ]; then
            # 2. version: "version"
            VERSION=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$FILE" | head -1)
        fi
        if [ -z "$VERSION" ]; then
            # 3. export const VERSION = "version"
            VERSION=$(sed -n 's/.*VERSION[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$FILE" | head -1)
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
        # 알 수 없는 형식
        echo "Unknown file type: $EXT" >&2
        exit 1
        ;;
esac
