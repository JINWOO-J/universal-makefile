# 🪝 배포 훅 시스템 (Deploy Hooks System)

Universal Makefile System의 배포 훅 시스템은 배포 전후에 커스텀 로직을 실행할 수 있는 확장 가능한 플러그인 시스템입니다.

## 📋 목차

- [개요](#개요)
- [시스템 구조](#시스템-구조)
- [사용 방법](#사용-방법)
- [훅 타입](#훅-타입)
- [커스텀 훅 작성](#커스텀-훅-작성)
- [설정 기반 훅](#설정-기반-훅)
- [원격 훅](#원격-훅)
- [예제](#예제)
- [문제 해결](#문제-해결)

## 🎯 개요

배포 훅 시스템은 다음과 같은 기능을 제공합니다:

- **Pre-deploy 훅**: 배포 전 검증 및 준비 작업
- **Post-deploy 훅**: 배포 후 검증 및 알림 작업
- **플러그인 시스템**: 프로젝트별 커스텀 훅 추가
- **설정 기반**: YAML 설정으로 훅 관리
- **원격 실행**: URL에서 스크립트 다운로드 실행
- **보안**: 도메인 화이트리스트, 해시 검증 등

## 🏗️ 시스템 구조

```
universal-makefile/
├── scripts/
│   ├── deploy_hooks.py          # 메인 훅 시스템
│   ├── remote_hook_executor.py  # 원격 훅 실행기
│   ├── pre_deploy.py           # 기존 pre-deploy (훅 시스템 통합)
│   └── post_deploy.py          # 기존 post-deploy (훅 시스템 통합)
├── templates/
│   └── deploy-hooks.yml.template # 설정 파일 템플릿
└── docs/
    └── DEPLOY_HOOKS.md         # 이 문서

프로젝트 루트/
├── deploy_hooks/               # 커스텀 훅 디렉토리
│   ├── pre_deploy_hooks.py    # Pre-deploy 커스텀 훅
│   ├── post_deploy_hooks.py   # Post-deploy 커스텀 훅
│   └── custom_checks.py       # 기타 커스텀 훅
├── deploy-hooks.yml           # 훅 설정 파일
└── .env.runtime              # 런타임 환경 변수
```

## 🚀 사용 방법

### 1. 기본 사용법

```bash
# Pre-deploy 훅 실행
python universal-makefile/scripts/deploy_hooks.py pre production be

# Post-deploy 훅 실행
python universal-makefile/scripts/deploy_hooks.py post production be

# 등록된 훅 목록 확인
python universal-makefile/scripts/deploy_hooks.py pre production be --list
```

### 2. 기존 스크립트와 통합 사용

```bash
# 기존 pre_deploy.py에서 훅 시스템 사용
python universal-makefile/scripts/pre_deploy.py production be --use-hooks

# 기존 post_deploy.py에서 훅 시스템 사용
python universal-makefile/scripts/post_deploy.py production be --use-hooks
```

### 3. Makefile 통합

```makefile
# project.mk 또는 환경별 설정에 추가
DEPLOY_HOOKS_ENABLED ?= true

pre-deploy-hooks: ## 🪝 Pre-deploy 훅 실행
	@if [ "$(DEPLOY_HOOKS_ENABLED)" = "true" ]; then \
		python $(MAKEFILE_DIR)/scripts/deploy_hooks.py pre $(ENV) $(SERVICE_KIND); \
	fi

post-deploy-hooks: ## 🪝 Post-deploy 훅 실행
	@if [ "$(DEPLOY_HOOKS_ENABLED)" = "true" ]; then \
		python $(MAKEFILE_DIR)/scripts/deploy_hooks.py post $(ENV) $(SERVICE_KIND); \
	fi

# 배포 프로세스에 통합
deploy: pre-deploy-hooks build push post-deploy-hooks
```

## 🔧 훅 타입

### Pre-deploy 훅 (배포 전)

- **환경 변수 검증**: 필수 환경 변수 확인
- **Docker 환경 검사**: Docker 데몬 및 Compose 확인
- **디스크 공간 검사**: 충분한 디스크 공간 확인
- **네트워크 연결 검사**: 외부 서비스 연결 확인
- **서비스 의존성 검사**: 데이터베이스, Redis 등 확인
- **포트 가용성 검사**: 사용할 포트 확인
- **데이터베이스 마이그레이션**: 스키마 업데이트

### Post-deploy 훅 (배포 후)

- **컨테이너 상태 확인**: 모든 컨테이너 정상 실행 확인
- **서비스 응답 확인**: 헬스체크 엔드포인트 확인
- **데이터베이스 헬스 확인**: DB 연결 및 상태 확인
- **외부 의존성 확인**: 외부 API 연결 확인
- **로그 에러 확인**: 심각한 에러 패턴 검사
- **알림 전송**: Slack, 이메일 등 배포 완료 알림
- **모니터링 등록**: APM, 로그 수집 시스템 등록

## ✍️ 커스텀 훅 작성

### 1. 플러그인 방식 (권장)

```python
# deploy_hooks/custom_checks.py
from deploy_hooks import DeployHook

class CustomDatabaseCheck(DeployHook):
    """커스텀 데이터베이스 체크"""
    
    # 훅 타입 지정 (pre 또는 post)
    hook_type = 'pre'
    
    @property
    def name(self) -> str:
        return "custom_database_check"
    
    @property
    def description(self) -> str:
        return "프로젝트별 데이터베이스 연결 및 스키마 검증"
    
    def execute(self) -> bool:
        """훅 실행 로직"""
        try:
            self.logger.info("커스텀 데이터베이스 체크 시작")
            
            # 환경별 다른 로직
            if self.environment == 'production':
                return self._check_production_db()
            else:
                return self._check_development_db()
                
        except Exception as e:
            self.logger.error(f"커스텀 DB 체크 실패: {str(e)}")
            return False
    
    def _check_production_db(self) -> bool:
        """프로덕션 DB 체크"""
        # 프로덕션 전용 검증 로직
        self.logger.info("프로덕션 데이터베이스 검증")
        return True
    
    def _check_development_db(self) -> bool:
        """개발 DB 체크"""
        # 개발 환경 검증 로직
        self.logger.info("개발 데이터베이스 검증")
        return True


class SlackNotificationHook(DeployHook):
    """Slack 알림 훅"""
    
    hook_type = 'post'
    
    @property
    def name(self) -> str:
        return "slack_notification"
    
    def execute(self) -> bool:
        """Slack 알림 전송"""
        try:
            import requests
            
            webhook_url = os.environ.get('SLACK_WEBHOOK_URL')
            if not webhook_url:
                self.logger.warning("SLACK_WEBHOOK_URL이 설정되지 않음")
                return True
            
            message = {
                "text": f"🚀 배포 완료: {self.service_kind} ({self.environment})",
                "channel": "#deployments",
                "username": "Deploy Bot"
            }
            
            response = requests.post(webhook_url, json=message, timeout=10)
            response.raise_for_status()
            
            self.logger.info("Slack 알림 전송 완료")
            return True
            
        except Exception as e:
            self.logger.error(f"Slack 알림 실패: {str(e)}")
            return False  # 알림 실패는 배포를 중단하지 않음
```

### 2. 조건부 실행

```python
class ConditionalHook(DeployHook):
    """조건부 실행 훅"""
    
    hook_type = 'pre'
    
    @property
    def name(self) -> str:
        return "conditional_check"
    
    def execute(self) -> bool:
        # 백엔드 서비스이고 프로덕션 환경일 때만 실행
        if self.service_kind == 'be' and self.environment == 'production':
            return self._run_production_backend_check()
        
        # 조건에 맞지 않으면 성공으로 처리
        self.logger.info("조건에 맞지 않아 건너뜀")
        return True
    
    def _run_production_backend_check(self) -> bool:
        # 실제 검사 로직
        return True
```

## ⚙️ 설정 기반 훅

### 1. 설정 파일 생성

```bash
# 템플릿 복사
cp universal-makefile/templates/deploy-hooks.yml.template deploy-hooks.yml
```

### 2. 설정 파일 커스터마이징

```yaml
# deploy-hooks.yml
pre_deploy:
  # 기본 훅 활성화/비활성화
  - name: "environment_check"
    type: "builtin"
    enabled: true
    config:
      required_vars:
        - "DATABASE_URL"
        - "REDIS_URL"
        - "API_KEY"

  # 커스텀 스크립트 실행
  - name: "migration_check"
    type: "script"
    enabled: true
    config:
      script_path: "./scripts/check_migrations.sh"
      timeout: 120
      args: ["${ENVIRONMENT}"]

  # 외부 API 호출
  - name: "deployment_webhook"
    type: "webhook"
    enabled: true
    config:
      url: "https://api.company.com/deployments/start"
      method: "POST"
      headers:
        Authorization: "Bearer ${DEPLOY_API_TOKEN}"
      payload:
        environment: "${ENVIRONMENT}"
        service: "${SERVICE_KIND}"
        version: "${VERSION}"

post_deploy:
  # 헬스체크 URL 커스터마이징
  - name: "service_response_check"
    type: "builtin"
    enabled: true
    config:
      health_urls:
        fe:
          - "https://app.company.com/health"
        be:
          - "https://api.company.com/health"
          - "https://api.company.com/status"

  # 성능 테스트
  - name: "performance_test"
    type: "script"
    enabled: false  # 필요시에만 활성화
    config:
      script_path: "./scripts/performance_test.py"
      timeout: 600
      args: ["${ENVIRONMENT}", "--threshold=500ms"]

# 환경별 설정 오버라이드
environment_overrides:
  production:
    pre_deploy:
      - name: "migration_check"
        config:
          timeout: 300  # 프로덕션에서는 더 긴 타임아웃
    
    post_deploy:
      - name: "performance_test"
        enabled: true  # 프로덕션에서만 성능 테스트 실행
```

## 🌐 원격 훅

### 1. 기본 사용법

```bash
# GitHub에서 스크립트 다운로드 실행
python universal-makefile/scripts/remote_hook_executor.py \
  production be \
  "https://raw.githubusercontent.com/company/deploy-scripts/main/pre_deploy.sh" \
  --type bash \
  --args production be

# 해시 검증과 함께 실행
python universal-makefile/scripts/remote_hook_executor.py \
  production be \
  "https://gist.githubusercontent.com/user/abc123/raw/script.py" \
  --type python \
  --hash "sha256:abc123..." \
  --args production be
```

### 2. 환경 변수 설정

```bash
# 허용된 도메인 설정
export ALLOWED_HOOK_DOMAINS="raw.githubusercontent.com,company-scripts.s3.amazonaws.com"

# 인증 토큰 설정
export HOOK_AUTH_TOKEN="ghp_xxxxxxxxxxxx"

# 캐시 TTL 설정 (초)
export HOOK_CACHE_TTL="3600"

# 최대 스크립트 크기 (바이트)
export MAX_SCRIPT_SIZE="2097152"  # 2MB
```

### 3. 보안 설정

```bash
# SSL 검증 활성화 (기본값)
export VERIFY_SSL="true"

# 허용된 도메인만 접근 가능
export ALLOWED_HOOK_DOMAINS="trusted-domain1.com,trusted-domain2.com"

# 스크립트 해시 검증 (권장)
# SHA256 해시를 미리 계산하여 검증
sha256sum script.sh  # 해시 계산
```

## 📚 예제

### 1. 간단한 커스텀 훅

```python
# deploy_hooks/simple_check.py
from deploy_hooks import DeployHook
import os

class EnvironmentFileCheck(DeployHook):
    hook_type = 'pre'
    
    @property
    def name(self) -> str:
        return "environment_file_check"
    
    def execute(self) -> bool:
        """환경별 설정 파일 존재 확인"""
        required_files = [
            f'.env.{self.environment}',
            f'config/{self.environment}.yml'
        ]
        
        for file_path in required_files:
            if not os.path.exists(file_path):
                self.logger.error(f"필수 파일 없음: {file_path}")
                return False
            
            self.logger.info(f"파일 확인: {file_path}")
        
        return True
```

### 2. 외부 서비스 연동

```python
# deploy_hooks/external_service.py
from deploy_hooks import DeployHook
import requests

class ExternalServiceRegistration(DeployHook):
    hook_type = 'post'
    
    @property
    def name(self) -> str:
        return "external_service_registration"
    
    def execute(self) -> bool:
        """외부 모니터링 서비스에 등록"""
        try:
            monitoring_url = os.environ.get('MONITORING_API_URL')
            api_key = os.environ.get('MONITORING_API_KEY')
            
            if not monitoring_url or not api_key:
                self.logger.warning("모니터링 API 설정 없음")
                return True
            
            service_info = {
                'name': f"{self.service_kind}-{self.environment}",
                'environment': self.environment,
                'health_url': f"http://localhost:8000/health",
                'version': os.environ.get('VERSION', 'unknown')
            }
            
            response = requests.post(
                f"{monitoring_url}/services",
                json=service_info,
                headers={'Authorization': f'Bearer {api_key}'},
                timeout=30
            )
            
            response.raise_for_status()
            self.logger.info("모니터링 서비스 등록 완료")
            return True
            
        except Exception as e:
            self.logger.error(f"모니터링 서비스 등록 실패: {str(e)}")
            return False
```

### 3. 데이터베이스 마이그레이션 훅

```python
# deploy_hooks/database_migration.py
from deploy_hooks import DeployHook
import subprocess

class DatabaseMigrationHook(DeployHook):
    hook_type = 'pre'
    
    @property
    def name(self) -> str:
        return "database_migration"
    
    def execute(self) -> bool:
        """데이터베이스 마이그레이션 실행"""
        if self.service_kind != 'be':
            self.logger.info("백엔드가 아니므로 마이그레이션 건너뜀")
            return True
        
        try:
            # 마이그레이션 상태 확인
            if not self._check_migration_needed():
                self.logger.info("마이그레이션이 필요하지 않음")
                return True
            
            # 백업 생성 (프로덕션만)
            if self.environment == 'production':
                if not self._create_backup():
                    return False
            
            # 마이그레이션 실행
            return self._run_migration()
            
        except Exception as e:
            self.logger.error(f"마이그레이션 실패: {str(e)}")
            return False
    
    def _check_migration_needed(self) -> bool:
        """마이그레이션 필요 여부 확인"""
        # Django 예시
        result = subprocess.run(
            ['python', 'manage.py', 'showmigrations', '--plan'],
            capture_output=True,
            text=True
        )
        
        return '[ ]' in result.stdout  # 미적용 마이그레이션 있음
    
    def _create_backup(self) -> bool:
        """데이터베이스 백업 생성"""
        self.logger.info("데이터베이스 백업 생성 중...")
        # 백업 로직 구현
        return True
    
    def _run_migration(self) -> bool:
        """마이그레이션 실행"""
        self.logger.info("데이터베이스 마이그레이션 실행 중...")
        
        result = subprocess.run(
            ['python', 'manage.py', 'migrate'],
            capture_output=True,
            text=True,
            timeout=300
        )
        
        if result.returncode == 0:
            self.logger.info("마이그레이션 완료")
            return True
        else:
            self.logger.error(f"마이그레이션 실패: {result.stderr}")
            return False
```

### 4. Makefile 통합 예제

```makefile
# project.mk에 추가
DEPLOY_HOOKS_ENABLED ?= true
HOOK_ENVIRONMENT ?= $(ENV)
HOOK_SERVICE_KIND ?= $(SERVICE_KIND)

# 훅 실행 타겟들
.PHONY: pre-deploy-hooks post-deploy-hooks deploy-with-hooks

pre-deploy-hooks: ## 🪝 Pre-deploy 훅 실행
	@if [ "$(DEPLOY_HOOKS_ENABLED)" = "true" ]; then \
		echo "$(CYAN)🪝 Pre-deploy 훅 실행 중...$(RESET)"; \
		python $(MAKEFILE_DIR)/scripts/deploy_hooks.py pre $(HOOK_ENVIRONMENT) $(HOOK_SERVICE_KIND) || exit 1; \
		echo "$(GREEN)✓ Pre-deploy 훅 완료$(RESET)"; \
	else \
		echo "$(YELLOW)⚠ Deploy hooks disabled$(RESET)"; \
	fi

post-deploy-hooks: ## 🪝 Post-deploy 훅 실행
	@if [ "$(DEPLOY_HOOKS_ENABLED)" = "true" ]; then \
		echo "$(CYAN)🪝 Post-deploy 훅 실행 중...$(RESET)"; \
		python $(MAKEFILE_DIR)/scripts/deploy_hooks.py post $(HOOK_ENVIRONMENT) $(HOOK_SERVICE_KIND) || exit 1; \
		echo "$(GREEN)✓ Post-deploy 훅 완료$(RESET)"; \
	else \
		echo "$(YELLOW)⚠ Deploy hooks disabled$(RESET)"; \
	fi

# 훅이 포함된 배포
deploy-with-hooks: pre-deploy-hooks build push post-deploy-hooks ## 🚀 훅을 포함한 전체 배포

# 기존 배포 타겟에 훅 추가
deploy: deploy-with-hooks

# 훅 목록 확인
list-hooks: ## 📋 등록된 훅 목록 표시
	@echo "$(CYAN)Pre-deploy hooks:$(RESET)"
	@python $(MAKEFILE_DIR)/scripts/deploy_hooks.py pre $(HOOK_ENVIRONMENT) $(HOOK_SERVICE_KIND) --list | grep "Pre-deploy" || true
	@echo "$(CYAN)Post-deploy hooks:$(RESET)"
	@python $(MAKEFILE_DIR)/scripts/deploy_hooks.py post $(HOOK_ENVIRONMENT) $(HOOK_SERVICE_KIND) --list | grep "Post-deploy" || true

# 훅 테스트
test-hooks: ## 🧪 훅 테스트 실행
	@echo "$(CYAN)🧪 Pre-deploy 훅 테스트$(RESET)"
	@HOOK_ENVIRONMENT=test python $(MAKEFILE_DIR)/scripts/deploy_hooks.py pre test $(HOOK_SERVICE_KIND)
	@echo "$(CYAN)🧪 Post-deploy 훅 테스트$(RESET)"
	@HOOK_ENVIRONMENT=test python $(MAKEFILE_DIR)/scripts/deploy_hooks.py post test $(HOOK_SERVICE_KIND)
```

## 🔧 문제 해결

### 1. 일반적인 문제들

#### 훅이 실행되지 않음
```bash
# 훅 목록 확인
python universal-makefile/scripts/deploy_hooks.py pre production be --list

# 디버그 모드로 실행
DEBUG_MODE=true python universal-makefile/scripts/deploy_hooks.py pre production be

# 로그 확인
tail -f /tmp/deploy_hooks.log
```

#### 커스텀 훅을 찾을 수 없음
```bash
# deploy_hooks 디렉토리 확인
ls -la deploy_hooks/

# Python 경로 확인
python -c "import sys; print('\n'.join(sys.path))"

# 모듈 임포트 테스트
python -c "from deploy_hooks import DeployHook; print('OK')"
```

#### 원격 훅 다운로드 실패
```bash
# 허용된 도메인 확인
echo $ALLOWED_HOOK_DOMAINS

# 네트워크 연결 테스트
curl -I https://raw.githubusercontent.com/user/repo/main/script.sh

# SSL 검증 비활성화 (테스트용)
VERIFY_SSL=false python universal-makefile/scripts/remote_hook_executor.py ...
```

### 2. 디버깅 팁

#### 로그 레벨 조정
```python
# deploy_hooks/debug_hook.py
from deploy_hooks import DeployHook
import logging

class DebugHook(DeployHook):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        # 로그 레벨을 DEBUG로 설정
        self.logger.logger.setLevel(logging.DEBUG)
    
    # ... 나머지 구현
```

#### 환경 변수 확인
```python
def execute(self) -> bool:
    # 모든 환경 변수 출력
    import os
    self.logger.info("Environment variables:")
    for key, value in sorted(os.environ.items()):
        if 'PASSWORD' not in key and 'SECRET' not in key:
            self.logger.info(f"  {key}={value}")
    
    return True
```

### 3. 성능 최적화

#### 훅 실행 시간 측정
```python
import time
from functools import wraps

def measure_time(func):
    @wraps(func)
    def wrapper(self, *args, **kwargs):
        start_time = time.time()
        result = func(self, *args, **kwargs)
        end_time = time.time()
        
        self.logger.info(f"{self.name} 실행 시간: {end_time - start_time:.2f}초")
        return result
    return wrapper

class TimedHook(DeployHook):
    @measure_time
    def execute(self) -> bool:
        # 훅 로직
        return True
```

#### 병렬 실행 (고급)
```python
from concurrent.futures import ThreadPoolExecutor
import threading

class ParallelHookManager(DeployHookManager):
    def _run_hooks(self, hooks, hook_type):
        """훅을 병렬로 실행"""
        with ThreadPoolExecutor(max_workers=3) as executor:
            futures = {executor.submit(hook.execute): hook for hook in hooks}
            
            failed_hooks = []
            for future in futures:
                hook = futures[future]
                try:
                    if not future.result():
                        failed_hooks.append(hook.name)
                except Exception as e:
                    self.logger.error(f"훅 실행 중 예외 ({hook.name}): {str(e)}")
                    failed_hooks.append(hook.name)
            
            return len(failed_hooks) == 0
```

## 📝 모범 사례

### 1. 훅 설계 원칙

- **단일 책임**: 각 훅은 하나의 명확한 목적을 가져야 함
- **멱등성**: 여러 번 실행해도 같은 결과를 보장
- **빠른 실패**: 문제가 있으면 즉시 실패하고 명확한 에러 메시지 제공
- **로깅**: 충분한 로그를 남겨 디버깅을 용이하게 함
- **타임아웃**: 무한 대기를 방지하기 위한 적절한 타임아웃 설정

### 2. 보안 고려사항

- **입력 검증**: 모든 외부 입력에 대한 검증
- **권한 최소화**: 필요한 최소한의 권한만 사용
- **비밀 정보 보호**: 로그에 비밀번호나 토큰 출력 금지
- **원격 스크립트**: 신뢰할 수 있는 소스에서만 다운로드
- **해시 검증**: 원격 스크립트의 무결성 검증

### 3. 성능 고려사항

- **캐싱**: 반복적인 작업은 캐싱 활용
- **병렬 처리**: 독립적인 훅들은 병렬 실행 고려
- **리소스 정리**: 사용한 리소스는 반드시 정리
- **타임아웃**: 적절한 타임아웃으로 무한 대기 방지

---

## 📞 지원 및 기여

- **이슈 리포트**: [GitHub Issues](https://github.com/jinwoo-j/universal-makefile/issues)
- **기능 요청**: [GitHub Discussions](https://github.com/jinwoo-j/universal-makefile/discussions)
- **기여 가이드**: [CONTRIBUTING.md](../CONTRIBUTING.md)

배포 훅 시스템을 통해 더 안전하고 자동화된 배포 프로세스를 구축하세요! 🚀