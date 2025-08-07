#!/bin/bash
set -e
MAKEFILE_SYSTEM_CHECK_FILE=".makefile-system/Makefile.universal"
if [ ! -f "${MAKEFILE_SYSTEM_CHECK_FILE}" ]; then
    echo "⚠️  Makefile system not found. Initializing submodule..."
    git submodule update --init --recursive
fi
exec make "$@"