#!/usr/bin/env bash
set -euo pipefail
set -E -o errtrace  # ERR trap 전파

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# shellcheck disable=SC1091
. "${SCRIPT_DIR}/scripts/lib_errtrace.sh"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/scripts/lib_installer.sh"

DEBUG="${DEBUG:-false}"
for __arg in "$@"; do
  case "$__arg" in --debug|-d) DEBUG=true ;; esac
done

errtrace::enable

if [[ "$DEBUG" == "true" ]]; then
  : "${UMS_XTRACE_LOG:=.ums-xtrace.log}"
  xtrace::enable "$UMS_XTRACE_LOG"
fi

umf_install_main "$@"
