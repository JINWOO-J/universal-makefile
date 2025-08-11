# scripts/test-install.sh
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SCRIPT="${REPO_ROOT}/install.sh"

: "${TMPDIR:=/tmp}"
TMPDIR="${TMPDIR%/}"
TMP_ROOT="$(mktemp -d "${TMPDIR}/umf-test.XXXXXX")"
cleanup() { rm -rf "${TMP_ROOT}"; }
trap cleanup EXIT

pass=0; fail=0

red()   { printf "\033[0;31m%s\033[0m\n" "$*"; }
green() { printf "\033[0;32m%s\033[0m\n" "$*"; }
blue()  { printf "\033[0;34m%s\033[0m\n" "$*"; }

assert_file()     { [[ -f "$1" ]]; }
assert_dir()      { [[ -d "$1" ]]; }
assert_contains() { grep -qE "$2" "$1"; }

# 필요 시 하위 셸에서도 쓰이도록 export (eval 사용 시 필수는 아님)
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

  # bash -c 중첩로 인한 "option requires an argument" 방지: eval로 현재 셸에서 실행
  if eval "$cmd"; then
    green "✅ $name"; pass=$((pass+1))
  else
    red "❌ $name"; fail=$((fail+1))
  fi
  popd >/dev/null
}

# 1) subtree install
case_run "subtree install" '
  "'"$SCRIPT"'" install --subtree -y &&
  assert_dir ".makefile-system" &&
  assert_file "Makefile.universal" &&
  assert_file "Makefile" &&
  assert_file "project.mk" &&
  make help >/dev/null
'

# 2) submodule install
case_run "submodule install" '
  "'"$SCRIPT"'" install --submodule -y &&
  assert_file ".gitmodules" &&
  assert_contains ".gitmodules" "path = .makefile-system"
'

# 3) copy install
case_run "copy install" '
  "'"$SCRIPT"'" install --copy -y &&
  assert_dir "makefiles" &&
  ! [[ -d ".makefile-system" ]]
'

# 4) release latest (falls back to branch if no releases)
case_run "release latest" '
  "'"$SCRIPT"'" install --release -y &&
  assert_dir ".makefile-system"
'

# 5) install with prefix
case_run "prefix install" '
  "'"$SCRIPT"'" install --subtree --prefix vendor/umf -y &&
  assert_dir "vendor/umf" &&
  assert_contains "Makefile" "MAKEFILE_SYSTEM_DIR := vendor/umf"
'

# 6) uninstall dry-run (should not remove files)
case_run "uninstall dry-run" '
  "'"$SCRIPT"'" install --subtree -y &&
  "'"$SCRIPT"'" uninstall --dry-run &&
  assert_dir ".makefile-system"
'

echo
echo "Passed: $pass  Failed: $fail"
exit $fail
