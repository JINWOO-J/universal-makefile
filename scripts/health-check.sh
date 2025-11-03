#!/bin/bash
# Basic HTTP health check

set -e

URL=$1
TIMEOUT=${2:-30}
RETRIES=${3:-5}

if [ -z "$URL" ]; then
    echo "Usage: $0 <URL> [timeout] [retries]"
    echo "Example: $0 http://localhost:8080/health 30 5"
    exit 1
fi

echo "🔍 Health checking: $URL"
echo "  Timeout: ${TIMEOUT}s"
echo "  Retries: $RETRIES"

for i in $(seq 1 $RETRIES); do
    echo "  Attempt $i/$RETRIES..."
    
    response=$(curl -s -o /dev/null -w "%{http_code}" --max-time $TIMEOUT $URL 2>/dev/null || echo "000")
    
    if [ "$response" = "200" ]; then
        echo "✓ Health check passed: $URL (HTTP $response)"
        exit 0
    fi
    
    if [ $i -lt $RETRIES ]; then
        echo "  Failed (HTTP $response), retrying in 2 seconds..."
        sleep 2
    fi
done

echo "✗ Health check failed: $URL (HTTP $response)"
exit 1
