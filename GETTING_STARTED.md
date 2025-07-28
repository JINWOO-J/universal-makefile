# Getting Started Guide

🚀 **15분만에 Universal Makefile System 시작하기**

## ⚡ 빠른 시작 (5분)

### 새 프로젝트
```bash
# 1. 프로젝트 생성
mkdir my-new-project && cd my-new-project
git init

# 2. Universal Makefile System 추가
git submodule add https://github.com/jinwoo/universal-makefile .makefile-system

# 3. 자동 설정
./.makefile-system/install.sh

# 4. 프로젝트 설정 (자동 생성된 project.mk 편집)
vim project.mk  # REPO_HUB, NAME, VERSION 수정

# 5. 바로 사용!
make help       # 사용 가능한 명령어 확인
make build      # 첫 빌드
```

### 기존 프로젝트
```bash
# 1. 기존 프로젝트에서
git submodule add https://github.com/jinwoo/universal-makefile .makefile-system

# 2. 기존 Makefile 보존하며 설치
./.makefile-system/install.sh --existing-project

# 3. 설정 및 사용
vim project.mk  # 프로젝트에 맞게 설정
make help       # 새로운 기능 확인
```

## 📋 단계별 상세 가이드

### Step 1: 설치 방법 선택

**Option A: Git Submodule (권장)**
- ✅ 중앙 집중식 업데이트
- ✅ 여러 프로젝트 일관성
- ✅ 버전 관리 용이

```bash
git submodule add https://github.com/jinwoo/universal-makefile .makefile-system
./.makefile-system/install.sh --submodule
```

**Option B: 파일 복사**
- ✅ Git 의존성 없음
- ✅ 프로젝트 독립성
- ❌ 수동 업데이트 필요

```bash
curl -sSL https://raw.githubusercontent.com/jinwoo/universal-makefile/main/install.sh | bash
# 또는
wget https://github.com/jinwoo/universal-makefile/archive/main.zip
unzip main.zip && ./universal-makefile-main/install.sh --copy
```

### Step 2: 프로젝트 설정

`project.mk` 파일을 편집하여 프로젝트에 맞게 설정:

```makefile
# 필수 설정
REPO_HUB = your-dockerhub-username    # Docker 레지스트리
NAME = your-project-name              # 프로젝트명
VERSION = v1.0.0                      # 초기 버전

# Git 설정 (필요시 수정)
MAIN_BRANCH = main                    # 메인 브랜치명
DEVELOP_BRANCH = develop              # 개발 브랜치명

# Docker 설정 (필요시 수정)
DOCKERFILE_PATH = Dockerfile          # Dockerfile 경로
```

### Step 3: 환경별 설정 (선택사항)

```bash
# 환경별 디렉토리 생성
mkdir environments

# 개발 환경 설정
cat > environments/development.mk << 'EOF'
# 개발환경 전용 설정
DEBUG = true
COMPOSE_FILE = docker-compose.dev.yml

dev-up: ## 🚀 Start development environment
	@docker-compose -f $(COMPOSE_FILE) up -d
EOF
```

### Step 4: 기본 사용법 익히기

```bash
# 📋 도움말 시스템
make help                    # 모든 명령어 보기
make help-docker            # Docker 명령어만 보기
make help-git               # Git 워크플로우 보기

# 🔨 빌드 및 테스트
make build                  # Docker 이미지 빌드
make test                   # 테스트 실행 (구현 필요)
make push                   # 이미지 푸시

# 🚀 배포
make up                     # 서비스 시작
make down                   # 서비스 중지
make logs                   # 로그 확인

# 🌿 Git 워크플로우
make auto-release           # 완전 자동 릴리스
make bump-version           # 버전 확인
make clean-old-branches     # 오래된 브랜치 정리

# 🧹 정리
make clean                  # 기본 정리
make docker-clean          # Docker 리소스 정리
```

## 🎯 프로젝트 타입별 설정

### Node.js 프로젝트
```bash
# 예시 복사
cp .makefile-system/examples/nodejs-project/project.mk .

# 주요 설정
VERSION_UPDATE_TOOL = yarn
VERSION_FILE = package.json
TEST_COMMAND = npm test
```

### Python 프로젝트
```bash
# 예시 복사
cp .makefile-system/examples/python-project/project.mk .

# 주요 설정
VERSION_UPDATE_TOOL = poetry
VERSION_FILE = pyproject.toml
TEST_COMMAND = pytest
```

### 일반적인 Docker 프로젝트
```bash
# 기본 템플릿 사용
cp .makefile-system/templates/project.mk.template project.mk

# 필수 설정만 수정
vim project.mk  # REPO_HUB, NAME, VERSION
```

## 🌍 환경별 사용법

### 개발 환경
```bash
make build ENV=development     # 개발 빌드
make dev-up                    # 개발 환경 시작
make dev-logs                  # 개발 로그 확인
```

### 스테이징 환경
```bash
make build ENV=staging         # 스테이징 빌드
make deploy ENV=staging        # 스테이징 배포
```

### 프로덕션 환경
```bash
make release ENV=production    # 프로덕션 릴리스
```

## 🔧 개인 설정 (.project.local.mk)

팀원마다 다른 설정이 필요한 경우:

```bash
# 개인별 로컬 설정 (Git에서 무시됨)
cat > .project.local.mk << 'EOF'
# 개인 개발용 설정
REPO_HUB = dev-myname
DEBUG = true

# 개인용 커스텀 타겟
my-debug: ## 🐛 My debugging setup
	@echo "Starting my debug environment..."
EOF
```

## 📈 점진적 적용 전략

### Phase 1: 기본 적용 (1주)
1. ✅ 설치 및 기본 설정
2. ✅ `make help`, `make build` 사용
3. ✅ 팀원들과 기본 사용법 공유

### Phase 2: Git 워크플로우 (2주)
1. ✅ `make auto-release` 도입
2. ✅ 브랜치 정리 자동화
3. ✅ 버전 관리 표준화

### Phase 3: 고도화 (1개월)
1. ✅ 환경별 설정 분리
2. ✅ CI/CD 파이프라인 통합
3. ✅ 프로젝트별 커스터마이징

## 🚨 자주 발생하는 실수들

### ❌ 실수 1: 권한 문제
```bash
# 문제: permission denied
# 해결:
chmod +x .makefile-system/install.sh
chmod +x .makefile-system/scripts/*.sh
```

### ❌ 실수 2: project.mk 누락
```bash
# 문제: project.mk not found
# 해결:
cp .makefile-system/templates/project.mk.template project.mk
vim project.mk  # 기본 정보 입력
```

### ❌ 실수 3: Docker 미실행
```bash
# 문제: Docker is not running
# 해결:
make check-docker    # Docker 상태 확인
# Docker Desktop 실행 후 재시도
```

### ❌ 실수 4: Git 상태 불일치
```bash
# 문제: Working directory has uncommitted changes
# 해결:
git status           # 변경사항 확인
git add . && git commit -m "Update"  # 커밋 후 재시도
```

## 🎪 실제 사용 시나리오

### 시나리오 1: 새 기능 개발
```bash
# 1. 기능 브랜치 생성
git checkout -b feature/new-feature

# 2. 개발 환경 시작
make dev-up

# 3. 개발 및 테스트
make build
make test

# 4. 개발 완료 후 통합
make sync-develop
```

### 시나리오 2: 릴리스 배포
```bash
# 1. 릴리스 준비 확인
make git-status
make clean

# 2. 자동 릴리스 실행
make auto-release

# 3. 배포 확인
make prod-health-check
```

### 시나리오 3: 긴급 수정
```bash
# 1. 핫픽스 브랜치 생성
make start-hotfix HOTFIX_NAME=critical-security-fix

# 2. 수정 및 테스트
make build
make test

# 3. 긴급 배포
make finish-hotfix
make prod-deploy
```

## 🎓 다음 단계

### 고급 기능 학습
- 📖 [Help 시스템 활용](../README.md#help-시스템)
- 🐳 [Docker 고급 사용법](../README.md#docker-고급-기능)
- 🌊 [Git Flow 마스터하기](../README.md#git-flow-자동화)

### 팀 도입 전략
- 👥 [팀 협업 가이드](../README.md#팀-협업)  
- 🏭 [CI/CD 통합](../README.md#cicd-통합)
- 📊 [모니터링 설정](../README.md#모니터링-및-메트릭)

### 커스터마이징
- 🎨 [프로젝트별 타겟 추가](../examples/README.md#커스터마이징-가이드)
- 🏢 [기업별 표준화](../examples/README.md#기업별-커스터마이징)
- 🔌 [플러그인 개발](../README.md#확장-및-커스터마이징)

---

**💡 도움이 필요하신가요?**
- 🐛 [Issues](https://github.com/jinwoo/universal-makefile/issues)
- 💬 [Discussions](https://github.com/jinwoo/universal-makefile/discussions)
- 📧 Email: support@yourcompany.com