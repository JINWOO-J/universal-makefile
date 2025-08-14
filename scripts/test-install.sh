# scripts/test-install.sh
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}" )" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SCRIPT="${REPO_ROOT}/install.sh"
SETUP="${REPO_ROOT}/setup.sh"

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

# Helper: fetch latest release tag for this repo (token-aware)
get_latest_release_tag() {
	local owner="jinwoo-j" repo="universal-makefile"
	local api_url="https://api.github.com/repos/${owner}/${repo}/releases/latest"
	if command -v curl >/dev/null 2>&1; then
		local auth=()
		if [[ -n "${GITHUB_TOKEN:-}" ]]; then
			# GitHub API v3 prefers "token" prefix for auth header
			auth+=( -H "Authorization: token ${GITHUB_TOKEN}" )
		fi
		curl -fsSL "${auth[@]}" "$api_url" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1
	else
		git ls-remote --tags --refs "https://github.com/${owner}/${repo}.git" 2>/dev/null | awk '{print $2}' | sed 's@refs/tags/@@' | sort -Vr | head -n1
	fi
}

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

# Git 리포 없이 실행하는 케이스 (setup.sh 부트스트랩 모드 검증용)
case_run_no_git() {
  local name="$1"; shift
  local cmd="$1"
  blue "==> $name"
  local dir="${TMP_ROOT}/${name// /_}"
  mkdir -p "$dir"; pushd "$dir" >/dev/null

  if eval "$cmd"; then
    green "✅ $name"; pass=$((pass+1))
  else
    red "❌ $name"; fail=$((fail+1))
  fi
  popd >/dev/null
}

# 1) subtree install
case_run "subtree install" '
  '"$SCRIPT"' install --subtree -y &&
  assert_dir "universal-makefile" &&
  assert_contains "Makefile" "MAKEFILE_SYSTEM_DIR := universal-makefile" &&
  assert_file "Makefile.universal" &&
  assert_file "Makefile" &&
  assert_file "project.mk" &&
  make help >/dev/null
'

# 2) submodule install
case_run "submodule install" '
  '"$SCRIPT"' install --submodule -y &&
  assert_file ".gitmodules" &&
  assert_contains ".gitmodules" "path = universal-makefile"
'

# 3) copy install
case_run "copy install" '
  '"$SCRIPT"' install --copy -y &&
  assert_dir "makefiles" &&
  ! [[ -d ".makefile-system" ]]
'

# 4) release latest (falls back to branch if no releases)
case_run "release latest" '
  '"$SCRIPT"' install --release -y
'

# 5) install with prefix
case_run "prefix install" '
  '"$SCRIPT"' install --subtree --prefix vendor/umf -y &&
  assert_dir "vendor/umf" &&
  assert_contains "Makefile" "MAKEFILE_SYSTEM_DIR := vendor/umf"
'

# 6) uninstall dry-run (should not remove files)
case_run "uninstall dry-run" '
  '"$SCRIPT"' install --subtree -y &&
  '"$SCRIPT"' uninstall --dry-run &&
  assert_dir "universal-makefile"
'

## setup.sh tests

# 7) setup local: delegate and make help
case_run "setup local: delegate and make help" '
  cp '"$SCRIPT"' ./install.sh &&
  cp -r '"$REPO_ROOT"'/scripts ./scripts &&
  ( FORCE_UPDATE=true '"$SETUP"' -- help ) &&
  ./install.sh init -y &&
  assert_file "Makefile" &&
  assert_dir "universal-makefile" &&
  make help >/dev/null
'

# 8) setup bootstrap: default
case_run_no_git "setup bootstrap: default" '
  '"$SETUP"' &&
  assert_dir "universal-makefile" &&
  assert_file "universal-makefile/Makefile" &&
  assert_dir "universal-makefile/makefiles" &&
  make -C universal-makefile help >/dev/null
'

# 9) setup bootstrap: -v master
case_run_no_git "setup bootstrap: -v master" '
  '"$SETUP"' -v master &&
  assert_dir "universal-makefile" &&
  assert_file "universal-makefile/Makefile" &&
  assert_dir "universal-makefile/makefiles" &&
  make -C universal-makefile help >/dev/null
'

# 10.5) setup bootstrap + update --force to latest (release install)
case_run_no_git "setup bootstrap + update --force to latest" '
	'"$SETUP"' &&
	assert_dir "universal-makefile" &&
	echo "v0.0.0" > .ums-version &&  # deliberately stale pin
	LATEST_TAG="$(get_latest_release_tag)" && [[ -n "$LATEST_TAG" ]] &&
	./universal-makefile/install.sh update --force >/dev/null &&
	assert_contains .ums-release-version "$LATEST_TAG" &&
	assert_contains .ums-version "$LATEST_TAG"
'

# 10) init debug logs
case_run "init debug logs" '
  cp '"$SCRIPT"' ./install.sh &&
  cp -r '"$REPO_ROOT"'/scripts ./scripts &&
  ./install.sh init --debug -y > out.txt 2>&1 &&
  assert_contains out.txt "\\[scaffold\\]\\[debug\\] begin"
'

# 11) scaffold-only install
case_run "scaffold-only install" '
  cp '"$SCRIPT"' ./install.sh &&
  cp -r '"$REPO_ROOT"'/scripts ./scripts &&
  ./install.sh install --scaffold-only -y &&
  assert_file "Makefile" &&
  assert_file "Makefile.universal" &&
  assert_file "project.mk"
'

# 12) status and check on subtree
case_run "status and check on subtree" '
  '"$SCRIPT"' install --subtree -y &&
  '"$SCRIPT"' status > status.txt 2>&1 &&
  '"$SCRIPT"' check
'

# 13) update on copy install
case_run "update on copy install" '
  '"$SCRIPT"' install --copy -y &&
  '"$SCRIPT"' update -y
'

# 14) uninstall backup creates backup dir
case_run "uninstall backup" '
  '"$SCRIPT"' install --subtree -y &&
  '"$SCRIPT"' uninstall --backup -y &&
  ls -d .backup_universal_makefile_* >/dev/null 2>&1
'

# 14.5) uninstall removes marked docker-compose.dev.yml
case_run "uninstall removes marked compose dev file" '
	'"$SCRIPT"' install --subtree -y &&
	echo "# === Created by Universal Makefile System Installer ===" > docker-compose.dev.yml &&
	'"$SCRIPT"' uninstall -y &&
	! [[ -f docker-compose.dev.yml ]]
'

# 15) app setup non-interactive
case_run "app setup non-interactive" '
  '"$SCRIPT"' install --subtree -y &&
  '"$SCRIPT"' app -y &&
  assert_file "app/index.html"
'

# 16) prefix + scaffold-only
case_run "prefix + scaffold-only" '
  cp '"$SCRIPT"' ./install.sh &&
  cp -r '"$REPO_ROOT"'/scripts ./scripts &&
  ./install.sh install --scaffold-only --subtree --prefix vendor/umf -y &&
  assert_contains "Makefile" "MAKEFILE_SYSTEM_DIR := vendor/umf"
'

# 17) submodule uninstall --force
case_run "submodule uninstall --force" '
  '"$SCRIPT"' install --submodule -y &&
  '"$SCRIPT"' uninstall --force -y &&
  ! [[ -d "universal-makefile" ]] &&
  ( ! [[ -f .gitmodules ]] || ! grep -q "path = universal-makefile" .gitmodules )
'

# 18) init idempotency (second run makes no changes)
case_run "init idempotency" '
  cp '"$SCRIPT"' ./install.sh &&
  cp -r '"$REPO_ROOT"'/scripts ./scripts &&
  ./install.sh init -y &&
  cp Makefile Makefile.bak && cp Makefile.universal Makefile.universal.bak && cp project.mk project.mk.bak &&
  ./install.sh init -y &&
  cmp -s Makefile Makefile.bak &&
  cmp -s Makefile.universal Makefile.universal.bak &&
  cmp -s project.mk project.mk.bak
'

# 19) release install with GITHUB_TOKEN (fallback to unauthenticated if 401)
case_run "release with GITHUB_TOKEN" '
  # 토큰 디버깅 정보 출력
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    # 토큰 첫 4자만 로그로 출력 (보안)
    echo "Using token: ${GITHUB_TOKEN:0:4}..." >&2
    
    # 토큰 권한 테스트 (HTTP 상태 코드 확인)
    local status=$(curl -s -o /dev/null -w "%{http_code}" \
      -H "Authorization: token ${GITHUB_TOKEN}" \
      "https://api.github.com/repos/jinwoo-j/universal-makefile")
    echo "API access status: $status" >&2
    
    # 토큰으로 릴리스 설치 시도
    '"$SCRIPT"' install --release -y
  else
    # 토큰 없으면 비인증 설치 시도
    echo "No GITHUB_TOKEN set, using unauthenticated access" >&2
    '"$SCRIPT"' install --release -y
  fi &&
  assert_dir "universal-makefile"
'

echo
echo "Passed: $pass  Failed: $fail"
exit $fail
