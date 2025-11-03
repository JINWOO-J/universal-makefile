#!/bin/bash
# Custom health check script
# Extend this script with your own health check logic

set -e

URL=$1

if [ -z "$URL" ]; then
    echo "Usage: $0 <URL>"
    exit 1
fi

echo "🔍 Custom health checking: $URL"

# Example: Check if response contains specific content
response=$(curl -s --max-time 5 "$URL" 2>/dev/null || echo "")

if [ -z "$response" ]; then
    echo "✗ Custom health check failed: empty response"
    exit 1
fi

# Example: Check for specific keywords
if echo "$response" | grep -q "Version"; then
    echo "✓ Custom health check passed: found 'Version' in response"
    exit 0
fi

# Add your custom checks here
# Examples:
# - Check API endpoints
# - Verify database connectivity
# - Test specific functionality
# - Validate response format

echo "✓ Custom health check passed"
exit 0
