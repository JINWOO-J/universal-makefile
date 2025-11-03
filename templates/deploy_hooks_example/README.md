# 배포 훅 예제 (Deploy Hooks Examples)

이 디렉토리는 Universal Makefile System의 배포 훅 시스템을 사용하는 방법을 보여주는 예제들을 포함합니다.

## 📁 파일 구조

```
deploy_hooks_example/
├── README.md                    # 이 파일
├── custom_pre_deploy.py        # Pre-deploy 훅 예제
└── custom_post_deploy.py       # Post-deploy 훅 예제
```

## 🚀 사용 방법

### 1. 프로젝트에 복사

```bash
# 프로젝트 루트에서 실행
mkdir -p deploy_hooks
cp universal-makefile/templates/deploy_hooks_example/*.py deploy_hooks/
```

### 2. 환경 변수 설정

```bash
# .env.runtime 또는 환경별 설정 파일에 추가

# 기본 설정
ENVIRONMENT=production
SERVICE_KIND=be
VERSION=1.0.0

# SSL 인증서 (프로덕션용)
SSL_CERT_PATH=/path/to/ssl/cert.pem

# 백업 시스템
BACKUP_API_URL=https://backup.company.com/api
BACKUP_API_KEY=your_backup_api_key

# 알림 설정
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK
DEPLOY_START_WEBHOOK_URL=https://api.company.com/webhooks/deploy-start

# 모니터링 시스템
MONITORING_API_URL=https://monitoring.company.com/api
MONITORING_API_KEY=your_monitoring_api_key

# 성능 테스트
MAX_RESPONSE_TIME_MS=1000
LOAD_TEST_SCRIPT=./scripts/load_test.sh

# 메트릭 수집
METRICS_API_URL=https://metrics.company.com/api

# 헬스체크 URL
FRONTEND_URL=https://app.company.com
API_URL=https://api.company.com
```

### 3. 훅 실행

```bash
# Pre-deploy 훅 실행
python universal-makefile/scripts/deploy_hooks.py pre production be

# Post-deploy 훅 실행
python universal-makefile/scripts/deploy_hooks.py post production be

# 기존 스크립트와 통합
python universal-makefile/scripts/pre_deploy.py production be --use-hooks
python universal-makefile/scripts/post_deploy.py production be --use-hooks
```

### 4. Makefile 통합

```makefile
# project.mk에 추가
DEPLOY_HOOKS_ENABLED ?= true

deploy-with-hooks: ## 🪝 훅을 포함한 배포
	@if [ "$(DEPLOY_HOOKS_ENABLED)" = "true" ]; then \
		python $(MAKEFILE_DIR)/scripts/deploy_hooks.py pre $(ENV) $(SERVICE_KIND) || exit 1; \
	fi
	@$(MAKE) build push
	@if [ "$(DEPLOY_HOOKS_ENABLED)" = "true" ]; then \
		python $(MAKEFILE_DIR)/scripts/deploy_hooks.py post $(ENV) $(SERVICE_KIND) || exit 1; \
	fi
```

## 📋 포함된 훅들

### Pre-deploy 훅

#### CustomEnvironmentCheck
- **목적**: 환경별 커스텀 검증
- **기능**:
  - 프로덕션: SSL 인증서, 백업 시스템 확인
  - 스테이징: 테스트 API 키 확인
  - 개발: 관대한 검증

#### DatabaseMigrationCheck
- **목적**: 데이터베이스 마이그레이션 관리
- **기능**:
  - 마이그레이션 필요 여부 확인
  - 프로덕션에서 자동 백업 생성
  - Django 마이그레이션 실행

#### ExternalServiceNotification
- **목적**: 외부 서비스에 배포 시작 알림
- **기능**:
  - 웹훅을 통한 배포 시작 알림
  - 배포 정보 전송

### Post-deploy 훅

#### CustomHealthCheck
- **목적**: 프로젝트별 상세 헬스체크
- **기능**:
  - 프론트엔드: 페이지 로드, JS 번들, API 연결 확인
  - 백엔드: API 엔드포인트, DB, 캐시, 중요 엔드포인트 확인

#### PerformanceTest
- **목적**: 배포 후 성능 검증
- **기능**:
  - 응답 시간 테스트
  - 간단한 부하 테스트
  - 프로덕션 환경에서만 실행

#### SlackNotification
- **목적**: Slack으로 배포 완료 알림
- **기능**:
  - 환경별 다른 채널/메시지
  - 상세한 배포 정보 포함

#### MonitoringRegistration
- **목적**: 모니터링 시스템에 서비스 등록
- **기능**:
  - 서비스 정보 등록
  - 헬스체크 URL 설정
  - 메트릭 수집 URL 설정

#### DeploymentMetrics
- **목적**: 배포 메트릭 수집 및 전송
- **기능**:
  - 배포 완료 메트릭
  - 시스템 메트릭 (컨테이너 수, 이미지 크기 등)

## 🔧 커스터마이징

### 1. 새로운 훅 추가

```python
# deploy_hooks/my_custom_hook.py
from deploy_hooks import DeployHook

class MyCustomHook(DeployHook):
    hook_type = 'pre'  # 또는 'post'
    
    @property
    def name(self) -> str:
        return "my_custom_hook"
    
    def execute(self) -> bool:
        # 커스텀 로직 구현
        self.logger.info("커스텀 훅 실행")
        return True
```

### 2. 조건부 실행

```python
def execute(self) -> bool:
    # 특정 환경에서만 실행
    if self.environment != 'production':
        self.logger.info("프로덕션이 아니므로 건너뜀")
        return True
    
    # 특정 서비스에서만 실행
    if self.service_kind != 'be':
        self.logger.info("백엔드가 아니므로 건너뜀")
        return True
    
    # 실제 로직 실행
    return self._do_something()
```

### 3. 환경 변수 활용

```python
def execute(self) -> bool:
    # 환경 변수로 동작 제어
    if os.environ.get('SKIP_CUSTOM_CHECK') == 'true':
        self.logger.info("SKIP_CUSTOM_CHECK가 설정되어 건너뜀")
        return True
    
    # 환경 변수로 설정값 조정
    timeout = int(os.environ.get('CUSTOM_TIMEOUT', '30'))
    max_retries = int(os.environ.get('CUSTOM_RETRIES', '3'))
    
    return self._do_something_with_config(timeout, max_retries)
```

## 🐛 디버깅

### 1. 로그 확인

```bash
# 디버그 모드로 실행
DEBUG_MODE=true python universal-makefile/scripts/deploy_hooks.py pre production be

# 특정 훅만 실행 (개발 중)
python -c "
from deploy_hooks import create_hook_manager
manager = create_hook_manager('production', 'be')
# 특정 훅만 추가하여 테스트
"
```

### 2. 환경 변수 확인

```python
def execute(self) -> bool:
    # 모든 환경 변수 출력 (디버깅용)
    self.logger.info("Environment variables:")
    for key, value in sorted(os.environ.items()):
        if 'PASSWORD' not in key and 'SECRET' not in key:
            self.logger.info(f"  {key}={value}")
    
    return True
```

### 3. 단계별 테스트

```bash
# 1. 훅 로드 테스트
python -c "from deploy_hooks import create_hook_manager; print('OK')"

# 2. 커스텀 훅 로드 테스트
python -c "
import sys, os
sys.path.append('deploy_hooks')
from custom_pre_deploy import CustomEnvironmentCheck
print('Custom hook loaded successfully')
"

# 3. 개별 훅 실행 테스트
python -c "
from deploy_hooks import create_hook_manager
manager = create_hook_manager('test', 'be')
hooks = manager.list_hooks()
print('Available hooks:', hooks)
"
```

## 📚 추가 리소스

- [배포 훅 시스템 문서](../docs/DEPLOY_HOOKS.md)
- [Universal Makefile README](../README.md)
- [GitHub Issues](https://github.com/jinwoo-j/universal-makefile/issues)

## 💡 팁

1. **점진적 도입**: 기존 시스템에서 한 번에 모든 훅을 적용하지 말고 단계적으로 도입
2. **환경별 테스트**: 개발 환경에서 충분히 테스트한 후 프로덕션 적용
3. **실패 처리**: 중요하지 않은 훅(알림, 메트릭 등)은 실패해도 배포를 중단하지 않도록 설계
4. **타임아웃 설정**: 모든 외부 호출에 적절한 타임아웃 설정
5. **로깅**: 충분한 로그를 남겨 문제 발생 시 디버깅을 용이하게 함

배포 훅 시스템을 통해 더 안전하고 자동화된 배포 프로세스를 구축하세요! 🚀