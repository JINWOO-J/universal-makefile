#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SETUP="${REPO_ROOT}/setup.sh"
INSTALL="${REPO_ROOT}/install.sh"

: "${TMPDIR:=/tmp}"
TMPDIR="${TMPDIR%/}"
TMP_ROOT="$(mktemp -d "${TMPDIR}/umf-setup-test.XXXXXX")"
cleanup() { rm -rf "${TMP_ROOT}"; }
trap cleanup EXIT

pass=0; fail=0

red()   { printf "\033[0;31m%s\033[0m\n" "$*"; }
green() { printf "\033[0;32m%s\033[0m\n" "$*"; }
blue()  { printf "\033[0;34m%s\033[0m\n" "$*"; }

assert_file()     { [[ -f "$1" ]]; }
assert_dir()      { [[ -d "$1" ]]; }
assert_contains() { grep -qE "$2" "$1"; }

export -f assert_file assert_dir assert_contains || true

case_run() {
  local name="$1"; shift
  local cmd="$1"
  blue "==> $name"
  local dir="${TMP_ROOT}/${name// /_}"
  mkdir -p "$dir"; pushd "$dir" >/dev/null

  git init -q
  git config user.email test@example.com
  git config user.name test
  git commit --allow-empty -m init >/dev/null

  if eval "$cmd"; then
    green "✅ $name"; pass=$((pass+1))
  else
    red "❌ $name"; fail=$((fail+1))
  fi
  popd >/dev/null
}

# 1) 로컬 모드: install.sh 위임 + make help 실행까지 검증
#    exec 회피 위해 서브셸로 실행: ( "$SETUP" -- help )
case_run "local: delegate and make help" '
  cp "'"$INSTALL"'" ./install.sh &&
  ( FORCE_UPDATE=true "'"$SETUP"'" -- help ) &&
  assert_file "Makefile" &&
  assert_dir ".makefile-system" &&
  make help >/dev/null
'

# 2) 부트스트랩 모드: 기본 동작 (릴리스 있으면 릴리스, 없으면 브랜치 스냅샷)
case_run "bootstrap: default" '
  "'"$SETUP"'" &&
  assert_dir "universal-makefile" &&
  assert_file "universal-makefile/Makefile" &&
  assert_dir "universal-makefile/.makefile-system" &&
  make -C universal-makefile help >/dev/null
'

# 3) 부트스트랩 모드: -v master로 브랜치 스냅샷 강제
case_run "bootstrap: -v master" '
  "'"$SETUP"'" -v master &&
  assert_dir "universal-makefile" &&
  assert_file "universal-makefile/Makefile" &&
  assert_dir "universal-makefile/.makefile-system" &&
  make -C universal-makefile help >/dev/null
'

echo
echo "Passed: $pass  Failed: $fail"
exit $fail