# Examples Directory

이 디렉토리는 Universal Makefile System을 다양한 프로젝트 타입에서 사용하는 방법을 보여주는 예시들을 포함합니다.

## 📁 디렉토리 구조

```
examples/
├── nodejs-project/          # Node.js 프로젝트 예시
│   ├── project.mk           # Node.js 전용 설정
│   ├── package.json         # NPM 패키지 설정
│   └── Dockerfile           # Node.js 최적화된 Dockerfile
├── python-project/          # Python 프로젝트 예시
│   ├── project.mk           # Python 전용 설정
│   ├── pyproject.toml       # Poetry 설정
│   └── Dockerfile           # Python 최적화된 Dockerfile
└── environments/            # 환경별 설정 예시
    ├── development.mk       # 개발 환경 설정
    ├── staging.mk          # 스테이징 환경 설정
    └── production.mk       # 프로덕션 환경 설정
```

## 🚀 사용 방법

### 1. 새 프로젝트 시작하기

```bash
# 1. 원하는 프로젝트 타입의 예시를 복사
cp -r examples/nodejs-project/* your-new-project/

# 2. Universal Makefile System 추가
cd your-new-project
git submodule add https://github.com/company/universal-makefile .makefile-system

# 3. 초기 설정
./.makefile-system/install.sh --submodule

# 4. project.mk 수정
vim project.mk

# 5. 사용!
make help
make build
```

### 2. 기존 프로젝트에 적용하기

```bash
# 1. 적절한 예시의 project.mk 참고
cat examples/nodejs-project/project.mk

# 2. 기존 프로젝트에 Universal Makefile System 추가
git submodule add https://github.com/company/universal-makefile .makefile-system
./.makefile-system/install.sh --existing-project

# 3. project.mk 생성 및 커스터마이징
cp examples/nodejs-project/project.mk project.mk
# 프로젝트에 맞게 수정

# 4. 환경별 설정 추가 (선택사항)
mkdir environments
cp examples/environments/development.mk environments/
```

## 📋 프로젝트별 특징

### Node.js 프로젝트
- **의존성 관리**: npm/yarn 자동 감지
- **빌드 시스템**: webpack, vite 등 지원
- **테스트**: jest, mocha 등 통합
- **보안**: npm audit 통합
- **배포**: PM2, Docker, Kubernetes 지원

**주요 커스텀 타겟:**
- `install`: 의존성 설치 (npm/yarn 자동 감지)
- `dev-server`: 개발 서버 시작
- `build-assets`: 프로덕션 빌드
- `test-e2e`: E2E 테스트 실행
- `security-audit`: npm 보안 감사

### Python 프로젝트
- **의존성 관리**: Poetry, pip-tools 지원
- **테스트**: pytest, coverage 통합
- **코드 품질**: black, isort, flake8, mypy
- **보안**: bandit, safety 통합
- **배포**: uvicorn, gunicorn, Docker 지원

**주요 커스텀 타겟:**
- `install`: Poetry/pip 의존성 설치
- `dev-server`: 개발 서버 시작 (FastAPI/Django)
- `test-coverage`: 커버리지 포함 테스트
- `lint-fix`: 자동 코드 포맷팅
- `type-check`: mypy 타입 체크
- `migrate`: 데이터베이스 마이그레이션

## 🌍 환경별 설정

### Development (개발 환경)
- **특징**: 핫 리로드, 디버깅 도구, 상세 로그
- **주요 타겟**: `dev-up`, `dev-watch`, `dev-seed`, `dev-reset`
- **포트**: 개발용 포트 노출
- **데이터**: 시드 데이터 자동 생성

### Staging (스테이징 환경)
- **특징**: 프로덕션과 유사한 환경, 통합 테스트
- **주요 타겟**: `staging-deploy`, `staging-test`, `staging-rollback`
- **배포**: Kubernetes 또는 Docker Compose
- **백업**: 자동 백업 및 복원

### Production (프로덕션 환경)
- **특징**: 보안 강화, 모니터링, 확장성
- **주요 타겟**: `prod-deploy`, `prod-rollback`, `prod-scale`
- **보안**: 다중 검증 단계, 확인 프롬프트
- **백업**: 중요 데이터 백업 시스템

## 🎯 커스터마이징 가이드

### 새로운 언어/프레임워크 추가

1. **프로젝트 디렉토리 생성**
   ```bash
   mkdir examples/your-framework-project
   ```

2. **project.mk 작성**
   ```makefile
   # 기본 설정
   REPO_HUB = mycompany
   NAME = my-framework-app
   VERSION = v1.0.0
   
   # 프레임워크별 커스텀 타겟
   framework-build: ## 🔨 Build with framework
       @echo "Building with your framework..."
   ```

3. **Dockerfile 작성**
   - 프레임워크에 최적화된 멀티스테이지 빌드
   - 보안 강화 (non-root user)
   - 헬스체크 포함

4. **예시 파일들 추가**
   - 설정 파일 (package.json, requirements.txt 등)
   - 환경 변수 예시
   - CI/CD 설정 예시

### 기업별 커스터마이징

```makefile
# project.mk에 기업별 설정 추가

# 기업 내부 레지스트리
REPO_HUB = internal-registry.company.com/myteam

# 기업 표준 라벨
DOCKER_BUILD_ARGS += --label "company.team=myteam"
DOCKER_BUILD_ARGS += --label "company.environment=$(ENV)"

# 기업 내부 도구 통합
company-deploy: ## 🚀 Deploy using company tools
    @company-deploy-tool --app $(NAME) --version $(VERSION)

company-security-scan: ## 🔒 Run company security scan
    @company-security-scanner $(FULL_TAG)
```

## 🔧 문제 해결

### 자주 발생하는 문제들

1. **권한 문제**
   ```bash
   # 스크립트 실행 권한 부여
   chmod +x .makefile-system/install.sh
   chmod +x scripts/*.sh
   ```

2. **Docker 관련 문제**
   ```bash
   # Docker 데몬 확인
   make check-docker
   
   # Docker 정리
   make docker-clean
   ```

3. **Git 관련 문제**
   ```bash
   # Git 상태 확인
   make git-status
   
   # 작업 디렉토리 정리
   make check-git-clean
   ```

## 📚 추가 자료

- [Universal Makefile System 메인 문서](../README.md)
- [설치 가이드](../README.md#설치)
- [고급 사용법](../README.md#고급-기능)
- [문제 해결](../README.md#문제-해결)

## 🤝 기여하기

새로운 예시나 개선사항이 있다면:

1. 새로운 예시 디렉토리 생성
2. README.md에 예시 추가
3. Pull Request 생성

**예시 기여 시 포함해야 할 것들:**
- [ ] project.mk (커스텀 타겟 포함)
- [ ] Dockerfile (보안 강화)
- [ ] 프레임워크별 설정 파일
- [ ] 사용법 설명
- [ ] 테스트 확인