#!/bin/bash
# scripts/timed_run_script.sh
# Timer wrapper for Makefile commands with pretty output

set -o pipefail

# ================================================================
# Configuration from environment
# ================================================================
TASK_NAME="${TIMED_TASK_NAME:-Task}"
MODE="${TIMED_MODE:-auto}"
DEBUG="${TIMED_DEBUG:-false}"
COLORS="${TIMED_COLORS:-true}"

IS_TTY="no"
if [ -t 1 ]; then   # stdout 기준으로만 판정
    IS_TTY="yes"
fi

# (옵션) 강제 모드 오버라이드: TIMED_FORCE_MODE=pipe|interactive|quiet
if [ -n "${TIMED_FORCE_MODE:-}" ]; then
    MODE="$TIMED_FORCE_MODE"
fi

if [ "$COLORS" = "true" ] && [ -t 1 ]; then
    YELLOW="${YELLOW:-\033[33m}"
    GREEN="${GREEN:-\033[32m}"
    RED="${RED:-\033[31m}"
    BLUE="${BLUE:-\033[34m}"
    RESET="${RESET:-\033[0m}"
else
    YELLOW=""
    GREEN=""
    RED=""
    BLUE=""
    RESET=""
fi

# ================================================================
# Helper functions
# ================================================================
get_nano_time() {
    if command -v gdate >/dev/null 2>&1; then
        gdate +%s%N
    elif command -v date >/dev/null 2>&1 && date +%s%N 2>/dev/null | grep -q '^[0-9]'; then
        date +%s%N
    else
        python3 -c 'import time; print(int(time.time() * 10**9))'
    fi
}

# Format duration from nanoseconds
format_duration() {
    local ns=$1
    if [ $ns -lt 1000000000 ]; then
        echo "$((ns / 1000000))ms"
    else
        local s=$((ns / 1000000000))
        if [ $s -ge 60 ]; then
            local m=$((s / 60))
            local remaining=$((s % 60))
            echo "${m}m ${remaining}s"
        else
            echo "${s}s"
        fi
    fi
}

# Draw header box
draw_header() {
    local msg="🚀 Executing: $TASK_NAME"

    # ANSI 코드 제거 후 실제 길이
    local clean_msg=$(echo "$msg" | sed 's/\x1b\[[0-9;]*m//g')
    local clean_len=${#clean_msg}

    # 기본 폭 100, 하지만 메시지가 더 길면 메시지에 맞게 늘린다
    local width=$((clean_len + 4))
    if [ $width -lt 100 ]; then
        width=100
    fi

    printf "\n${YELLOW}┌"
    printf '─%.0s' $(seq 1 $width)
    printf "┐${RESET}\n"

    # 메시지 출력 (좌우 1칸씩 여유)
    printf "${YELLOW}│${RESET} %s" "$msg"
    local padding=$((width - clean_len - 2))
    printf '%*s' $padding ""
    printf "${YELLOW}│${RESET}\n"

    printf "${YELLOW}├"
    printf '─%.0s' $(seq 1 $width)
    printf "┤${RESET}\n"
}

# Draw footer box with command details on failure
draw_footer() {
    local exit_code=$1
    local duration=$2
    local command_str="${3:-}"
    local width=100
    
    printf "${YELLOW}├"
    printf '%.0s─' $(seq 1 $width)
    printf "┤${RESET}\n"
    
    if [ $exit_code -eq 0 ]; then
        local msg="✅ SUCCESS - Completed in $duration"
        printf "${YELLOW}│${RESET} ${GREEN}$msg${RESET}"
        local clean_msg=$(echo "$msg" | sed 's/\x1b\[[0-9;]*m//g')
        local padding=$((width - ${#clean_msg} - 2))
        printf '%*s' $padding ""
        printf "${YELLOW}│${RESET}\n"
    else        
        local msg="❌ FAILED - Exit code $exit_code after $duration"
        printf "${YELLOW}│${RESET} ${RED}$msg${RESET}"
        local clean_msg=$(echo "$msg" | sed 's/\x1b\[[0-9;]*m//g')
        local padding=$((width - ${#clean_msg} - 2))
        printf '%*s' $padding ""
        printf "${YELLOW}│${RESET}\n"
        
        # 실행한 커맨드 표시 (가능한 경우)
        if [ -n "$command_str" ]; then
            printf "${YELLOW}│${RESET}\n"
            printf "${YELLOW}│${RESET} ${BLUE}Failed Command:${RESET}\n"
            
            # 긴 커맨드는 여러 줄로 분할해서 표시
            local cmd_display="$command_str"
            while [ -n "$cmd_display" ]; do
                local line_part
                if [ ${#cmd_display} -gt 94 ]; then
                    line_part="${cmd_display:0:94}"
                    cmd_display="${cmd_display:94}"
                else
                    line_part="$cmd_display"
                    cmd_display=""
                fi
                # 모든 줄을 동일한 회색(기본색)으로 표시 , but 복붙하기 힘들어서 원본 출력
                # printf "${YELLOW}│${RESET}   %s\n" "$line_part"                
            done
            printf "${YELLOW}│${RESET}   %s\n" "$command_str"
        fi
    fi
    
    printf "${YELLOW}└"
    printf '%.0s─' $(seq 1 $width)
    printf "┘${RESET}\n\n"
}

# Print debug info
debug_info() {
    if [ "$DEBUG" = "true" ]; then
        echo "${BLUE}[DEBUG] Task: $TASK_NAME${RESET}" >&2
        echo "${BLUE}[DEBUG] Mode: $MODE${RESET}" >&2
        echo "${BLUE}[DEBUG] Command: $@${RESET}" >&2
        echo "${BLUE}[DEBUG] TTY(stdout): $IS_TTY${RESET}" >&2
        echo "${BLUE}[DEBUG] TTY: $([ -t 0 ] && [ -t 1 ] && echo "yes" || echo "no")${RESET}" >&2
        echo "" >&2
    fi
}

debug_print() {
    if [ "$DEBUG" = "true" ]; then
        echo "${BLUE}[DEBUG] $1${RESET}" >&2
    fi
}

# ================================================================
# Main execution modes
# ================================================================

# Quiet mode - minimal output with command on failure
run_quiet() {
    echo "${YELLOW}⏱️  Starting: $TASK_NAME${RESET}"
    local start=$(get_nano_time)
    local command_str="$*"
    
    if "$@"; then
        local end=$(get_nano_time)
        local duration=$(format_duration $((end - start)))
        echo "${GREEN}✅ Completed in $duration${RESET}"
        return 0
    else
        local exit_code=$?
        local end=$(get_nano_time)
        local duration=$(format_duration $((end - start)))
        echo "${RED}❌ Failed after $duration (exit code: $exit_code)${RESET}" >&2
        echo "${RED}Command: $command_str${RESET}" >&2
        return $exit_code
    fi
}

# Interactive mode - direct execution
run_interactive() {    
    debug_print "Running in interactive mode"
    local command_str="$*"
    draw_header
    local start=$(get_nano_time)
    
    eval "$@"
    local exit_code=$?
    
    local end=$(get_nano_time)
    local duration=$(format_duration $((end - start)))
    
    # 에러 시에만 커맨드 전달
    if [ $exit_code -ne 0 ]; then
        draw_footer $exit_code "$duration" "$command_str"
    else
        draw_footer $exit_code "$duration"
    fi
    return $exit_code
}

# Interactive + left/right borders while preserving TTY for child
run_interactive_bordered() {
    local command_str="$*"
    draw_header
    local start=$(get_nano_time)
    local exit_code=0

    left_print() {
        local cleaned
        cleaned=$(printf '%s' "$1" | perl -pe 's/\e\[[0-9;]*[A-HJKSTf]//g')

        # 완전 빈 줄은 그냥 테두리만
        if [ -z "$cleaned" ]; then
            printf "${YELLOW}│${RESET}\n"
        else
            printf "${YELLOW}│${RESET} %s\n" "$cleaned"
        fi
    }

    if command -v script >/dev/null 2>&1 && script -V 2>&1 | grep -qi 'util-linux'; then
        script -qefc "$*" /dev/null 2>&1 \
        | stdbuf -oL -eL tr '\r' '\n' \
        | while IFS= read -r line; do left_print "$line"; done
        exit_code=${PIPESTATUS[0]}
    elif command -v script >/dev/null 2>&1; then
        local tmp_status; tmp_status=$(mktemp)
        { script -q /dev/null bash -lc "$*" 2>&1; echo $? >"$tmp_status"; } \
        | stdbuf -oL -eL tr '\r' '\n' \
        | while IFS= read -r line; do left_print "$line"; done
        exit_code=$(cat "$tmp_status" 2>/dev/null || echo 1)
        rm -f "$tmp_status"
    else
        eval "$@"
        exit_code=$?
    fi

    local end=$(get_nano_time)
    local duration=$(format_duration $((end - start)))
    
    # 에러 시에만 커맨드 전달
    if [ $exit_code -ne 0 ]; then
        draw_footer $exit_code "$duration" "$command_str"
    else
        draw_footer $exit_code "$duration"
    fi
    return $exit_code
}

# Piped mode - formatted output with command on failure
run_piped() {
    debug_print "Running in piped mode"
    local command_str="$*"
    draw_header
    local start=$(get_nano_time)
    
    local temp_exit=$(mktemp)
    trap "rm -f $temp_exit" EXIT
    
    {
        eval "$@" 2>&1
        echo $? > $temp_exit
    } | while IFS= read -r line; do
        # Truncate long lines
        if [ ${#line} -gt 72 ]; then
            line="${line:0:69}..."
        fi
        printf "${YELLOW}│${RESET} %s\n" "$line"
    done
    
    local exit_code=$(cat $temp_exit 2>/dev/null || echo 1)
    rm -f $temp_exit
    
    local end=$(get_nano_time)
    local duration=$(format_duration $((end - start)))
    
    # 에러 시에만 커맨드 전달
    if [ $exit_code -ne 0 ]; then
        draw_footer $exit_code "$duration" "$command_str"
    else
        draw_footer $exit_code "$duration"
    fi
    return $exit_code
}

# ================================================================
# Main entry point
# ================================================================

main() {
    debug_info "$@"    
    
    # Determine execution mode    
    case "$MODE" in
        quiet)
            run_quiet "$@"
            ;;
        interactive)
            run_interactive "$@"
            ;;
        piped|pipe)
            run_piped "$@"
            ;;
        auto|*)
            if [ "$IS_TTY" = "yes" ]; then
                run_interactive "$@"
            else
                run_piped "$@"
            fi
            ;;
    esac
}

# Execute if not sourced
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi