#!/usr/bin/env bash
set -euo pipefail
set -E -o errtrace

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

DEBUG="${DEBUG:-false}"
for __arg in "$@"; do
  case "$__arg" in --debug|-d) DEBUG=true ;; esac
done

ERRTRACE_LIB="${SCRIPT_DIR}/scripts/lib_errtrace.sh"
if [[ -f "$ERRTRACE_LIB" ]]; then
  # shellcheck disable=SC1091
  . "$ERRTRACE_LIB"
  errtrace::enable

  if [[ "$DEBUG" == "true" ]]; then
    : "${UMS_XTRACE_LOG:=.ums-xtrace.log}"
    xtrace::enable "$UMS_XTRACE_LOG"
  fi
else
  if [[ -t 2 ]] && command -v tput >/dev/null 2>&1; then
    RED=$(tput setaf 1 || true); YEL=$(tput setaf 3 || true); RST=$(tput sgr0 || true)
  else
    RED=""; YEL=""; RST=""
  fi

  _stacktrace() {
    local i=1 depth=${#BASH_LINENO[@]}
    while (( i < depth )); do
      local line=${BASH_LINENO[i-1]}
      local func=${FUNCNAME[i]:-MAIN}
      local src=${BASH_SOURCE[i]:-n/a}
      printf '  at %s(%s:%s)\n' "$func" "${src##*/}" "$line" >&2
      ((i++))
    done
  }
  _on_error(){ local code=$?; local cmd=$BASH_COMMAND; set +e
    echo -e "${RED}✖ exit ${code}${RST}" >&2
    echo -e "${YEL}↳ cmd:${RST} ${cmd}" >&2
    _stacktrace
  }
  trap '_on_error; exit $?' ERR

  if [[ "$DEBUG" == "true" ]]; then
    export PS4='+ $(date "+%H:%M:%S") ${BASH_SOURCE##*/}:${LINENO}:${FUNCNAME[0]:-MAIN}: '
    : "${UMS_XTRACE_LOG:=.ums-xtrace.log}"
    if [[ -n ${BASH_VERSINFO:-} && ${BASH_VERSINFO[0]} -ge 4 ]]; then
      # bash 4+: BASH_XTRACEFD 지원
      exec {__xtrace_fd}>>"${UMS_XTRACE_LOG}"
      export BASH_XTRACEFD=${__xtrace_fd}
    else
      exec 2> >(tee -a "${UMS_XTRACE_LOG}" >&2)
    fi
    set -x
    echo "[debug] xtrace enabled → ${UMS_XTRACE_LOG}" >&2
  fi
fi

if [[ -f "${SCRIPT_DIR}/scripts/lib_installer.sh" ]]; then
  # shellcheck disable=SC1091
  . "${SCRIPT_DIR}/scripts/lib_installer.sh"
else
  echo "scripts/lib_installer.sh not found. Aborting." >&2
  exit 1
fi

umf_install_main "$@"
