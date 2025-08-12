# makefiles/show_grouped.awk

function base(p, a, n)  { n = split(p, a, "/"); return a[n] }
function trim(s)        { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }

BEGIN {
  # 1) 그룹 정의 파싱 (표시 순서 유지)
  ng = split(groups, G, "|")
  for (i = 1; i <= ng; i++) {
    split(G[i], kv, ":")
    ord[i] = kv[1]
    lab[kv[1]] = kv[2]
  }

  # 2) 출력 대상 파일 화이트리스트
  m = split(list, L, ",")
  for (i = 1; i <= m; i++) {
    x = L[i]; sub(/^[[:space:]]+/, "", x); sub(/[[:space:]]+$/, "", x)
    allow[x] = 1
  }
}

# "타겟: ... ## 설명" 라인만 수집
/^[A-Za-z0-9_.-]+:[[:space:]].*##[[:space:]]/ {
  line = $0
  pos  = index(line, "## "); if (!pos) next

  c = substr(line, pos + 3)         # comment/desc
  split(line, p, ":")
  t = p[1]                          # target
  f = base(FILENAME)                # filename
  if (!(f in allow)) next

  # 3) 파일명으로 도메인 추론
  if      (f == "docker.mk")                          d = "docker"
  else if (f == "compose.mk")                         d = "compose"
  else if (f == "git-flow.mk")                        d = "git"
  else if (f == "version.mk" || f == "version-check.mk") d = "version"
  else if (f == "cleanup.mk")                         d = "cleanup"
  else if (f == "core.mk")                            d = "core"
  else                                                d = "other"

  # 4) [key] 태그가 있으면 우선 분류
  g = ""
  for (i = 1; i <= ng; i++) {
    tag = "[" ord[i] "]"
    if (index(c, tag) > 0) { g = ord[i]; break }
  }

  # 5) 태그 없으면 도메인별 휴리스틱
  if (g == "") {
    if (d == "docker") {
      if (t == "build" || index(t, "build-") == 1 || t == "push" || t == "tag-latest") g = "build"
      else if (t == "bash" || t == "run" || t == "exec" || t == "docker-logs")         g = "dev"
      else if (index(t, "docker-") == 1 || index(t, "image-") == 1 || t == "security-scan" || t == "clear-build-cache") g = "mgmt"
      else g = "other"
    } else if (d == "compose") {
      if (t == "up" || t == "down" || t == "restart" || t == "rebuild" || t == "dev-up" || t == "dev-down" || t == "dev-restart") g = "ops"
      else if (t == "logs" || t == "logs-tail" || t == "dev-logs" || t == "status" || t == "dev-status" || t == "health-check")   g = "monitor"
      else if (t == "exec-service" || t == "restart-service" || t == "logs-service" || t == "scale")                               g = "service"
      else if (t == "compose-config" || t == "compose-images")                                                                     g = "inspect"
      else if (t == "compose-clean" || t == "compose-test" || t == "backup-volumes")                                              g = "maint"
      else g = "other"
    } else if (d == "git") {
      if (index(t, "start-release") == 1 || index(t, "finish-release") == 1 || index(t, "merge-release") == 1 || index(t, "push-release") == 1 ||
          t == "create-release-branch" || t == "push-release-branch" || t == "github-release" || t == "auto-release" || t == "update-and-release" || t == "ur")
        g = "release"
      else if (index(t, "start-hotfix") == 1 || index(t, "finish-hotfix") == 1) g = "hotfix"
      else if (index(t, "git-") == 1 || t == "sync-develop" || t == "git-status" || t == "git-branches") g = "branch"
      else g = "other"
    } else if (d == "version") {
      if (t == "version" || t == "update-version" || t == "update-version-file" || t == "version-next") g = "show"
      else if (t == "version-tag" || t == "push-tags" || t == "delete-tag") g = "tagging"
      else if (t == "version-changelog" || t == "version-release-notes")    g = "notes"
      else if (t == "version-patch" || t == "version-minor" || t == "version-major") g = "semver"
      else if (t == "validate-version" || t == "check-version-consistency" || t == "export-version-info") g = "validate"
      else g = "other"
    } else if (d == "cleanup") {
      if (t == "clean" || t == "clean-temp" || t == "clean-logs" || t == "clean-cache" || t == "clean-build" || t == "env-clean") g = "project"
      else if (t == "clean-node" || t == "clean-python" || t == "clean-java") g = "lang"
      else if (t == "clean-ide" || t == "clean-test" || t == "clean-recursively" || t == "clean-secrets") g = "ide"
      else if (index(t, "docker-") == 1) g = "docker"
      else g = "other"
    } else if (d == "core") {
      if (index(t, "env-") == 1) {
        if      (t == "env-keys" || t == "env-get" || t == "env-show") g = "query"
        else if (t == "env-pretty" || t == "env-github")               g = "format"
        else if (t == "env-file")                                      g = "file"
        else g = "other"
      } else if (index(t, "self-") == 1) {
        if (t == "self-app") g = "app"; else g = "installer"
      } else g = "other"
    } else g = "other"
  }

  # 6) 설명에서 [key] 태그 제거
  for (i = 1; i <= ng; i++) {
    tag = "[" ord[i] "]"
    while ((s = index(c, tag)) > 0)
      c = substr(c, 1, s - 1) substr(c, s + length(tag))
  }
  desc = trim(c)

  # 7) 수집 및 폭 계산
  n[g]++
  T[g, n[g]] = t
  D[g, n[g]] = desc
  F[g, n[g]] = f
  if (length(t) > W[g]) W[g] = length(t)
}

END {
  for (ii = 1; ii <= ng; ii++) {
    k = ord[ii]; if (n[k] < 1) continue

    # 타깃명 알파벳 정렬
    for (i = 1; i <= n[k]; i++) idx[i] = i
    for (i = 1; i <= n[k]; i++)
      for (j = i + 1; j <= n[k]; j++)
        if (T[k, idx[i]] > T[k, idx[j]]) { tmp = idx[i]; idx[i] = idx[j]; idx[j] = tmp }

    printf("%s%s:%s\n", yellow, lab[k], reset)
    for (i = 1; i <= n[k]; i++) {
      ii2 = idx[i]
      if (show == "true" || show == "1")
        printf("  %s%-*s%s %s  [%s]\n", green, W[k] + 2, T[k, ii2], reset, D[k, ii2], F[k, ii2])
      else
        printf("  %s%-*s%s %s\n", green, W[k] + 2, T[k, ii2], reset, D[k, ii2])
    }
    printf("\n")
  }
}
