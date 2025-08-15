#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [[ -f "${SCRIPT_DIR}/scripts/lib_installer.sh" ]]; then
  # shellcheck disable=SC1091
  . "${SCRIPT_DIR}/scripts/lib_installer.sh"
else
  echo "scripts/lib_installer.sh not found. Aborting." >&2
        exit 1
    fi

umf_install_main "$@"


