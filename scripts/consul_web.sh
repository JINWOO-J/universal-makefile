#!/bin/bash
#
# Consul API Client - FastAPI 서버를 통한 Configuration 관리
# API 키를 사용하여 암호화된 값을 자동으로 복호화합니다.
#

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 기본 설정
CONSUL_API_URL="${CONSUL_API_URL:-http://localhost:8000}"
CONSUL_API_KEY="${CONSUL_API_KEY:-}"
CONSUL_APP="${CONSUL_APP:-}"
CONSUL_ENV="${CONSUL_ENV:-}"
ALL_ENV=false
QUIET=false

# 도움말
show_help() {
    cat << EOF
Usage: $0 [command] [options]

Consul Configuration API Client (with decryption support)

기본 명령어: export (명령어를 지정하지 않으면 export가 실행됩니다)

COMMANDS:
    export [prefix]     Configuration을 .env 형식으로 출력 (기본 명령어)
    get <key>           특정 key 조회 (자동 복호화)
    list [prefix]       Configuration 목록 조회
    set <key> <value>   Configuration 설정
    delete <key>        Configuration 삭제

OPTIONS:
    --prefix <prefix>   Key prefix (기본값: "")
    --app <app>         Application name (env: CONSUL_APP)
    --env <env>         Environment name (env: CONSUL_ENV)
    --all-env           Include all environments (use with --app, dangerous!)
    --output <file>     Output file (default: stdout, use "-" for explicit stdout)
    --overwrite         Overwrite existing output file
    --quiet             Minimize stderr output (warnings still shown)
    --no-decrypt        복호화하지 않음 (암호화된 값 그대로)
    --api-key <key>     API 키 (환경 변수 CONSUL_API_KEY 사용 가능)

ENVIRONMENT VARIABLES:
    CONSUL_API_URL      FastAPI 서버 URL (기본값: http://localhost:8000)
    CONSUL_API_KEY      API 키

EXAMPLES:
    # API 키 설정
    export CONSUL_API_KEY="cck_your_api_key"

    # 기본 명령어 (export) 사용 - 안전한 방식
    $0 --app web_service --env prod
    $0 --prefix dev  # prefix 직접 지정

    # 파일로 안전하게 저장
    $0 --app web_service --env prod --output .env
    $0 --app web_service --env prod --output .env --overwrite

    # 조용한 모드 (CI/CD용)
    $0 --app web_service --env prod --output .env --quiet

    # 위험한 방식 - 모든 환경 포함 (명시적 옵션 필요)
    $0 --app web_service --all-env export

    # 복호화된 비밀번호 조회
    $0 get dev/password

    # 암호화된 값 그대로 조회
    $0 get dev/password --no-decrypt

    # 목록 조회
    $0 list dev

    # 값 설정
    $0 set dev/new_key "new_value"

EOF
}

# API 키 확인
check_api_key() {
    if [ -z "$CONSUL_API_KEY" ]; then
        echo -e "${RED}Error: API key not provided${NC}" >&2
        echo "Set CONSUL_API_KEY environment variable or use --api-key option" >&2
        exit 1
    fi
}

# 로깅 함수 (stderr로 출력)
log_info() {
    if [ "$QUIET" != "true" ]; then
        echo -e "${GREEN}INFO: $1${NC}" >&2
    fi
}

log_warn() {
    echo -e "${YELLOW}WARNING: $1${NC}" >&2
}

log_error() {
    echo -e "${RED}Error: $1${NC}" >&2
}

# 출력 유틸리티
write_output() {
    local content="$1"
    local output_file="$2"
    local overwrite="${3:-true}"
    
    if [ -z "$output_file" ] || [ "$output_file" = "-" ]; then
        # stdout으로 출력 (순수 데이터만)
        echo "$content"
        return 0
    fi
    
    # 파일 존재 여부 확인
    if [ -f "$output_file" ] && [ "$overwrite" != "true" ]; then
        log_error "File already exists: $output_file (use --overwrite to replace)"
        exit 1
    fi
    
    # 원자적 파일 쓰기
    local temp_file="${output_file}.tmp.$$"
    
    # 임시 파일에 쓰기
    if echo "$content" > "$temp_file"; then
        # 파일 권한 설정 (0600 - 소유자만 읽기/쓰기)
        chmod 600 "$temp_file"
        
        # 원자적 교체
        if mv "$temp_file" "$output_file"; then
            log_info "✓ Wrote $output_file"
        else
            log_error "Failed to write $output_file"
            rm -f "$temp_file" 2>/dev/null
            exit 1
        fi
    else
        log_error "Failed to create temporary file"
        rm -f "$temp_file" 2>/dev/null
        exit 1
    fi
}

# GET 요청
api_get() {
    local key="$1"
    local prefix="$2"
    local decrypt="$3"
    
    check_api_key
    
    # URL 인코딩
    local encoded_key=$(url_encode "$key")
    local url="${CONSUL_API_URL}/api/v1/config/${encoded_key}"
    local params="decrypt=${decrypt}"
    
    if [ -n "$prefix" ]; then
        params="${params}&prefix=${prefix}"
    fi
    
    curl -s -f -H "X-API-Key: ${CONSUL_API_KEY}" \
        "${url}?${params}" 2>/dev/null || echo '{"success": false, "detail": "Request failed"}'
}

# LIST 요청
api_list() {
    local prefix="$1"
    
    check_api_key
    
    local url="${CONSUL_API_URL}/api/v1/config"
    local params=""
    
    if [ -n "$prefix" ]; then
        params="prefix=${prefix}"
    fi
    
    curl -s -f -H "X-API-Key: ${CONSUL_API_KEY}" \
        "${url}${params:+?$params}" 2>/dev/null || echo '{"success": false, "detail": "Request failed"}'
}

# POST 요청
api_set() {
    local key="$1"
    local value="$2"
    local prefix="$3"
    
    check_api_key
    
    local url="${CONSUL_API_URL}/api/v1/config"
    local params=""
    
    if [ -n "$prefix" ]; then
        params="prefix=${prefix}"
    fi
    
    # JSON 이스케이프
    local json_payload=$(python3 -c "import json; print(json.dumps({'key': '$key', 'value': '$value'}))")
    
    curl -s -f -X POST \
        -H "X-API-Key: ${CONSUL_API_KEY}" \
        -H "Content-Type: application/json" \
        -d "$json_payload" \
        "${url}${params:+?$params}" 2>/dev/null || echo '{"success": false, "detail": "Request failed"}'
}

# DELETE 요청
api_delete() {
    local key="$1"
    local prefix="$2"
    
    check_api_key
    
    # URL 인코딩
    local encoded_key=$(url_encode "$key")
    local url="${CONSUL_API_URL}/api/v1/config/${encoded_key}"
    local params=""
    
    if [ -n "$prefix" ]; then
        params="prefix=${prefix}"
    fi
    
    curl -s -f -X DELETE \
        -H "X-API-Key: ${CONSUL_API_KEY}" \
        "${url}${params:+?$params}" 2>/dev/null || echo '{"success": false, "detail": "Request failed"}'
}

# JSON 파싱 (jq 사용)
parse_json() {
    local query="$1"
    if command -v jq &> /dev/null; then
        jq -r "$query"
    else
        # jq 없으면 python 사용
        python3 -c "import sys, json; data=json.load(sys.stdin); result=$query; print(result if result is not None else '')"
    fi
}

# URL 인코딩
url_encode() {
    local string="$1"
    python3 -c "import urllib.parse; print(urllib.parse.quote('$string', safe=''))"
}

# 메인 로직
main() {
    local command=""
    local key=""
    local value=""
    local prefix=""
    local decrypt="true"
    local output=""
    local overwrite=false
    local format="env"
    local strip_prefix=""
    local no_uppercase=false
    local no_sort=false
    local mask_secrets=false
    
    # 인자 파싱
    while [[ $# -gt 0 ]]; do
        case $1 in
            export|get|list|set|delete)
                command="$1"
                shift
                ;;
            --prefix)
                prefix="$2"
                shift 2
                ;;
            --app)
                CONSUL_APP="$2"
                shift 2
                ;;
            --env)
                CONSUL_ENV="$2"
                shift 2
                ;;
            --all-env)
                ALL_ENV=true
                shift
                ;;
            --output)
                output="$2"
                shift 2
                ;;
            --overwrite)
                overwrite=true
                shift
                ;;
            --format)
                format="$2"
                shift 2
                ;;
            --strip-prefix)
                strip_prefix="$2"
                shift 2
                ;;
            --no-uppercase)
                no_uppercase=true
                shift
                ;;
            --no-sort)
                no_sort=true
                shift
                ;;
            --mask-secrets)
                mask_secrets=true
                shift
                ;;
            --quiet)
                QUIET=true
                shift
                ;;
            --no-decrypt)
                decrypt="false"
                shift
                ;;
            --api-key)
                CONSUL_API_KEY="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                if [ -z "$key" ]; then
                    key="$1"
                elif [ -z "$value" ]; then
                    value="$1"
                else
                    log_error "Unknown argument: $1"
                    show_help
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # prefix 자동 구성
    if [ -z "$prefix" ] && [ -n "$CONSUL_APP" ] && [ -n "$CONSUL_ENV" ]; then
        prefix="$CONSUL_APP/$CONSUL_ENV"
    fi
    
    # 기본 명령어 설정 (명령어가 지정되지 않은 경우)
    if [ -z "$command" ]; then
        command="export"
        # prefix가 key로 설정되었다면 prefix로 이동
        if [ -n "$key" ] && [ -z "$prefix" ]; then
            prefix="$key"
            key=""
        fi
    fi
    
    # 앱 기반 안전성 검사 (export 명령어에만 적용)
    if [ "$command" = "export" ] && [ -n "$CONSUL_APP" ]; then
        if [ -z "$CONSUL_ENV" ] && [ "$ALL_ENV" != "true" ]; then
            echo -e "${RED}Error: Safety check: When --app is specified, you must specify either:${NC}" >&2
            echo -e "${RED}  --env <environment>     (safe: specific environment only)${NC}" >&2
            echo -e "${RED}  --all-env              (dangerous: all environments)${NC}" >&2
            echo "" >&2
            echo -e "${RED}This prevents accidentally exporting configurations from all environments.${NC}" >&2
            exit 1
        fi
        
        if [ "$ALL_ENV" = "true" ]; then
            echo -e "${YELLOW}WARNING: ⚠️  Using --all-env: This will include ALL environments for app '$CONSUL_APP'${NC}" >&2
            echo -e "${YELLOW}WARNING: ⚠️  Make sure this is what you intended!${NC}" >&2
            # --all-env 사용 시 prefix를 app만으로 설정
            prefix="$CONSUL_APP"
        fi
    fi
    
    # 명령어 실행
    case $command in
        get)
            if [ -z "$key" ]; then
                log_error "Key required"
                exit 1
            fi
            
            log_info "Getting key: ${key}"
            
            response=$(api_get "$key" "$prefix" "$decrypt")
            
            if echo "$response" | grep -q '"success".*true'; then
                value=$(echo "$response" | parse_json '.value')
                is_secret=$(echo "$response" | parse_json '.is_secret')
                is_masked=$(echo "$response" | parse_json '.is_masked')
                
                echo "${key}: ${value}"
                
                if [ "$is_secret" = "true" ]; then
                    if [ "$is_masked" = "true" ]; then
                        log_warn "Value is masked (use without --no-decrypt to see plaintext)"
                    else
                        log_info "✓ Decrypted secret value"
                    fi
                fi
            else
                log_error "Failed to get key"
                echo "$response" | parse_json '.detail' >&2
                exit 1
            fi
            ;;
            
        export)
            prefix="${key:-$prefix}"
            
            response=$(api_list "$prefix")
            
            if echo "$response" | grep -q '"count"'; then
                # 설정 개수 수집 (요약용)
                local config_count
                config_count=$(echo "$response" | parse_json '.count')
                
                # .env 형식으로 변환
                local result
                result=$(echo "$response" | parse_json '.items | to_entries[] | "\(.key | gsub("/"; "_") | ascii_upcase)=\(.value)"')
                
                # 출력 (stdout 또는 파일)
                write_output "$result" "$output" "$overwrite"
                
                # 요약 정보 (stderr로 출력, --quiet가 아닐 때만)
                if [ "$QUIET" != "true" ] && ([ -z "$output" ] || [ "$output" = "-" ]); then
                    # stdout 출력 시에만 요약 출력 (파일 출력 시에는 write_output에서 이미 메시지 출력됨)
                    local decrypt_status="decrypted"
                    if [ "$decrypt" = "false" ]; then
                        decrypt_status="encrypted"
                    fi
                    log_info "Exported $config_count configurations ($decrypt_status)"
                fi
            else
                log_error "Failed to export configurations"
                echo "$response" >&2
                exit 1
            fi
            ;;
            
        list)
            prefix="${key:-$prefix}"
            echo -e "${BLUE}INFO: Listing configurations (prefix: ${prefix:-none})${NC}" >&2
            
            response=$(api_list "$prefix")
            
            if echo "$response" | grep -q '"count"'; then
                count=$(echo "$response" | parse_json '.count')
                echo -e "${GREEN}Found ${count} configurations:${NC}" >&2
                echo "$response" | parse_json '.items | to_entries[] | "\(.key): \(.value)"'
            else
                echo -e "${RED}Error: Failed to list configurations${NC}" >&2
                echo "$response" >&2
                exit 1
            fi
            ;;
            
        set)
            if [ -z "$key" ] || [ -z "$value" ]; then
                echo -e "${RED}Error: Key and value required${NC}" >&2
                exit 1
            fi
            
            echo -e "${BLUE}INFO: Setting key: ${key}${NC}" >&2
            
            response=$(api_set "$key" "$value" "$prefix")
            
            if echo "$response" | grep -q '"success".*true'; then
                echo -e "${GREEN}INFO: ✓ Successfully set key${NC}" >&2
            else
                echo -e "${RED}Error: Failed to set key${NC}" >&2
                echo "$response" >&2
                exit 1
            fi
            ;;
            
        delete)
            if [ -z "$key" ]; then
                echo -e "${RED}Error: Key required${NC}" >&2
                exit 1
            fi
            
            echo -e "${BLUE}INFO: Deleting key: ${key}${NC}" >&2
            
            response=$(api_delete "$key" "$prefix")
            
            if echo "$response" | grep -q '"success".*true'; then
                echo -e "${GREEN}INFO: ✓ Successfully deleted key${NC}" >&2
            else
                echo -e "${RED}Error: Failed to delete key${NC}" >&2
                echo "$response" >&2
                exit 1
            fi
            ;;
            
        *)
            echo -e "${RED}Error: Unknown command: ${command}${NC}" >&2
            show_help
            exit 1
            ;;
    esac
}

main "$@"
