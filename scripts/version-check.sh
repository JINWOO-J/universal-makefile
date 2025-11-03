#!/bin/bash
# Version verification check

set -e

URL=$1
EXPECTED_VERSION=$2
STRICT=${3:-false}

if [ -z "$URL" ] || [ -z "$EXPECTED_VERSION" ]; then
    echo "Usage: $0 <URL> <expected_version> [strict]"
    exit 1
fi

echo "🔍 Version checking: $URL"
echo "  Expected version: $EXPECTED_VERSION"

actual_version=$(curl -s --max-time 5 "$URL/version.txt" 2>/dev/null | tr -d '\n\r' || echo "unknown")

echo "  Actual version: $actual_version"

if [ "$actual_version" = "$EXPECTED_VERSION" ]; then
    echo "✓ Version check passed: $actual_version"
    exit 0
elif [ "$STRICT" = "true" ]; then
    echo "✗ Version mismatch (strict mode): expected $EXPECTED_VERSION, got $actual_version"
    exit 1
else
    echo "⚠ Version mismatch (non-strict): expected $EXPECTED_VERSION, got $actual_version"
    exit 0
fi
