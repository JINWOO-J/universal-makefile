# Universal Makefile System

🚀 **재사용 가능한 Docker 기반 CI/CD Makefile 시스템**

여러 프로젝트에서 일관된 빌드, 테스트, 배포 워크플로우를 제공하는 모듈화된 Makefile 시스템입니다.

## ✨ 주요 특징

- 🔧 **모듈화된 구조**: 기능별로 분리된 Makefile 모듈
- 🐳 **Docker 통합**: Docker 및 Docker Compose 완전 지원
- 🌿 **Git Flow**: 자동화된 Git 워크플로우 및 릴리스 관리
- 🎯 **다중 환경**: 개발/스테이징/프로덕션 환경 지원
- 📋 **자동 문서화**: 모든 타겟에 대한 자동 help 시스템
- 🔄 **두 가지 설치 방식**: Git Submodule 또는 파일 복사
- 🎨 **프로젝트별 커스터마이징**: 최소한의 설정으로 프로젝트 적응

## 📦 지원하는 프로젝트 타입

- **Node.js** (npm, yarn)
- **Python** (poetry, pip)
- **Rust** (cargo)
- **Go** (go modules)
- **Java** (maven, gradle)
- **PHP** (composer)
- **Ruby** (bundler)
- **일반적인 Docker 기반 프로젝트**

## 🚀 빠른 시작

### 방법 1: Git Submodule (권장)

```bash
# 기존 프로젝트에 추가
cd your-project
```


```bash
git submodule add https://github.com/jinwoo-j/universal-makefile .makefile-system

# 설치 및 설정
./.makefile-system/install.sh

# 프로젝트 설정 (project.mk 편집)
vim project.mk

# 사용 가능한 명령어 확인
make help
```

### 방법 2: 스크립트 설치

```bash
# 원격 설치
curl -sSL https://raw.githubusercontent.com/jinwoo-j/universal-makefile/main/install.sh | bash

# 또는 수동 설치
wget https://github.com/jinwoo-j/universal-makefile/archive/main.zip
unzip main.zip && cd universal-makefile-main
./install.sh --copy
```

### 기존 프로젝트에 추가

```bash
# 기존 Makefile이 있는 프로젝트
git submodule add https://github.com/jinwoo-j/universal-makefile .makefile-system
./.makefile-system/install.sh --existing-project
```

## 📋 기본 사용법

### 주요 명령어

```bash
# 도움말 및 정보
make help                    # 모든 사용 가능한 명령어 표시
make getting-started         # 시작 가이드 표시
make debug-vars             # 현재 설정 표시

# 빌드 및 테스트
make build                  # Docker 이미지 빌드
make test                   # 테스트 실행
make lint                   # 코드 린팅

# Docker Compose
make up                     # 서비스 시작
make down                   # 서비스 중지
make logs                   # 로그 확인

# 릴리스 관리
make auto-release          # 완전 자동화된 릴리스
make bump-version          # 버전 계산
make create-release-branch # 릴리스 브랜치 생성

# 정리
make clean                 # 기본 정리
make docker-clean         # Docker 리소스 정리
```

### 환경별 사용

```bash
# 개발 환경
make build ENV=development
make dev-up

# 스테이징 환경
make deploy ENV=staging

# 프로덕션 환경
make release ENV=production
```

## 🏗️ 프로젝트 구조

### Submodule 방식
```
your-project/
├── .makefile-system/          # 공통 시스템 (submodule)
│   ├── Makefile              # 메인 시스템
│   ├── makefiles/            # 기능별 모듈
│   ├── templates/            # 템플릿 파일들
│   └── scripts/              # 헬퍼 스크립트들
├── Makefile                  # 프로젝트 진입점
├── project.mk               # 프로젝트 설정
├── .project.local.mk        # 개발자별 로컬 설정
└── environments/            # 환경별 설정
    ├── development.mk
    ├── staging.mk
    └── production.mk
```

### 복사 방식
```
your-project/
├── makefiles/               # 복사된 공통 시스템
├── Makefile                # 프로젝트 진입점
├── project.mk             # 프로젝트 설정
└── ...
```

## ⚙️ 설정 파일들

### project.mk (필수)

프로젝트의 기본 정보를 정의합니다:

```makefile
# 기본 정보
REPO_HUB = mycompany
NAME = myproject
VERSION = v1.0.0

# Git 설정
MAIN_BRANCH = main
DEVELOP_BRANCH = develop

# Docker 설정
DOCKERFILE_PATH = Dockerfile
COMPOSE_FILE = docker-compose.yml

# 커스텀 타겟
custom-deploy: ## 🚀 Deploy to custom infrastructure
	@echo "Deploying $(NAME)..."
```

### .project.local.mk (선택사항)

개발자별 로컬 설정 (Git에서 무시됨):

```makefile
# 개발자 A의 설정
REPO_HUB = dev-alice
DEBUG = true

# 개인용 타겟
my-test: ## 🧪 My custom test
	@echo "Running my tests..."
```

### environments/*.mk (선택사항)

환경별 설정:

```makefile
# environments/development.mk
DEBUG = true
COMPOSE_FILE = docker-compose.dev.yml

dev-seed: ## 🌱 Seed development data
	@echo "Seeding development database..."
```

## 🔧 고급 기능

### 자동 버전 관리

```bash
# 시맨틱 버전 자동 증가
make version-patch    # 1.0.0 -> 1.0.1
make version-minor    # 1.0.0 -> 1.1.0
make version-major    # 1.0.0 -> 2.0.0

# 릴리스 노트 자동 생성
make version-changelog
make version-release-notes
```

### Git Flow 자동화

```bash
# 릴리스 브랜치 생성
make create-release-branch

# 릴리스 완료 (병합, 태깅, GitHub 릴리스)
make finish-release

# 전체 자동화
make auto-release
```

### 멀티플랫폼 빌드

```bash
# AMD64 + ARM64 동시 빌드
make build-multi

# 보안 스캔
make security-scan

# 이미지 분석
make image-size
```

### 정리 및 유지보수

```bash
# 언어별 정리
make clean-node      # Node.js
make clean-python    # Python
make clean-rust      # Rust

# 고급 정리
make clean-large-files    # 큰 파일 찾기
make clean-old-files     # 오래된 파일 찾기
make clean-old-branches  # 병합된 브랜치 정리
```

## 📖 상세 도움말

시스템의 각 기능에 대한 상세한 도움말을 확인할 수 있습니다:

```bash
make help-docker     # Docker 관련 명령어
make help-git        # Git 워크플로우
make help-compose    # Docker Compose
make help-cleanup    # 정리 명령어

# 특정 타겟에 대한 도움말
make help-build      # build 타겟 상세 정보
```

## 🔄 업데이트

### Submodule 방식

```bash
# 자동 업데이트
make update-makefile-system

# 수동 업데이트
git submodule update --remote .makefile-system
```

### 복사 방식

```bash
# 재설치 필요
./install.sh --copy --force
```

## 🤝 팀 협업

### 새 팀원 온보딩

```bash
# 1. 레포지토리 클론
git clone --recursive your-project-repo
cd your-project

# 2. 즉시 사용 가능
make help
make build
make up
```

### 프로젝트별 커스터마이징

각 프로젝트에서 `project.mk`에 커스텀 타겟을 추가:

```makefile
# 프로젝트별 배포
deploy-to-k8s: ## 🚀 Deploy to Kubernetes
	kubectl apply -f k8s/
	$(call success, "Deployed to Kubernetes")

# 프로젝트별 테스트
integration-test: ## 🧪 Run integration tests
	docker-compose -f docker-compose.test.yml up --abort-on-container-exit
	$(call success, "Integration tests completed")
```

## 🏭 CI/CD 통합

### GitHub Actions

```yaml
name: CI/CD
on: [push, pull_request]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
        with:
          submodules: recursive

      - name: Build and Test
        run: |
          make build
          make test
          make security-scan

      - name: Deploy
        if: github.ref == 'refs/heads/main'
        run: make deploy ENV=production
```

### GitLab CI

```yaml
stages:
  - build
  - test
  - deploy

build:
  stage: build
  script:
    - git submodule update --init --recursive
    - make build

test:
  stage: test
  script:
    - make test
    - make lint

deploy:
  stage: deploy
  script:
    - make deploy ENV=production
  only:
    - main
```

## 🐛 문제 해결

### 일반적인 문제들

```bash
# 1. Docker가 실행되지 않음
make check-docker

# 2. 버전 불일치
make check-version-consistency

# 3. 설정 확인
make debug-vars

# 4. 전체 정리 후 재시작
make deep-clean
make build
```

### 로그 확인

```bash
# 서비스 로그
make logs

# 특정 서비스 로그
make logs-service SERVICE=app

# 빌드 로그 (디버그 모드)
make build DEBUG=true
```

## 📊 모니터링 및 메트릭

### 프로젝트 상태 확인

```bash
# 전체 상태 확인
make status

# Docker 상태
make docker-info

# Git 상태
make git-status

# 정리 상태 보고
make clean-status
```

### 성능 모니터링

```bash
# 이미지 크기 분석
make image-size

# 빌드 시간 측정 (자동)
make build  # 빌드 시간이 자동으로 표시됨

# 리소스 사용량
make health-check
```

## 🔒 보안

### 보안 모범 사례

```bash
# 보안 스캔
make security-scan

# 민감한 파일 정리 (주의!)
make clean-secrets

# 이미지 취약점 스캔 (trivy 설치 시)
make security-scan
```

### 환경 변수 관리

```bash
# .env 파일 생성
make env

# 환경 설정 확인
make env-show

# 로컬 설정은 .project.local.mk 사용
echo "REPO_HUB=dev-$(whoami)" > .project.local.mk
```

## 📚 확장 및 커스터마이징

### 새로운 언어/프레임워크 지원

시스템을 새로운 언어나 프레임워크에 맞게 확장하려면:

1. `project.mk`에 언어별 설정 추가
2. 필요시 `makefiles/` 디렉토리에 새 모듈 추가
3. `cleanup.mk`에 언어별 정리 함수 추가

### 플러그인 시스템

```makefile
# project.mk에서 조건부 모듈 로딩
ifneq (,$(wildcard plugins/))
    include plugins/*.mk
endif
```

### 회사별 커스터마이징

Fork를 만들어 회사 특화 기능 추가:

```bash
# 회사 전용 fork 생성
git clone https://github.com/company/universal-makefile company-makefile
cd company-makefile

# 회사별 기능 추가
# - 내부 CI/CD 시스템 통합
# - 회사 표준 Docker 이미지
# - 보안 정책 적용
# - 내부 도구 통합
```

## 🤔 FAQ

### Q: 기존 Makefile과 충돌하지 않나요?
A: `--existing-project` 옵션을 사용하면 기존 Makefile을 보존하고 `Makefile.universal`로 새 시스템을 생성합니다.

### Q: Submodule 방식과 복사 방식 중 어떤 것을 선택해야 하나요?
A: **Submodule 방식을 권장**합니다. 중앙 집중식 업데이트가 가능하고 여러 프로젝트를 일관되게 관리할 수 있습니다.

### Q: 프로젝트별로 다른 버전의 시스템을 사용할 수 있나요?
A: 네, Submodule에서 특정 태그나 커밋을 지정할 수 있습니다:
```bash
cd .makefile-system
git checkout v1.2.0
cd ..
git add .makefile-system
```

### Q: Docker 없이도 사용할 수 있나요?
A: 네, Docker 관련 타겟들은 선택사항입니다. Git 워크플로우, 버전 관리, 정리 기능 등은 Docker 없이도 사용 가능합니다.

### Q: Windows에서도 작동하나요?
A: Git Bash, WSL2, 또는 Docker Desktop이 설치된 환경에서 작동합니다.

## 🚀 로드맵

### v1.1.0
- [ ] Kubernetes 배포 지원
- [ ] Terraform 통합
- [ ] 더 많은 언어 지원 (C#, Swift, Kotlin)

### v1.2.0
- [ ] 웹 기반 설정 도구
- [ ] 모니터링 대시보드 통합
- [ ] 자동 보안 업데이트

### v2.0.0
- [ ] 플러그인 시스템
- [ ] 그래픽 사용자 인터페이스
- [ ] 클라우드 네이티브 기능

## 🤝 기여하기

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### 개발 환경 설정

```bash
# 개발용 클론
git clone https://github.com/company/universal-makefile
cd universal-makefile

# 테스트 프로젝트에서 테스트
mkdir test-project && cd test-project
../install.sh --copy
make help
```

## 📄 라이선스

이 프로젝트는 MIT 라이선스 하에 배포됩니다. 자세한 내용은 [LICENSE](LICENSE) 파일을 참조하세요.

## 🙏 감사의 말

- Docker 및 Docker Compose 커뮤니티
- Make 및 GNU Make 개발자들
- 모든 오픈소스 기여자들

---

**💡 도움이 필요하신가요?**

- 📖 [Wiki](https://github.com/jinwoo-j/universal-makefile/wiki)
- 🐛 [Issues](https://github.com/jinwoo-j/universal-makefile/issues)
- 💬 [Discussions](https://github.com/jinwoo-j/universal-makefile/discussions)

**⭐ 이 프로젝트가 도움이 되었다면 스타를 눌러주세요!**
