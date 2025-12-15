#!/bin/bash
#
# Consul Direct Client - Consul HTTP API 직접 접근 (Shell Script)
#
# - Consul KV API를 직접 사용하여 Configuration 관리
# - APP/ENV 또는 PREFIX 기반으로 키 prefix 관리
# - .env / shell / json export
# - curl + jq 기반 구현
#

set -uo pipefail

# 기본값 설정
CONSUL_HTTP_ADDR="${CONSUL_HTTP_ADDR:-http://localhost:8500}"
CONSUL_PREFIX="${CONSUL_PREFIX:-}"
CONSUL_APP="${CONSUL_APP:-}"
CONSUL_ENV="${CONSUL_ENV:-}"
CONSUL_TIMEOUT="${CONSUL_TIMEOUT:-5}"
CONSUL_USE_QUOTES="${CONSUL_USE_QUOTES:-false}"

VERBOSE=false
ENV_FILE=""
ALL_ENV=false
QUIET=false

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 로깅 함수
log_info() {
    if [[ "$QUIET" != "true" ]]; then
        echo -e "${GREEN}INFO:${NC} $1" >&2
    fi
}

log_warn() {
    echo -e "${YELLOW}WARNING:${NC} $1" >&2
}

log_error() {
    echo -e "${RED}ERROR:${NC} $1" >&2
}

log_debug() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${BLUE}DEBUG:${NC} $1" >&2
    fi
}

# 출력 유틸리티
write_output() {
    local content="$1"
    local output_file="$2"
    local overwrite="${3:-true}"
    
    if [[ -z "$output_file" ]] || [[ "$output_file" == "-" ]]; then
        # stdout으로 출력 (순수 데이터만)
        echo "$content"
        return 0
    fi
    
    # 파일 존재 여부 확인
    if [[ -f "$output_file" ]] && [[ "$overwrite" != "true" ]]; then
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

# 설정 소스 추적 함수
get_config_source() {
    local var_name="$1"
    local current_value="${!var_name}"
    
    # CLI에서 설정된 경우 (이미 처리됨)
    case "$var_name" in
        CONSUL_HTTP_ADDR)
            if [[ "$current_value" != "http://localhost:8500" ]]; then
                echo "CLI(--consul-url)"
            elif [[ -n "${!var_name}" ]] && [[ -f "$ENV_FILE" ]] && grep -q "^CONSUL_HTTP_ADDR=" "$ENV_FILE" 2>/dev/null; then
                echo ".env(CONSUL_HTTP_ADDR)"
            elif [[ -n "${CONSUL_HTTP_ADDR_ORIG:-}" ]]; then
                echo "OS_ENV(CONSUL_HTTP_ADDR)"
            else
                echo "DEFAULT"
            fi
            ;;
        CONSUL_APP)
            if [[ -n "$current_value" ]]; then
                echo "CLI(--app)"
            else
                echo "DEFAULT"
            fi
            ;;
        CONSUL_ENV)
            if [[ -n "$current_value" ]]; then
                echo "CLI(--env)"
            else
                echo "DEFAULT"
            fi
            ;;
        CONSUL_PREFIX)
            if [[ -n "$current_value" ]]; then
                if [[ -n "$CONSUL_APP" ]] && [[ -n "$CONSUL_ENV" ]] && [[ "$current_value" == "$CONSUL_APP/$CONSUL_ENV" ]]; then
                    echo "AUTO(app/env)"
                else
                    echo "CLI(--prefix)"
                fi
            else
                echo "DEFAULT"
            fi
            ;;
        CONSUL_TIMEOUT)
            if [[ "$current_value" != "5" ]]; then
                echo "CLI(--timeout)"
            else
                echo "DEFAULT"
            fi
            ;;
        CONSUL_USE_QUOTES)
            if [[ "$current_value" == "true" ]]; then
                echo "CLI(--use-quotes)"
            else
                echo "DEFAULT"
            fi
            ;;
        *)
            echo "UNKNOWN"
            ;;
    esac
}

# .env 파일 로드 함수
load_env_file() {
    local env_file="$1"
    local loaded_count=0
    
    if [[ -f "$env_file" ]]; then
        log_debug "Loading .env file: $env_file"
        
        # 파일을 한 번에 읽어서 처리
        local content
        content=$(cat "$env_file")
        
        # 줄별로 처리
        while IFS= read -r line; do
            # 주석과 빈 줄 건너뛰기
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "${line// }" ]] && continue
            
            # export 제거
            line="${line#export }"
            line="${line# }"  # 앞쪽 공백 제거
            
            # KEY=VALUE 형식 확인
            if [[ "$line" =~ ^[^=]+= ]]; then
                local key="${line%%=*}"
                local value="${line#*=}"
                key="${key// /}"  # 공백 제거
                value="${value# }"  # 앞쪽 공백 제거
                
                # 따옴표 제거 (양끝만)
                if [[ ${#value} -ge 2 ]]; then
                    if [[ "$value" =~ ^\".*\"$ ]] || [[ "$value" =~ ^\'.*\'$ ]]; then
                        value="${value:1:-1}"
                    fi
                fi
                
                # 환경변수로 설정 (기존 값이 없을 때만 - Python 버전과 동일한 우선순위)
                if [[ -n "$key" ]] && [[ -z "${!key:-}" ]]; then
                    export "$key"="$value"
                    ((loaded_count++))
                    log_debug "Loaded from .env: $key"
                fi
            fi
        done <<< "$content"
        
        if [[ "$VERBOSE" == "true" ]]; then
            echo "[env] Loaded $loaded_count variables from $(basename "$env_file")" >&2
        fi
    else
        log_debug ".env file not found: $env_file"
    fi
}

# URL 인코딩 함수
url_encode() {
    local string="$1"
    local encoded=""
    local pos c o
    
    for (( pos=0 ; pos<${#string} ; pos++ )); do
        c=${string:$pos:1}
        case "$c" in
            [-_.~a-zA-Z0-9] ) o="${c}" ;;
            * ) printf -v o '%%%02x' "'$c" ;;
        esac
        encoded+="${o}"
    done
    echo "${encoded}"
}

# Base64 디코딩 함수
base64_decode() {
    if command -v base64 >/dev/null 2>&1; then
        echo "$1" | base64 -d 2>/dev/null || echo "$1"
    else
        echo "$1"
    fi
}

# prefix와 key 결합
build_key() {
    local key="$1"
    if [[ -n "$CONSUL_PREFIX" ]]; then
        echo "${CONSUL_PREFIX}/${key#/}"
    else
        echo "${key#/}"
    fi
}

# prefix 제거
strip_prefix() {
    local full_key="$1"
    if [[ -n "$CONSUL_PREFIX" ]]; then
        echo "${full_key#$CONSUL_PREFIX/}"
    else
        echo "$full_key"
    fi
}

# 환경변수명 변환
to_env_name() {
    local key="$1"
    local strip_prefix="$2"
    
    # strip_prefix 제거
    if [[ -n "$strip_prefix" ]]; then
        key="${key#$strip_prefix/}"
    fi
    
    # / -> _, 대문자 변환
    key="${key//\//_}"
    echo "$key" | tr '[:lower:]' '[:upper:]'
}

# 값 이스케이프
escape_value() {
    local value="$1"
    # 백슬래시, 따옴표, 개행 이스케이프
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    echo "$value"
}

# Consul에서 단일 키 조회
get_config() {
    local key="$1"
    local full_key
    full_key=$(build_key "$key")
    local encoded_key
    encoded_key=$(url_encode "$full_key")
    
    log_debug "Getting key: $full_key"
    
    local response
    response=$(curl -s -f --max-time "$CONSUL_TIMEOUT" \
        "$CONSUL_HTTP_ADDR/v1/kv/$encoded_key" 2>/dev/null || echo "")
    
    if [[ -z "$response" ]]; then
        return 1
    fi
    
    local value
    value=$(echo "$response" | jq -r '.[0].Value // empty' 2>/dev/null || echo "")
    
    if [[ -n "$value" ]]; then
        base64_decode "$value"
        return 0
    fi
    
    return 1
}

# Consul에서 모든 키 조회
get_all_configs() {
    local include_metadata="${1:-false}"
    local url
    if [[ -n "$CONSUL_PREFIX" ]]; then
        local encoded_prefix
        encoded_prefix=$(url_encode "$CONSUL_PREFIX/")
        url="$CONSUL_HTTP_ADDR/v1/kv/$encoded_prefix?recurse=true"
    else
        url="$CONSUL_HTTP_ADDR/v1/kv/?recurse=true"
    fi
    
    log_debug "Getting all configs from: $url"
    
    local response
    response=$(curl -s -f --max-time "$CONSUL_TIMEOUT" "$url" 2>/dev/null || echo "[]")
    
    if [[ "$response" == "[]" ]] || [[ -z "$response" ]]; then
        echo "{}"
        return 0
    fi
    
    # jq로 JSON 변환 (__metadata__ 필터링 포함)
    echo "$response" | jq -r --arg include_metadata "$include_metadata" --arg prefix "$CONSUL_PREFIX" '
        if . == null then {} else
            [.[] | select(.Value != null) | 
                {
                    key: .Key,
                    value: (.Value | @base64d),
                    relative_key: (
                        if $prefix != "" then
                            .Key | sub("^" + $prefix + "/"; "")
                        else
                            .Key
                        end
                    )
                } |
                # __metadata__ 필터링
                select(
                    $include_metadata == "true" or 
                    (.relative_key | contains("__metadata__") | not)
                )
            ] | 
            reduce .[] as $item ({}; 
                .[$item.relative_key] = $item.value
            )
        end
    ' 2>/dev/null || echo "{}"
}

# 설정 저장
set_config() {
    local key="$1"
    local value="$2"
    local full_key
    full_key=$(build_key "$key")
    local encoded_key
    encoded_key=$(url_encode "$full_key")
    
    log_debug "Setting key: $full_key"
    
    local response
    response=$(curl -s -f --max-time "$CONSUL_TIMEOUT" \
        -X PUT \
        -d "$value" \
        "$CONSUL_HTTP_ADDR/v1/kv/$encoded_key" 2>/dev/null || echo "false")
    
    if [[ "$response" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

# 설정 삭제
delete_config() {
    local key="$1"
    local full_key
    full_key=$(build_key "$key")
    local encoded_key
    encoded_key=$(url_encode "$full_key")
    
    log_debug "Deleting key: $full_key"
    
    local response
    response=$(curl -s -f --max-time "$CONSUL_TIMEOUT" \
        -X DELETE \
        "$CONSUL_HTTP_ADDR/v1/kv/$encoded_key" 2>/dev/null || echo "false")
    
    if [[ "$response" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

# export 함수
export_configs() {
    local strip_prefix="$1"
    local format="$2"
    local uppercase="$3"
    local sort_keys="$4"
    local include_metadata="$5"
    
    local configs
    configs=$(get_all_configs "$include_metadata")
    
    if [[ "$configs" == "{}" ]]; then
        return 0
    fi
    
    local keys
    if [[ "$sort_keys" == "true" ]]; then
        keys=$(echo "$configs" | jq -r 'keys | sort | .[]' 2>/dev/null || echo "")
    else
        keys=$(echo "$configs" | jq -r 'keys | .[]' 2>/dev/null || echo "")
    fi
    
    if [[ "$format" == "json" ]]; then
        # JSON 형식
        echo "$configs" | jq -r '
            with_entries(
                .key |= (
                    if "'$strip_prefix'" != "" then
                        sub("^'$strip_prefix'/"; "")
                    else . end |
                    gsub("/"; "_") |
                    if "'$uppercase'" == "true" then ascii_upcase else . end
                )
            )
        ' 2>/dev/null || echo "{}"
        return 0
    fi
    
    # env 또는 shell 형식
    while IFS= read -r key; do
        [[ -z "$key" ]] && continue
        
        local relative_key
        relative_key=$(strip_prefix "$key")
        
        local env_name
        env_name=$(to_env_name "$relative_key" "$strip_prefix")
        if [[ "$uppercase" != "true" ]]; then
            env_name=$(echo "$env_name" | tr '[:upper:]' '[:lower:]')
        fi
        
        local value
        value=$(echo "$configs" | jq -r --arg k "$key" '.[$k] // ""' 2>/dev/null || echo "")
        
        if [[ "$format" == "shell" ]]; then
            # shell: 항상 따옴표 사용
            local escaped_value
            escaped_value=$(escape_value "$value")
            echo "export $env_name=\"$escaped_value\""
        else
            # env: use_quotes 설정에 따라
            if [[ "$CONSUL_USE_QUOTES" == "true" ]]; then
                local escaped_value
                escaped_value=$(escape_value "$value")
                echo "$env_name=\"$escaped_value\""
            else
                echo "$env_name=$value"
            fi
        fi
    done <<< "$keys"
}

# 도움말 출력
show_help() {
    cat << 'EOF'
Consul Direct Client - Consul HTTP API 직접 접근

Usage: consul_kv.sh [OPTIONS] [COMMAND] [ARGS...]

기본 명령어: export (명령어를 지정하지 않으면 export가 실행됩니다)

Global Options:
  --env-file FILE         Load environment from .env file
  --consul-url URL        Consul HTTP URL (env: CONSUL_HTTP_ADDR)
  --prefix PREFIX         Key prefix (env: CONSUL_PREFIX)
  --app APP               Application name (env: CONSUL_APP)
  --env ENV               Environment name (env: CONSUL_ENV)
  --all-env               Include all environments (use with --app, dangerous!)
  --timeout SECONDS       HTTP timeout (env: CONSUL_TIMEOUT)
  --use-quotes            Use quotes in env format (env: CONSUL_USE_QUOTES)
  --quiet                 Minimize stderr output (warnings still shown)
  -v, --verbose           Verbose output
  -h, --help              Show this help

Commands:
  get KEY                 Get a configuration value
    --with-key            Print "key: value" format
  
  list                    List all configurations
    --match PATTERN       Filter keys containing pattern
    --include-metadata    Include __metadata__ keys (normally hidden)
  
  export                  Export configurations
    --strip-prefix PREFIX Strip prefix from env names
    --format FORMAT       Output format: env, shell, json (default: env)
    --no-uppercase        Don't uppercase env names
    --no-sort             Don't sort keys
    --output FILE         Write to file (default: stdout, use "-" for explicit stdout)
    --overwrite           Overwrite existing output file
    --include-metadata    Include __metadata__ keys (normally hidden)
  
  set KEY VALUE           Set a configuration value
  
  delete KEY              Delete a configuration
    -y, --yes             Don't ask for confirmation
  
  count                   Count configurations

Examples:
  # 기본 명령어 (export) 사용 - 안전한 방식
  consul_kv.sh --app web_service --env prod
  consul_kv.sh --prefix web_service/prod --output .env

  # 위험한 방식 - 모든 환경 포함 (명시적 옵션 필요)
  consul_kv.sh --app web_service --all-env export

  # .env 먼저 사용하고, CLI로 덮어쓰기
  consul_kv.sh --env-file .env -v list

  # APP/ENV 방식(추천)
  consul_kv.sh --app web_service --env prod list

  # prefix 직접 지정하여 export
  consul_kv.sh --prefix web_service/prod export --output .env

  # 따옴표 포함하여 export
  consul_kv.sh --use-quotes
EOF
}

# 메인 함수
main() {
    local command=""
    local args=()
    
    # 전역 export 옵션들 (기본 명령어에서 사용 가능)
    local global_output=""
    local global_overwrite=false
    local global_format="env"
    local global_strip_prefix=""
    local global_no_uppercase=false
    local global_no_sort=false
    local global_include_metadata=false
    
    # 인자 파싱
    while [[ $# -gt 0 ]]; do
        case $1 in
            --env-file)
                ENV_FILE="$2"
                shift 2
                ;;
            --consul-url)
                CONSUL_HTTP_ADDR="$2"
                shift 2
                ;;
            --prefix)
                CONSUL_PREFIX="$2"
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
            --timeout)
                CONSUL_TIMEOUT="$2"
                shift 2
                ;;
            --use-quotes)
                CONSUL_USE_QUOTES="true"
                shift
                ;;
            --quiet)
                QUIET=true
                shift
                ;;
            # 전역 export 옵션들 (기본 명령어에서도 사용 가능)
            --output)
                global_output="$2"
                shift 2
                ;;
            --overwrite)
                global_overwrite=true
                shift
                ;;
            --format)
                global_format="$2"
                shift 2
                ;;
            --strip-prefix)
                global_strip_prefix="$2"
                shift 2
                ;;
            --no-uppercase)
                global_no_uppercase=true
                shift
                ;;
            --no-sort)
                global_no_sort=true
                shift
                ;;
            --include-metadata)
                global_include_metadata=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            get|list|export|set|delete|count)
                command="$1"
                shift
                args=("$@")
                break
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # .env 파일 로드 (Python 버전과 동일한 로직)
    if [[ -n "$ENV_FILE" ]]; then
        load_env_file "$ENV_FILE"
    elif [[ -f ".env" ]]; then
        ENV_FILE=".env"
        load_env_file ".env"
    fi
    
    # prefix 자동 구성
    if [[ -z "$CONSUL_PREFIX" ]] && [[ -n "$CONSUL_APP" ]] && [[ -n "$CONSUL_ENV" ]]; then
        CONSUL_PREFIX="$CONSUL_APP/$CONSUL_ENV"
        log_debug "Auto-generated prefix: $CONSUL_PREFIX"
    fi
    
    # 기본 명령어 설정 (명령어가 지정되지 않은 경우)
    if [[ -z "$command" ]]; then
        command="export"
        log_debug "Using default command: export"
    fi
    
    # 앱 기반 안전성 검사 (export 명령어에만 적용)
    if [[ "$command" == "export" ]] && [[ -n "$CONSUL_APP" ]]; then
        if [[ -z "$CONSUL_ENV" ]] && [[ "$ALL_ENV" != "true" ]]; then
            log_error "Safety check: When --app is specified, you must specify either:"
            log_error "  --env <environment>     (safe: specific environment only)"
            log_error "  --all-env              (dangerous: all environments)"
            log_error ""
            log_error "This prevents accidentally exporting configurations from all environments."
            exit 1
        fi
        
        if [[ "$ALL_ENV" == "true" ]]; then
            log_warn "⚠️  Using --all-env: This will include ALL environments for app '$CONSUL_APP'"
            log_warn "⚠️  Make sure this is what you intended!"
            # --all-env 사용 시 prefix를 app만으로 설정
            CONSUL_PREFIX="$CONSUL_APP"
            log_debug "Modified prefix for --all-env: $CONSUL_PREFIX"
        fi
    fi
    
    # verbose 출력 (Python 버전과 동일한 형식)
    if [[ "$VERBOSE" == "true" ]]; then
        echo "=== Effective Configuration (with sources) ===" >&2
        if [[ -n "$ENV_FILE" ]]; then
            echo "- ENV_FILE: $ENV_FILE (loaded: YES)" >&2
        else
            echo "- ENV_FILE: (none) (loaded: NO)" >&2
        fi
        
        # 각 설정의 소스 표시
        echo "- CONSUL_HTTP_ADDR: $CONSUL_HTTP_ADDR    <- $(get_config_source CONSUL_HTTP_ADDR)" >&2
        echo "- CONSUL_APP: $CONSUL_APP    <- $(get_config_source CONSUL_APP)" >&2
        echo "- CONSUL_ENV: $CONSUL_ENV    <- $(get_config_source CONSUL_ENV)" >&2
        echo "- CONSUL_PREFIX: $CONSUL_PREFIX    <- $(get_config_source CONSUL_PREFIX)" >&2
        echo "- CONSUL_TIMEOUT: $CONSUL_TIMEOUT    <- $(get_config_source CONSUL_TIMEOUT)" >&2
        echo "- CONSUL_USE_QUOTES: $CONSUL_USE_QUOTES    <- $(get_config_source CONSUL_USE_QUOTES)" >&2
        echo "" >&2
    fi
    
    # 필수 도구 확인
    if ! command -v curl >/dev/null 2>&1; then
        log_error "curl is required but not installed"
        exit 1
    fi
    
    if ! command -v jq >/dev/null 2>&1; then
        log_error "jq is required but not installed"
        exit 1
    fi
    
    # 명령어 실행
    log_debug "Executing command: $command"
    case "$command" in
        get)
            if [[ ${#args[@]} -lt 1 ]]; then
                log_error "get command requires a key"
                exit 1
            fi
            
            local key="${args[0]}"
            local with_key=false
            
            # 옵션 파싱
            for arg in "${args[@]:1}"; do
                case "$arg" in
                    --with-key) with_key=true ;;
                esac
            done
            
            local value
            if value=$(get_config "$key"); then
                if [[ "$with_key" == "true" ]]; then
                    echo "$key: $value"
                else
                    echo "$value"
                fi
            else
                log_error "Key not found: $key"
                exit 1
            fi
            ;;
            
        list)
            local match=""
            local include_metadata="false"
            
            # 옵션 파싱
            for ((i=0; i<${#args[@]}; i++)); do
                case "${args[i]}" in
                    --match)
                        match="${args[i+1]}"
                        ((i++))
                        ;;
                    --include-metadata)
                        include_metadata="true"
                        ;;
                esac
            done
            
            local configs
            configs=$(get_all_configs "$include_metadata")
            local count=0
            
            local keys
            keys=$(echo "$configs" | jq -r 'keys | sort | .[]' 2>/dev/null || echo "")
            
            while IFS= read -r key; do
                [[ -z "$key" ]] && continue
                
                # 매치 필터 적용
                if [[ -n "$match" ]] && [[ "$key" != *"$match"* ]]; then
                    continue
                fi
                
                local value
                value=$(echo "$configs" | jq -r --arg k "$key" '.[$k] // ""' 2>/dev/null || echo "")
                echo "$key: $value"
                ((count++))
            done <<< "$keys"
            
            log_info "Total: $count configurations"
            ;;
            
        export)
            # 전역 옵션을 기본값으로 사용하고, 서브커맨드 옵션으로 덮어쓰기
            local strip_prefix="$global_strip_prefix"
            local format="$global_format"
            local uppercase=$([ "$global_no_uppercase" = "true" ] && echo "false" || echo "true")
            local sort_keys=$([ "$global_no_sort" = "true" ] && echo "false" || echo "true")
            local output="$global_output"
            local overwrite="$global_overwrite"
            local include_metadata=$([ "$global_include_metadata" = "true" ] && echo "true" || echo "false")
            
            # 서브커맨드 옵션 파싱 (전역 옵션 덮어쓰기)
            for ((i=0; i<${#args[@]}; i++)); do
                case "${args[i]}" in
                    --strip-prefix)
                        strip_prefix="${args[i+1]}"
                        ((i++))
                        ;;
                    --format)
                        format="${args[i+1]}"
                        ((i++))
                        ;;
                    --no-uppercase)
                        uppercase=false
                        ;;
                    --no-sort)
                        sort_keys=false
                        ;;
                    --output)
                        output="${args[i+1]}"
                        ((i++))
                        ;;
                    --overwrite)
                        overwrite=true
                        ;;
                    --include-metadata)
                        include_metadata="true"
                        ;;
                esac
            done
            
            # 설정 개수 수집 (요약용)
            local all_configs
            all_configs=$(get_all_configs "true")  # metadata 포함하여 개수 계산
            local config_count=0
            local metadata_count=0
            
            if [[ "$all_configs" != "{}" ]]; then
                local keys
                keys=$(echo "$all_configs" | jq -r 'keys | .[]' 2>/dev/null || echo "")
                while IFS= read -r key; do
                    [[ -z "$key" ]] && continue
                    if [[ "$key" == *"__metadata__"* ]]; then
                        ((metadata_count++))
                    else
                        ((config_count++))
                    fi
                done <<< "$keys"
            fi
            
            # 실제 export 수행
            local result
            result=$(export_configs "$strip_prefix" "$format" "$uppercase" "$sort_keys" "$include_metadata")
            
            # 출력 (stdout 또는 파일)
            write_output "$result" "$output" "$overwrite"
            
            # 요약 정보 (stderr로 출력, --quiet가 아닐 때만)
            if [[ "$QUIET" != "true" ]] && ([[ -z "$output" ]] || [[ "$output" == "-" ]]); then
                # stdout 출력 시에만 요약 출력 (파일 출력 시에는 write_output에서 이미 메시지 출력됨)
                local summary="Exported $config_count configurations"
                if [[ $metadata_count -gt 0 ]] && [[ "$include_metadata" != "true" ]]; then
                    summary="$summary ($metadata_count metadata keys excluded)"
                fi
                log_info "$summary"
            fi
            ;;
            
        set)
            if [[ ${#args[@]} -lt 2 ]]; then
                log_error "set command requires key and value"
                exit 1
            fi
            
            local key="${args[0]}"
            local value="${args[1]}"
            
            if set_config "$key" "$value"; then
                log_info "✓ Successfully set key: $key"
            else
                log_error "Failed to set configuration"
                exit 1
            fi
            ;;
            
        delete)
            if [[ ${#args[@]} -lt 1 ]]; then
                log_error "delete command requires a key"
                exit 1
            fi
            
            local key="${args[0]}"
            local yes=false
            
            # 옵션 파싱
            for arg in "${args[@]:1}"; do
                case "$arg" in
                    -y|--yes) yes=true ;;
                esac
            done
            
            if [[ "$yes" != "true" ]]; then
                echo -n "Delete key '$key'? [y/N]: " >&2
                read -r answer
                if [[ "$answer" != "y" ]] && [[ "$answer" != "yes" ]]; then
                    log_info "Cancelled"
                    exit 0
                fi
            fi
            
            if delete_config "$key"; then
                log_info "✓ Successfully deleted key: $key"
            else
                log_error "Failed to delete configuration"
                exit 1
            fi
            ;;
            
        count)
            local configs
            configs=$(get_all_configs "false")  # count에서는 기본적으로 metadata 제외
            local count
            count=$(echo "$configs" | jq -r 'keys | length' 2>/dev/null || echo "0")
            echo "$count"
            log_info "Total: $count configurations"
            ;;
            

            
        *)
            log_error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

# 스크립트 실행
main "$@"