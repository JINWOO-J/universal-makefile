# shellcheck shell=bash
# lib_errtrace.sh — precise DEBUG/ERR pairing for reliable bash error reports
# Bash 4.2+ compatible

# ---------- color (안전) ----------
if [[ -t 2 ]] && command -v tput >/dev/null 2>&1; then
  ERRTRACE_RED=$(tput setaf 1 || true)
  ERRTRACE_YEL=$(tput setaf 3 || true)
  ERRTRACE_RST=$(tput sgr0   || true)
else
  ERRTRACE_RED=""; ERRTRACE_YEL=""; ERRTRACE_RST=""
fi

# ---------- stacktrace ----------
errtrace::stacktrace() {
  # BASH_LINENO[i-1] = caller line of FUNCNAME[i]
  local i=1 depth=${#BASH_LINENO[@]}
  while (( i < depth )); do
    local line=${BASH_LINENO[i-1]}
    local func=${FUNCNAME[i]:-MAIN}
    local src=${BASH_SOURCE[i]:-n/a}
    printf '  at %s(%s:%s)\n' "$func" "${src##*/}" "$line" >&2
    ((i++))
  done
}

# ---------- precise DEBUG/ERR pairing ----------
# 실행 직전(DEBUG) 커맨드의 문맥을 저장 → ERR에서 그대로 사용
# Bash 4.2 호환 전역 저장소
__ERRTRACE_CMD=""
__ERRTRACE_SRC=""
__ERRTRACE_LINE=0

errtrace::__debug_capture() {
  # DEBUG는 커맨드 실행 '직전' 호출 → 이 시점의 정보가 가장 정확
  __ERRTRACE_CMD=${BASH_COMMAND}
  __ERRTRACE_SRC=${BASH_SOURCE[0]:-n/a}
  __ERRTRACE_LINE=${LINENO}
}

# ---------- on_error (ERR trap 핸들러) ----------
errtrace::_on_error() {
  # trap 의 기본 $?를 그대로 사용
  local code=$?
  # 핸들러 내부는 실패해도 죽지 않게
  set +e

  # 파이프라인 실패 상세 (있으면)
  local pipe=""
  if [[ -n ${PIPESTATUS[*]-} ]]; then
    pipe=" | PIPESTATUS=(${PIPESTATUS[*]})"
  fi

  # DEBUG에서 캡처한 정보가 있으면 우선 사용
  local src="${__ERRTRACE_SRC:-${BASH_SOURCE[1]:-n/a}}"
  local line="${__ERRTRACE_LINE:-${BASH_LINENO[0]:-0}}"
  local cmd="${__ERRTRACE_CMD:-${BASH_COMMAND}}"

  echo -e "${ERRTRACE_RED}✖ exit ${code}${ERRTRACE_RST}${pipe}" >&2
  echo -e "${ERRTRACE_YEL}↳ at ${src}:${line}${ERRTRACE_RST}" >&2
  echo -e "${ERRTRACE_YEL}↳ cmd:${ERRTRACE_RST} ${cmd}" >&2
  errtrace::stacktrace

  # set -e 가 있으면 호출자에서 종료됨. 여기서는 반환만.
  return "$code"
}

# ---------- enable/disable ----------
errtrace::enable() {
  # 함수/서브셸까지 ERR/DEBUG 전파
  set -E -o errtrace
  set -o functrace

  # 중복 설치 방지
  [[ "${ERRTRACE_INSTALLED:-}" == "1" ]] && return 0

  # 실행 직전 항상 문맥 저장
  trap 'errtrace::__debug_capture' DEBUG
  # 실패 시 에러 출력
  trap 'errtrace::_on_error' ERR

  ERRTRACE_INSTALLED=1
}

errtrace::disable() {
  trap - DEBUG
  trap - ERR
  unset ERRTRACE_INSTALLED
}

errtrace::guard() {
  # 사용법: errtrace::guard some_command arg1 arg2...
  # 실패하면 반드시 ERR 핸들러를 태우고 원코드로 반환
  "$@"
  local rc=$?
  if (( rc != 0 )); then
    # DEBUG에서 직전 커맨드가 캡처되도록 한 번 찍어주고
    errtrace::__debug_capture
    errtrace::_on_error  # 표준 핸들러 호출
    return "$rc"
  fi
}


# ---------- xtrace (디버그 -x) ----------
xtrace::enable() {
  # 사용법: xtrace::enable [logfile]
  local log=${1:-${UMS_XTRACE_LOG:-.ums-xtrace.log}}

  # 보기 좋은 프롬프트(시간/파일/라인/함수)
  # shellcheck disable=SC2016
  export PS4='+ $(date "+%H:%M:%S") ${BASH_SOURCE##*/}:${LINENO}:${FUNCNAME[0]:-MAIN}: '

  # Bash 4+ : BASH_XTRACEFD 사용
  if [[ -n ${BASH_VERSINFO[0]+x} && ${BASH_VERSINFO[0]} -ge 4 ]]; then
    # 독립 FD를 열어 xtrace 를 파일로 보냄
    exec {__xtrace_fd}>>"$log"
    export BASH_XTRACEFD=${__xtrace_fd}
  else
    # Bash 3.x 폴백: stderr 전체를 tee
    exec 2> >(tee -a "$log" >&2)
  fi

  set -x
  export XTRACE_LOG="$log"
}

xtrace::disable() {
  set +x
  # Bash 4+: 열린 FD 닫기
  if [[ -n ${BASH_XTRACEFD:-} && ${BASH_XTRACEFD} != 2 ]]; then
    # shellcheck disable=SC2091
    eval "exec ${BASH_XTRACEFD}>&-"
    unset BASH_XTRACEFD
  fi
}
