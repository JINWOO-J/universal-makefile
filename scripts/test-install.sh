#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SCRIPT="${REPO_ROOT}/install.sh"

TMP_ROOT="$(mktemp -d)"
pass=0; fail=0

red() { printf "\033[0;31m%s\033[0m\n" "$*"; }
green() { printf "\033[0;32m%s\033[0m\n" "$*"; }
blue() { printf "\033[0;34m%s\033[0m\n" "$*"; }

assert_file() { [[ -f "$1" ]]; }
assert_dir() { [[ -d "$1" ]]; }
assert_contains() { grep -qE "$2" "$1"; }

export -f assert_file
export -f assert_dir
export -f assert_contains


case_run() {
  local name="$1"; shift
  blue "==> $name"
  local dir="${TMP_ROOT}/${name// /_}"
  mkdir -p "$dir"; pushd "$dir" >/dev/null

  git init -q
  git config user.email test@example.com
  git config user.name test
  git commit --allow-empty -m init >/dev/null

  if bash -c "$*"; then
    green "✅ $name"; pass=$((pass+1))
  else
    red "❌ $name"; fail=$((fail+1))
  fi
  popd >/dev/null
}


# 1) subtree install
case_run "subtree install" bash -c '
  "'"$SCRIPT"'" install --subtree -y &&
  assert_dir ".makefile-system" &&
  assert_file "Makefile.universal" &&
  assert_file "Makefile" &&
  assert_file "project.mk" &&
  make help >/dev/null
'

# 2) submodule install
case_run "submodule install" bash -c '
  "'"$SCRIPT"'" install --submodule -y &&
  assert_file ".gitmodules" &&
  assert_contains ".gitmodules" "path = .makefile-system"
'

# 3) copy install
case_run "copy install" bash -c '
  "'"$SCRIPT"'" install --copy -y &&
  assert_dir "makefiles" &&
  ! [[ -d ".makefile-system" ]]
'

# 4) release latest (falls back to branch if no releases)
case_run "release latest" bash -c '
  "'"$SCRIPT"'" install --release -y &&
  assert_dir ".makefile-system"
'

# 5) install with prefix
case_run "prefix install" bash -c '
  "'"$SCRIPT"'" install --subtree --prefix vendor/umf -y &&
  assert_dir "vendor/umf" &&
  assert_contains "Makefile" "MAKEFILE_SYSTEM_DIR := vendor/umf"
'

# 6) uninstall dry-run (should not remove files)
case_run "uninstall dry-run" bash -c '
  "'"$SCRIPT"'" install --subtree -y &&
  "'"$SCRIPT"'" uninstall --dry-run &&
  assert_dir ".makefile-system"
'

echo ""
echo "Passed: $pass  Failed: $fail"
exit $fail


