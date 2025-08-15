# shellcheck shell=bash

# ---------- color (안전) ----------
if [[ -t 2 ]] && command -v tput >/dev/null 2>&1; then
  ERRTRACE_RED=$(tput setaf 1 || true)
  ERRTRACE_YEL=$(tput setaf 3 || true)
  ERRTRACE_RST=$(tput sgr0 || true)
else
  ERRTRACE_RED=""; ERRTRACE_YEL=""; ERRTRACE_RST=""
fi

# ---------- stacktrace ----------
errtrace::stacktrace() {
  local i=1 depth=${#BASH_LINENO[@]}
  while (( i < depth )); do
    local line=${BASH_LINENO[i-1]}
    local func=${FUNCNAME[i]:-MAIN}
    local src=${BASH_SOURCE[i]:-n/a}
    printf '  at %s(%s:%s)\n' "$func" "${src##*/}" "$line" >&2
    ((i++))
  done
}

# ---------- on_error (ERR trap 핸들러) ----------
errtrace::_on_error() {
  local code=$1
  local cmd=${BASH_COMMAND}
  # 파이프라인 실패 상세 (옵션)
  local pipe=""; [[ -n ${PIPESTATUS[*]-} ]] && pipe=" | PIPESTATUS=(${PIPESTATUS[*]})"
  # 핸들러 내부는 실패해도 죽지 않게
  set +e
  echo -e "${ERRTRACE_RED}✖ exit ${code}${ERRTRACE_RST}${pipe}" >&2
  echo -e "${ERRTRACE_YEL}↳ cmd:${ERRTRACE_RST} ${cmd}" >&2
  errtrace::stacktrace
}

# ---------- enable/disable ----------
errtrace::enable() {
  # 함수/서브셸까지 ERR 전파
  set -E -o errtrace
  # 중복 설치 방지
  [[ "${ERRTRACE_INSTALLED:-}" == "1" ]] && return 0
  trap 'errtrace::_on_error $?; exit $?' ERR
  ERRTRACE_INSTALLED=1
}

errtrace::disable() {
  trap - ERR
  unset ERRTRACE_INSTALLED
}

# ---------- xtrace (디버그 -x) ----------
xtrace::enable() {
  # 사용법: xtrace::enable [logfile]
  local log=${1:-${UMS_XTRACE_LOG:-.ums-xtrace.log}}
  # 보기 좋은 프롬프트(시간/파일/라인/함수)
  export PS4='+ $(date "+%H:%M:%S") ${BASH_SOURCE##*/}:${LINENO}:${FUNCNAME[0]:-MAIN}: '

  # bash 4+면 BASH_XTRACEFD 사용, 3.x(맥 기본)면 stderr를 tee로 복제
  if [[ -n ${BASH_VERSINFO:-} && ${BASH_VERSINFO[0]} -ge 4 ]]; then
    exec {__xtrace_fd}>>"$log"
    export BASH_XTRACEFD=${__xtrace_fd}
  else
    # 주의: bash 3.x 에서는 stderr 전체가 파일에도 기록됩니다.
    exec 2> >(tee -a "$log" >&2)
  fi
  set -x
  export XTRACE_LOG="$log"
}

xtrace::disable() {
  set +x
  # bash 4+: 열린 FD 닫기
  if [[ -n ${BASH_XTRACEFD:-} && ${BASH_XTRACEFD} != 2 ]]; then
    eval "exec ${BASH_XTRACEFD}>&-"
    unset BASH_XTRACEFD
  fi
}
