#!/usr/bin/env bash
set -Eeuo pipefail

# registry-list-tags.sh (auto public/private + color + last-updated)
# ------------------------------------------------------------------
# Required:
#   REPO_HUB : mycompany | ghcr.io/mycompany | 123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/myteam
#   NAME     : image name (e.g., app)
#
# Optional:
#   PRIVATE     : 0=force no-auth, 1=force auth, (unset=auto)  ← 권장: unset
#   PAGE_SIZE   : Docker Hub REST page size (default 100)
#   AUTHFILE    : docker config (default ~/.docker/config.json)
#   CONT_AUTH   : containers auth.json (default ~/.config/containers/auth.json)
#   REG_USER    : generic registry user/token (GHCR/ECR)
#   REG_PASS    : generic registry password/token
#   DOCKER_USERNAME / DOCKER_PASSWORD : Docker Hub JWT fallback
#   FETCH_META  : 1 → non-Hub도 skopeo inspect로 생성일 수집(느릴 수 있음)
#   MAX_TAGS    : FETCH_META=1일 때 최대 조회 태그 수 (default 200)
#   DEBUG       : 1 → set -x
#
# Output:
#   Colored table (TAG, LAST UPDATED if available). No color if not TTY.

[[ "${DEBUG:-0}" == "1" ]] && set -x

REPO_HUB="${REPO_HUB:-}"
NAME="${NAME:-}"
PRIVATE="${PRIVATE:-}"    # auto by default
PAGE_SIZE="${PAGE_SIZE:-100}"
AUTHFILE="${AUTHFILE:-$HOME/.docker/config.json}"
CONT_AUTH="${CONT_AUTH:-$HOME/.config/containers/auth.json}"
FETCH_META="${FETCH_META:-0}"
MAX_TAGS="${MAX_TAGS:-200}"

if [[ -z "$REPO_HUB" || -z "$NAME" ]]; then
  echo "❌ REPO_HUB와 NAME을 지정하세요. 예) REPO_HUB=mycompany NAME=app" >&2
  exit 1
fi

# colors
if [[ -t 1 ]]; then
  BOLD=$'\e[1m'; DIM=$'\e[2m'; RESET=$'\e[0m'
  CYAN=$'\e[36m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'
else
  BOLD=""; DIM=""; RESET=""; CYAN=""; GREEN=""; YELLOW=""
fi

need() { command -v "$1" >/dev/null 2>&1 || { echo "❌ '$1' 필요합니다." >&2; exit 2; }; }

# parse repo
HUB="$REPO_HUB"; IMG="$NAME"
if [[ "$HUB" == *.*/* ]]; then
  HOST="${HUB%%/*}"; NS="${HUB#*/}"
elif [[ "$HUB" == *.* ]]; then
  HOST="$HUB"; NS=""
else
  HOST="docker.io"; NS="$HUB"
fi
[[ -n "$NS" ]] || NS="library"
REF="$HOST/$NS/$IMG"

echo "${BOLD}${CYAN}Registry:${RESET} $HOST    ${BOLD}${CYAN}Repository:${RESET} $NS/$IMG"
echo "${DIM}mode:${RESET} ${PRIVATE:-auto}   ${DIM}meta:${RESET} $( [[ "$FETCH_META" == "1" ]] && echo on || echo off )"
echo


b64dec() { (base64 -d 2>/dev/null) || (base64 --decode 2>/dev/null) || (openssl base64 -d 2>/dev/null); }

docker_cfg_get_auth_b64() {
  local cfg="$1"
  local key
  for key in \
    "https://index.docker.io/v1/" \
    "https://registry-1.docker.io/v2/" \
    "https://registry-1.docker.io" \
    "registry-1.docker.io" \
    "index.docker.io/v1/"; do
    local val
    val="$(jq -r --arg k "$key" '.auths[$k].auth // empty' "$cfg" 2>/dev/null || true)"
    if [[ -n "$val" && "$val" != "null" ]]; then
      printf '%s' "$val"
      return 0
    fi
  done
  return 1
}

has_plain_auths_docker_cfg() {
  local cfg="$1"
  [[ -f "$cfg" ]] || return 1
  [[ -n "$(docker_cfg_get_auth_b64 "$cfg")" ]]
}

has_plain_auths_containers_cfg() {
  local f="$1"
  [[ -f "$f" ]] || return 1
  jq -e '.auths | to_entries | length>0' "$f" >/dev/null 2>&1
}

get_creds_from_docker_helper() {
  # ~/.docker/config.json의 credHelpers/credsStore를 통해 docker-credential-* 호출
  local cfg="${AUTHFILE:-$HOME/.docker/config.json}"
  [[ -f "$cfg" ]] || return 1

  if has_plain_auths_docker_cfg "$cfg"; then
    local b64 up
    b64="$(docker_cfg_get_auth_b64 "$cfg")"
    up="$(printf '%s' "$b64" | b64dec)" || return 1
    printf '%s' "$up"
    return 0
  fi

  local helper store prog
  helper="$(jq -r '.credHelpers["index.docker.io"] // .credHelpers["https://index.docker.io/v1/"] // empty' "$cfg" 2>/dev/null || true)"
  store="$(jq -r '.credsStore // empty' "$cfg" 2>/dev/null || true)"
  if [[ -n "$helper" ]]; then prog="docker-credential-$helper"; fi
  if [[ -z "$prog" && -n "$store" ]]; then prog="docker-credential-$store"; fi
  [[ -n "$prog" ]] || return 1
  command -v "$prog" >/dev/null 2>&1 || return 1

  local try url out user pass
  for url in "https://index.docker.io/v1/" "https://registry-1.docker.io" "https://registry-1.docker.io/v2/"; do
    out="$(printf '{"ServerURL":"%s"}' "$url" | "$prog" get 2>/dev/null || true)"
    user="$(printf '%s' "$out" | jq -r .Username 2>/dev/null || true)"
    pass="$(printf '%s' "$out" | jq -r .Secret   2>/dev/null || true)"
    if [[ -n "$user" && -n "$pass" && "$user" != "null" && "$pass" != "null" ]]; then
      printf '%s:%s' "$user" "$pass"
      return 0
    fi
  done

  return 1
}

# ECR 편의: 토큰 자동
ecr_maybe_set_creds() {
  local h="$1"
  if [[ "$h" =~ \.dkr\.ecr\.([a-z0-9-]+)\.amazonaws\.com$ ]] && command -v aws >/dev/null 2>&1; then
    local region="${BASH_REMATCH[1]}"
    REG_USER="AWS"
    REG_PASS="$(aws ecr get-login-password --region "$region")"
  fi
}

print_table() {
  local lines="$1" have_dates="$2"
  if [[ -z "$lines" ]]; then
    echo "⚠️  태그가 없습니다." >&2
    return 0
  fi
  if [[ "$have_dates" == "1" ]]; then
    printf "%s\n" "$lines" | sort -t $'\t' -k2,2r | awk -F'\t' -v y="$YELLOW" -v g="$GREEN" -v r="$RESET" '
      BEGIN{ printf "%-54s  %s\n", "TAG", "LAST UPDATED" }
      { printf y"%-54s"r"  "g"%s"r"\n", $1, $2 }
    '
  else
    printf "%s\n" "$lines" | sort | awk -v y="$YELLOW" -v r="$RESET" '
      BEGIN{ printf "%-54s\n", "TAG" }
      { printf y"%-54s"r"\n", $0 }
    '
  fi
}

# ---------- Docker Hub ----------
hub_list_public() {
  need curl; need jq
  local lines="" next="https://hub.docker.com/v2/repositories/${NS}/${IMG}/tags?page_size=${PAGE_SIZE}"
  while :; do
    local res code
    res="$(curl -fsS -w $'\n%{http_code}\n' "$next" || true)"
    code="${res##*$'\n'}"; res="${res%$'\n'*}"
    [[ "$code" == "200" ]] || break
    lines+=$'\n'$(echo "$res" | jq -r '.results[] | [.name, .last_updated] | @tsv')
    next="$(echo "$res" | jq -r '.next')"
    [[ -n "$next" && "$next" != "null" ]] || break
  done
  lines="${lines#"$'\n'"}"
  print_table "$lines" 1
}

hub_list_private_auto() {
  need curl; need jq

  if [[ "${PRIVATE:-}" == "1" ]]; then
    :
  else

    local code
    code="$(curl -s -o /dev/null -w '%{http_code}' \
      "https://hub.docker.com/v2/repositories/${NS}/${IMG}/tags?page_size=1" || true)"

    # PRIVATE=0 (무인증 강제)인데 공개가 아니면 실패 처리
    if [[ "${PRIVATE:-}" == "0" && "$code" != "200" ]]; then
      echo "❌ 공개 접근이 거부되었습니다. 인증이 필요합니다. (PRIVATE를 비우거나 1로 설정)" >&2
      exit 4
    fi

    # PRIVATE가 비어 있고(자동) 200이면 공개 레포이므로 공개 경로로 바로 처리
    if [[ -z "${PRIVATE:-}" && "$code" == "200" ]]; then
      hub_list_public
      return 0
    fi
  fi

  if command -v crane >/dev/null 2>&1; then
    if lines="$(crane ls "docker.io/${NS}/${IMG}" 2>/dev/null || true)"; [[ -n "$lines" ]]; then
      print_table "$lines" 0; return 0
    fi
  fi

  if command -v skopeo >/dev/null 2>&1 && [[ -f "$CONT_AUTH" ]] && has_plain_auths_containers_cfg "$CONT_AUTH"; then
    if lines="$(skopeo list-tags "docker://docker.io/${NS}/${IMG}" --authfile "$CONT_AUTH" 2>/dev/null | jq -r '.Tags[]' || true)"; [[ -n "$lines" ]]; then
      print_table "$lines" 0; return 0
    fi
  fi

  if [[ -z "${DOCKER_USERNAME:-}" || -z "${DOCKER_PASSWORD:-}" ]]; then
    if up="$(get_creds_from_docker_helper)"; then
      DOCKER_USERNAME="${up%%:*}"; DOCKER_PASSWORD="${up#*:}"
    fi
  fi

  : "${DOCKER_USERNAME:?Docker Hub 자격을 찾지 못했습니다. (docker login 후 재시도하거나 crane/skopeo login 사용)}"
  : "${DOCKER_PASSWORD:?Docker Hub 자격을 찾지 못했습니다. (docker login 후 재시도하거나 crane/skopeo login 사용)}"

  local token resp lines="" next="https://hub.docker.com/v2/repositories/${NS}/${IMG}/tags?page_size=${PAGE_SIZE}"
  token="$(curl -fsSL -H 'Content-Type: application/json' \
    -d "$(printf '{"username":"%s","password":"%s"}' "$DOCKER_USERNAME" "$DOCKER_PASSWORD")" \
    https://hub.docker.com/v2/users/login/ | jq -r .token)"
  [[ -n "$token" && "$token" != "null" ]] || { echo "❌ Docker Hub 인증 실패" >&2; exit 4; }

  while :; do
    resp="$(curl -fsS -H "Authorization: JWT $token" -w $'\n%{http_code}\n' "$next" || true)"
    code="${resp##*$'\n'}"; resp="${resp%$'\n'*}"
    [[ "$code" == "200" ]] || break
    lines+=$'\n'$(echo "$resp" | jq -r '.results[] | [.name, .last_updated] | @tsv')
    next="$(echo "$resp" | jq -r '.next')"
    [[ -n "$next" && "$next" != "null" ]] || break
  done
  lines="${lines#"$'\n'"}"
  print_table "$lines" 1
}

other_registry_list() {
  need jq
  local tags=""

  # try no-auth via skopeo
  if command -v skopeo >/dev/null 2>&1; then
    tags="$(skopeo list-tags "docker://$REF" 2>/dev/null | jq -r '.Tags[]' || true)"
    if [[ -z "$tags" ]]; then
      # try with authfile / creds
      if [[ -f "$CONT_AUTH" ]] && has_plain_auths_containers_cfg "$CONT_AUTH"; then
        tags="$(skopeo list-tags "docker://$REF" --authfile "$CONT_AUTH" 2>/dev/null | jq -r '.Tags[]' || true)"
      elif [[ -f "$AUTHFILE" ]] && has_plain_auths_containers_cfg "$AUTHFILE"; then
        # 일부 환경에서 docker config를 containers 형식으로 관리하는 경우
        tags="$(skopeo list-tags "docker://$REF" --authfile "$AUTHFILE" 2>/dev/null | jq -r '.Tags[]' || true)"
      else
        [[ -n "${REG_USER:-}" && -n "${REG_PASS:-}" ]] || ecr_maybe_set_creds "$HOST" || true
        if [[ -n "${REG_USER:-}" && -n "${REG_PASS:-}" ]]; then
          tags="$(skopeo list-tags "docker://$REF" --creds "$REG_USER:$REG_PASS" 2>/dev/null | jq -r '.Tags[]' || true)"
        fi
      fi
    fi
  fi

  # crane fallback
  if [[ -z "$tags" && "$(command -v crane)" ]]; then
    tags="$(crane ls "$REF" 2>/dev/null || true)"
  fi

  if [[ -z "$tags" ]]; then
    echo "❌ 태그를 가져오지 못했습니다. 인증 방법(crane auth login / skopeo login / REG_USER+REG_PASS)을 확인하세요." >&2
    exit 3
  fi

  # metadata
  if [[ "$FETCH_META" != "1" ]]; then
    print_table "$tags" 0
    return 0
  fi
  if ! command -v skopeo >/dev/null 2>&1; then
    echo "ℹ️  FETCH_META=1 이지만 skopeo가 없어 태그만 출력합니다." >&2
    print_table "$tags" 0
    return 0
  fi

  local with_dates="" count=0
  while IFS= read -r t; do
    [[ -n "$t" ]] || continue
    ((count++))
    if (( count > MAX_TAGS )); then
      echo "ℹ️  태그가 많아 상위 ${MAX_TAGS}개만 메타를 조회합니다." >&2
      break
    fi
    local created
    created="$(skopeo inspect "docker://$REF:$t" 2>/dev/null | jq -r '.Created // empty')"
    with_dates+=$'\n'"$t"$'\t'"$created"
  done <<< "$tags"
  with_dates="${with_dates#"$'\n'"}"
  if [[ -n "$with_dates" ]]; then
    print_table "$with_dates" 1
  else
    print_table "$tags" 0
  fi
}

# main
if [[ "$HOST" == "docker.io" ]]; then
  hub_list_private_auto
else
  other_registry_list
fi
