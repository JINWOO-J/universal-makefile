#!/usr/bin/env bash
# scripts/lib_release.sh
# Shared utility functions for release download/extract logic and common helpers.
# Safe to source from any shell script. Does not exit on errors; returns status codes instead.

# ---- Bash 4.2 호환 보강: readarray가 없으면 mapfile로 폴백 ----
if ! declare -F readarray >/dev/null 2>&1 && declare -F mapfile >/dev/null 2>&1; then
  readarray() { mapfile "$@"; }
fi

# ----- Boolean helper -----
umr_is_true() { case "${1:-}" in true|1|yes|on|Y|y) return 0;; *) return 1;; esac; }

# ----- Interactive confirm (no-op false in non-interactive) -----
umr_prompt_confirm() {
  # usage: umr_prompt_confirm "Question?"
  local msg="$1" reply
  if [ -t 0 ]; then
    read -r -p "${msg} [y/N]: " reply || true
    case "$reply" in
      [yY][eE][sS]|[yY]) return 0 ;;
      *) return 1 ;;
    esac
  else
    return 1
  fi
}

# ----- Retry/backoff defaults (can be overridden via env) -----
: "${CURL_RETRY_MAX:=3}"
: "${CURL_RETRY_DELAY_SEC:=2}"

# ----- Verify SHA256 of a file -----
umr_verify_sha256() {
  local file_path="$1" expected="$2"
  if [[ -z "$expected" ]]; then
    return 2
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    echo "${expected}  ${file_path}" | sha256sum -c --status
    return $?
  elif command -v shasum >/dev/null 2>&1; then
    echo "${expected}  ${file_path}" | shasum -a 256 -c --status
    return $?
  else
    return 3
  fi
}

# ----- Fetch latest GitHub release tag (API → git ls-remote fallback) -----
umr_fetch_latest_release_tag() {
  # usage: umr_fetch_latest_release_tag OWNER REPO
  local owner="$1" repo="$2"
  local api_url="https://api.github.com/repos/${owner}/${repo}/releases/latest"
  local tag=""
  local -a auth_args=()
  [[ -n "${GITHUB_TOKEN:-}" ]] && auth_args=(-H "Authorization: Bearer ${GITHUB_TOKEN}")

  if command -v curl >/dev/null 2>&1; then
    tag=$(
      curl -fsSL \
        ${auth_args[@]+"${auth_args[@]}"} \
        "$api_url" \
      | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
      | head -n1 || true
    )
  elif command -v wget >/dev/null 2>&1; then
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
      tag=$(wget -qO- --header="Authorization: Bearer ${GITHUB_TOKEN}" "$api_url" \
            | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
            | head -n1 || true)
    else
      tag=$(wget -qO- "$api_url" \
            | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
            | head -n1 || true)
    fi
  fi

  if [[ -n "$tag" ]]; then
    echo "$tag"; return 0
  fi

  if command -v git >/dev/null 2>&1; then
    tag=$(git ls-remote --tags --refs "https://github.com/${owner}/${repo}.git" 2>/dev/null \
      | awk '{print $2}' | sed 's@refs/tags/@@' | sort -Vr | head -n1)
    if [[ -n "$tag" ]]; then
      echo "$tag"; return 0
    fi
  fi
  return 1
}

# ----- Build primary/mirror tarball URLs for given ref -----
umr_build_tarball_urls() {
  # usage: umr_build_tarball_urls OWNER REPO REF
  # prints two lines: primary_url\nmirror_url
  local owner="$1" repo="$2" ref="$3"
  local primary="" mirror=""
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    primary="https://api.github.com/repos/${owner}/${repo}/tarball/${ref}"
    case "$ref" in
      main|master|develop|*-branch|*-snapshot)
        mirror="https://codeload.github.com/${owner}/${repo}/tar.gz/refs/heads/${ref}"
        ;;
      *)
        mirror="https://codeload.github.com/${owner}/${repo}/tar.gz/refs/tags/${ref}"
        ;;
    esac
  else
    case "$ref" in
      main|master|develop|*-branch|*-snapshot)
        primary="https://github.com/${owner}/${repo}/archive/refs/heads/${ref}.tar.gz"
        mirror="https://codeload.github.com/${owner}/${repo}/tar.gz/refs/heads/${ref}"
        ;;
      *)
        primary="https://github.com/${owner}/${repo}/archive/refs/tags/${ref}.tar.gz"
        mirror="https://codeload.github.com/${owner}/${repo}/tar.gz/refs/tags/${ref}"
        ;;
    esac
  fi
  echo "$primary"
  echo "$mirror"
}

# ----- Download a URL with retries -----
umr_download_with_retries() {
  # usage: umr_download_with_retries URL OUT_FILE [HEADER1] [HEADER2] ...
  local url="$1" out="$2"; shift 2

  # 헤더를 먼저 배열로 수집
  local -a curl_headers=()
  local h
  for h in "$@"; do
    # 빈 문자열이 섞이지 않게 필터
    [[ -n "$h" ]] && curl_headers+=( -H "$h" )
  done

  local attempt=1
  while [[ $attempt -le ${CURL_RETRY_MAX} ]]; do
    if command -v curl >/dev/null 2>&1; then
      # ←← 여기: 한 줄 커맨드 대신 배열을 조립해서 실행
      local -a cmd=( curl -fSL --connect-timeout 10 --max-time 300 )
      if ((${#curl_headers[@]})); then
        cmd+=("${curl_headers[@]}")
      fi
      cmd+=( -o "$out" "$url" )

      # xtrace 감춤/복원
      local _had_xtrace=0; case "$-" in *x*) _had_xtrace=1; set +x ;; esac
      if "${cmd[@]}"; then
        ((_had_xtrace)) && set -x
        [[ -s "$out" ]] && return 0
      fi
      ((_had_xtrace)) && set -x

    elif command -v wget >/dev/null 2>&1; then
      local -a wget_hdr=()
      for h in "$@"; do [[ -n "$h" ]] && wget_hdr+=( --header "$h" ); done
      local -a wcmd=( wget -q -O "$out" )
      ((${#wget_hdr[@]:-0})) && wcmd+=( "${wget_hdr[@]}" )
      wcmd+=( "$url" )
      if "${wcmd[@]}"; then
        [[ -s "$out" ]] && return 0
      fi

    else
      return 127
    fi

    sleep $((CURL_RETRY_DELAY_SEC * (2 ** (attempt - 1)))) || sleep "${CURL_RETRY_DELAY_SEC}"
    attempt=$((attempt + 1))
  done
  return 1
}


# ----- High-level tarball download (select URLs and apply auth) -----
umr_download_tarball() {
  # usage: umr_download_tarball OWNER REPO REF OUT_TAR
  local owner="$1" repo="$2" ref="$3" out_tar="$4"

  # Build URLs (two lines: primary, mirror)
  local primary mirror
  read -r primary < <(umr_build_tarball_urls "$owner" "$repo" "$ref")
  read -r mirror  < <(umr_build_tarball_urls "$owner" "$repo" "$ref" | sed -n '2p')

  # Optional auth headers (array is always initialized → safe with `set -u`)
  local -a headers=()
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    headers+=("Authorization: Bearer ${GITHUB_TOKEN}")
    headers+=("Accept: application/vnd.github+json")
    headers+=("X-GitHub-Api-Version: 2022-11-28")
  fi

  # Try primary then mirror. Bash 4.2-safe length check (no :- default).
  if ((${#headers[@]})); then
    if umr_download_with_retries "$primary" "$out_tar" "${headers[@]}"; then
      [[ -s "$out_tar" ]] && return 0
    fi
    if [[ -n "$mirror" ]] && umr_download_with_retries "$mirror" "$out_tar" "${headers[@]}"; then
      [[ -s "$out_tar" ]] && return 0
    fi
  else
    if umr_download_with_retries "$primary" "$out_tar"; then
      [[ -s "$out_tar" ]] && return 0
    fi
    if [[ -n "$mirror" ]] && umr_download_with_retries "$mirror" "$out_tar"; then
      [[ -s "$out_tar" ]] && return 0
    fi
  fi

  return 1
}


# ----- Validate tar.gz and get first top directory name -----
umr_tar_first_dir() {
  # usage: umr_tar_first_dir TAR_PATH
  local tarfile="$1"
  if ! tar -tzf "$tarfile" >/dev/null 2>&1; then
    return 2
  fi
  local first
  first=$(tar -tzf "$tarfile" 2>/dev/null | head -n1 | cut -d/ -f1 || true)
  [[ -n "$first" ]] || return 3
  echo "$first"
  return 0
}

# ----- Extract tar.gz to target directory and echo top dir path -----
umr_extract_tarball() {
  # usage: umr_extract_tarball TAR_PATH DEST_DIR
  local tarfile="$1" dest="$2"
  mkdir -p "$dest"
  if ! tar -xzf "$tarfile" -C "$dest" 2>/dev/null; then
    return 1
  fi
  return 0
}
