#!/bin/bash
# Custom health check script
# Extend this script with your own health check logic

set -e

CONTAINER_IP=$1
CONTAINER_PORT=$2
HEALTH_ENDPOINT=$3
TIMEOUT=${4:-30}
RETRIES=${5:-5}

if [ -z "$CONTAINER_IP" ] || [ -z "$CONTAINER_PORT" ] || [ -z "$HEALTH_ENDPOINT" ]; then
    echo "Usage: $0 <container_ip> <container_port> <health_endpoint> [timeout] [retries]"
    echo "Example: $0 172.17.0.2 8080 /health 30 5"
    exit 1
fi

URL="http://${CONTAINER_IP}:${CONTAINER_PORT}${HEALTH_ENDPOINT}"

echo "🔍 Custom health checking: $URL"
echo "  Container IP: $CONTAINER_IP"
echo "  Container Port: $CONTAINER_PORT"
echo "  Health Endpoint: $HEALTH_ENDPOINT"
echo "  Timeout: ${TIMEOUT}s"
echo "  Retries: $RETRIES"

for i in $(seq 1 $RETRIES); do
    echo "  Attempt $i/$RETRIES..."
    
    # Example: Check if response contains specific content
    response=$(curl -s --max-time "$TIMEOUT" "$URL" 2>/dev/null || echo "")
    
    if [ -z "$response" ]; then
        echo "  Failed: empty response"
        if [ $i -lt $RETRIES ]; then
            echo "  Retrying in 2 seconds..."
            sleep 2
        fi
        continue
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
    # - Check response status codes
    # - Validate JSON structure
    
    # Example: Check HTTP status code
    status_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time "$TIMEOUT" "$URL" 2>/dev/null || echo "000")
    if [ "$status_code" = "200" ]; then
        echo "✓ Custom health check passed: HTTP $status_code"
        exit 0
    fi
    
    echo "  Failed: HTTP $status_code"
    if [ $i -lt $RETRIES ]; then
        echo "  Retrying in 2 seconds..."
        sleep 2
    fi
done

echo "✗ Custom health check failed after $RETRIES attempts"
exit 1
