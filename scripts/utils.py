#!/usr/bin/env python3
"""
공통 유틸리티 함수
AWS SSM 클라이언트 관리, 로깅, 에러 처리 등을 제공합니다.
"""

import os
import sys
import logging
import time
from typing import Dict, List, Optional
from datetime import datetime

try:
    import boto3
    from botocore.exceptions import ClientError, NoCredentialsError
except ImportError:
    print("boto3가 설치되지 않았습니다. pip install boto3를 실행하세요.")
    sys.exit(1)

try:
    import requests
except ImportError:
    print("requests가 설치되지 않았습니다. pip install requests를 실행하세요.")
    sys.exit(1)


# 공통 상수 및 설정
class Config:
    """공통 설정 및 상수"""
    
    # AWS 관련 설정
    DEFAULT_AWS_REGION = 'us-east-1'
    SSM_PARAMETER_PREFIX = '/app'
    
    # Docker 관련 설정
    DOCKER_REGISTRY = os.environ.get('DOCKER_REGISTRY', 'docker.io')
    DOCKER_REPO_HUB = os.environ.get('DOCKER_REPO_HUB', '42tape')
    
    # 배포 관련 설정
    DEPLOYMENT_TIMEOUT = int(os.environ.get('DEPLOYMENT_TIMEOUT', '300'))  # 5분
    HEALTH_CHECK_TIMEOUT = int(os.environ.get('HEALTH_CHECK_TIMEOUT', '30'))  # 30초
    HEALTH_CHECK_RETRIES = int(os.environ.get('HEALTH_CHECK_RETRIES', '3'))
    
    # 파일 경로 설정
    RELEASES_DIR = 'RELEASES'
    CONFIG_DIR = 'config'
    SCRIPTS_DIR = 'scripts'
    DOCKER_DIR = 'docker'
    
    # 로그 레벨 설정
    LOG_LEVEL = os.environ.get('LOG_LEVEL', 'INFO').upper()
    
    # Slack 설정
    SLACK_WEBHOOK_URL = os.environ.get('SLACK_WEBHOOK_URL')
    
    # 지원되는 환경 목록
    SUPPORTED_ENVIRONMENTS = ['prod', 'staging', 'dev']
    
    # 지원되는 서비스 종류
    SUPPORTED_SERVICE_KINDS = ['fe', 'be']
    
    @classmethod
    def validate_environment(cls, environment: str) -> bool:
        """환경 유효성 검증"""
        return environment in cls.SUPPORTED_ENVIRONMENTS
    
    @classmethod
    def validate_service_kind(cls, service_kind: str) -> bool:
        """서비스 종류 유효성 검증"""
        return service_kind in cls.SUPPORTED_SERVICE_KINDS
    
    @classmethod
    def get_ssm_path(cls, environment: str) -> str:
        """환경별 SSM 경로 반환"""
        return f"{cls.SSM_PARAMETER_PREFIX}/{environment}"
    
    @classmethod
    def get_config_path(cls, environment: str) -> str:
        """환경별 설정 파일 경로 반환"""
        return os.path.join(cls.CONFIG_DIR, environment, 'app.env.public')


class CICDError(Exception):
    """CI/CD 관련 커스텀 예외"""
    pass


class SSMError(CICDError):
    """SSM 관련 예외"""
    pass


class DeploymentError(CICDError):
    """배포 관련 예외"""
    pass


class HealthCheckError(CICDError):
    """헬스 체크 관련 예외"""
    pass


class Logger:
    """로깅 설정 및 관리"""
    
    _loggers = {}  # 로거 인스턴스 캐시
    
    def __init__(self, name: str = "cicd-runner", level: Optional[str] = None):
        self.name = name
        self.level = level or Config.LOG_LEVEL
        
        # 캐시된 로거가 있으면 재사용
        if name in self._loggers:
            self.logger = self._loggers[name]
        else:
            self.logger = self._create_logger(name, self.level)
            self._loggers[name] = self.logger
    
    def _create_logger(self, name: str, level: str) -> logging.Logger:
        """로거 생성"""
        logger = logging.getLogger(name)
        logger.setLevel(getattr(logging, level.upper()))
        
        # 핸들러가 이미 있으면 추가하지 않음 (중복 방지)
        if not logger.handlers:
            # 콘솔 핸들러
            console_handler = logging.StreamHandler(sys.stdout)
            console_formatter = logging.Formatter(
                '%(asctime)s - %(name)s - %(levelname)s - %(message)s',
                datefmt='%Y-%m-%d %H:%M:%S'
            )
            console_handler.setFormatter(console_formatter)
            logger.addHandler(console_handler)
            
            # 파일 핸들러 (선택적)
            log_file = os.environ.get('LOG_FILE')
            if log_file:
                try:
                    file_handler = logging.FileHandler(log_file)
                    file_formatter = logging.Formatter(
                        '%(asctime)s - %(name)s - %(levelname)s - %(funcName)s:%(lineno)d - %(message)s',
                        datefmt='%Y-%m-%d %H:%M:%S'
                    )
                    file_handler.setFormatter(file_formatter)
                    logger.addHandler(file_handler)
                except Exception as e:
                    logger.warning(f"파일 로그 핸들러 생성 실패: {e}")
        
        return logger
    
    def info(self, message: str) -> None:
        """정보 로그"""
        self.logger.info(message)
    
    def error(self, message: str, exc_info: bool = False) -> None:
        """에러 로그"""
        self.logger.error(message, exc_info=exc_info)
    
    def warning(self, message: str) -> None:
        """경고 로그"""
        self.logger.warning(message)
    
    def debug(self, message: str) -> None:
        """디버그 로그"""
        self.logger.debug(message)
    
    def critical(self, message: str) -> None:
        """치명적 에러 로그"""
        self.logger.critical(message)
    
    @classmethod
    def get_logger(cls, name: str, level: Optional[str] = None) -> 'Logger':
        """로거 인스턴스 반환 (팩토리 메서드)"""
        return cls(name, level)


class SSMClient:
    """AWS SSM Parameter Store 클라이언트"""
    
    def __init__(self, region: Optional[str] = None):
        self.logger = Logger.get_logger("SSMClient")
        self.region = region or os.environ.get('AWS_DEFAULT_REGION', Config.DEFAULT_AWS_REGION)
        
        try:
            self.client = boto3.client('ssm', region_name=self.region)
            self.logger.info(f"SSM 클라이언트 초기화 완료 (리전: {self.region})")
        except NoCredentialsError as e:
            error_msg = "AWS 자격 증명을 찾을 수 없습니다. IAM 역할 또는 자격 증명을 확인하세요."
            self.logger.error(error_msg)
            raise SSMError(error_msg) from e
        except Exception as e:
            error_msg = f"SSM 클라이언트 초기화 실패: {str(e)}"
            self.logger.error(error_msg)
            raise SSMError(error_msg) from e
    
    def get_parameter(self, name: str, decrypt: bool = True) -> Optional[str]:
        """단일 파라미터 조회"""
        try:
            response = self.client.get_parameter(
                Name=name,
                WithDecryption=decrypt
            )
            value = response['Parameter']['Value']
            self.logger.debug(f"파라미터 조회 성공: {name}")
            return value
        except ClientError as e:
            error_code = e.response['Error']['Code']
            if error_code == 'ParameterNotFound':
                self.logger.warning(f"파라미터를 찾을 수 없습니다: {name}")
                return None
            elif error_code == 'AccessDenied':
                error_msg = f"파라미터 접근 권한이 없습니다: {name}"
                self.logger.error(error_msg)
                raise SSMError(error_msg) from e
            else:
                error_msg = f"파라미터 조회 실패 ({name}): {str(e)}"
                self.logger.error(error_msg)
                raise SSMError(error_msg) from e
        except Exception as e:
            error_msg = f"파라미터 조회 중 예외 발생 ({name}): {str(e)}"
            self.logger.error(error_msg, exc_info=True)
            raise SSMError(error_msg) from e
    
    def get_parameters_by_path(self, path: str, decrypt: bool = True) -> Dict[str, str]:
        """경로별 파라미터 일괄 조회"""
        parameters = {}
        next_token = None
        
        try:
            while True:
                kwargs = {
                    'Path': path,
                    'Recursive': True,
                    'WithDecryption': decrypt,
                    'MaxResults': 10
                }
                
                if next_token:
                    kwargs['NextToken'] = next_token
                
                response = self.client.get_parameters_by_path(**kwargs)
                
                for param in response['Parameters']:
                    # 경로에서 키 이름만 추출 (/app/prod/DB_PASSWORD -> DB_PASSWORD)
                    key = param['Name'].split('/')[-1]
                    parameters[key] = param['Value']
                
                next_token = response.get('NextToken')
                if not next_token:
                    break
            
            self.logger.info(f"경로별 파라미터 조회 완료: {path} ({len(parameters)}개)")
            return parameters
            
        except ClientError as e:
            error_code = e.response['Error']['Code']
            if error_code == 'AccessDenied':
                error_msg = f"경로 접근 권한이 없습니다: {path}"
                self.logger.error(error_msg)
                raise SSMError(error_msg) from e
            else:
                error_msg = f"경로별 파라미터 조회 실패 ({path}): {str(e)}"
                self.logger.error(error_msg)
                raise SSMError(error_msg) from e
        except Exception as e:
            error_msg = f"경로별 파라미터 조회 중 예외 발생 ({path}): {str(e)}"
            self.logger.error(error_msg, exc_info=True)
            raise SSMError(error_msg) from e
    
    def get_environment_secrets(self, environment: str) -> Dict[str, str]:
        """환경별 비밀 정보 조회"""
        if not Config.validate_environment(environment):
            raise SSMError(f"지원되지 않는 환경입니다: {environment}")
        
        path = Config.get_ssm_path(environment)
        return self.get_parameters_by_path(path, decrypt=True)


class SlackNotifier:
    """Slack 알림 전송"""
    
    def __init__(self, webhook_url: Optional[str] = None):
        self.logger = Logger.get_logger("SlackNotifier")
        self.webhook_url = webhook_url or Config.SLACK_WEBHOOK_URL
        
        if not self.webhook_url:
            self.logger.warning("Slack 웹훅 URL이 설정되지 않았습니다.")
    
    def send_message(self, message: str, color: str = "good") -> bool:
        """Slack 메시지 전송"""
        if not self.webhook_url:
            self.logger.warning("Slack 웹훅 URL이 없어 알림을 전송할 수 없습니다.")
            return False
        
        try:
            payload = {
                "attachments": [
                    {
                        "color": color,
                        "text": self._mask_secrets(message),
                        "ts": int(time.time())
                    }
                ]
            }
            
            response = requests.post(
                self.webhook_url,
                json=payload,
                timeout=10
            )
            
            if response.status_code == 200:
                self.logger.info("Slack 알림 전송 성공")
                return True
            else:
                self.logger.error(f"Slack 알림 전송 실패: {response.status_code}")
                return False
                
        except Exception as e:
            self.logger.error(f"Slack 알림 전송 중 예외 발생: {str(e)}")
            return False
    
    def send_deployment_success(self, deployment_info: Dict[str, str]) -> bool:
        """배포 성공 알림"""
        message = f"""
🚀 배포 성공!

• 환경: {deployment_info.get('environment', 'N/A')}
• 서비스: {deployment_info.get('service_kind', 'N/A')}
• 버전: {deployment_info.get('version', 'N/A')}
• 소스: {deployment_info.get('source_repo', 'N/A')}
• 시간: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
        """.strip()
        
        return self.send_message(message, "good")
    
    def send_deployment_failure(self, deployment_info: Dict[str, str], error: str) -> bool:
        """배포 실패 알림"""
        message = f"""
❌ 배포 실패!

• 환경: {deployment_info.get('environment', 'N/A')}
• 서비스: {deployment_info.get('service_kind', 'N/A')}
• 버전: {deployment_info.get('version', 'N/A')}
• 소스: {deployment_info.get('source_repo', 'N/A')}
• 에러: {self._mask_secrets(error)}
• 시간: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
        """.strip()
        
        return self.send_message(message, "danger")
    
    def send_rollback_notification(self, deployment_info: Dict[str, str], rollback_digest: str) -> bool:
        """롤백 알림"""
        message = f"""
🔄 자동 롤백 실행!

• 환경: {deployment_info.get('environment', 'N/A')}
• 서비스: {deployment_info.get('service_kind', 'N/A')}
• 롤백 다이제스트: {rollback_digest[:12]}...
• 시간: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
        """.strip()
        
        return self.send_message(message, "warning")
    
    def _mask_secrets(self, text: str) -> str:
        """민감한 정보 마스킹"""
        # 일반적인 비밀 패턴들을 마스킹
        import re
        
        # 패스워드, 토큰, 키 등의 패턴
        patterns = [
            r'(password["\s]*[:=]["\s]*)([^"\s]+)',
            r'(token["\s]*[:=]["\s]*)([^"\s]+)',
            r'(key["\s]*[:=]["\s]*)([^"\s]+)',
            r'(secret["\s]*[:=]["\s]*)([^"\s]+)',
            r'(webhook["\s]*[:=]["\s]*)([^"\s]+)',
        ]
        
        masked_text = text
        for pattern in patterns:
            masked_text = re.sub(pattern, r'\1***MASKED***', masked_text, flags=re.IGNORECASE)
        
        return masked_text


class HealthChecker:
    """헬스 체크 유틸리티"""
    
    def __init__(self):
        self.logger = Logger.get_logger("HealthChecker")
    
    def check_url(self, url: str, timeout: Optional[int] = None, expected_status: int = 200) -> bool:
        """URL 헬스 체크"""
        timeout = timeout or Config.HEALTH_CHECK_TIMEOUT
        
        try:
            response = requests.get(url, timeout=timeout)
            if response.status_code == expected_status:
                self.logger.info(f"헬스 체크 성공: {url}")
                return True
            else:
                self.logger.error(f"헬스 체크 실패: {url} (상태코드: {response.status_code})")
                return False
        except requests.exceptions.Timeout:
            self.logger.error(f"헬스 체크 타임아웃: {url} ({timeout}초)")
            return False
        except requests.exceptions.ConnectionError:
            self.logger.error(f"헬스 체크 연결 실패: {url}")
            return False
        except Exception as e:
            self.logger.error(f"헬스 체크 중 예외 발생: {url} - {str(e)}")
            return False
    
    def check_multiple_urls(self, urls: List[str], timeout: Optional[int] = None) -> bool:
        """여러 URL 헬스 체크"""
        if not urls:
            self.logger.warning("헬스 체크할 URL이 없습니다.")
            return True
        
        all_healthy = True
        failed_urls = []
        
        for url in urls:
            if not self.check_url(url, timeout):
                all_healthy = False
                failed_urls.append(url)
        
        if failed_urls:
            self.logger.error(f"헬스 체크 실패한 URL들: {', '.join(failed_urls)}")
        
        return all_healthy
    
    def check_with_retry(self, url: str, retries: Optional[int] = None, timeout: Optional[int] = None) -> bool:
        """재시도를 포함한 헬스 체크"""
        retries = retries or Config.HEALTH_CHECK_RETRIES
        
        for attempt in range(retries):
            if self.check_url(url, timeout):
                return True
            
            if attempt < retries - 1:
                wait_time = 2 ** attempt  # 지수 백오프
                self.logger.info(f"헬스 체크 재시도 {attempt + 1}/{retries} (대기: {wait_time}초)")
                time.sleep(wait_time)
        
        raise HealthCheckError(f"헬스 체크 최대 재시도 횟수 초과: {url}")


class RetryHelper:
    """재시도 헬퍼"""
    
    def __init__(self):
        self.logger = Logger.get_logger("RetryHelper")
    
    def retry_with_backoff(self, func, max_retries: int = 3, backoff_factor: float = 1.0, 
                          exceptions: tuple = (Exception,)):
        """지수 백오프를 사용한 재시도"""
        for attempt in range(max_retries):
            try:
                return func()
            except exceptions as e:
                if attempt == max_retries - 1:
                    self.logger.error(f"최대 재시도 횟수 초과: {str(e)}")
                    raise
                
                wait_time = backoff_factor * (2 ** attempt)
                self.logger.warning(f"재시도 {attempt + 1}/{max_retries} (대기: {wait_time}초): {str(e)}")
                time.sleep(wait_time)
            except Exception as e:
                # 재시도하지 않을 예외는 즉시 발생
                self.logger.error(f"재시도하지 않는 예외 발생: {str(e)}")
                raise
    
    @staticmethod
    def retry_with_backoff_static(func, max_retries: int = 3, backoff_factor: float = 1.0):
        """정적 메서드 버전 (하위 호환성)"""
        helper = RetryHelper()
        return helper.retry_with_backoff(func, max_retries, backoff_factor)


def load_env_file(file_path: str) -> Dict[str, str]:
    """환경 파일 로드"""
    logger = Logger.get_logger("utils")
    env_vars = {}
    
    if not os.path.exists(file_path):
        logger.warning(f"환경 파일이 존재하지 않습니다: {file_path}")
        return env_vars
    
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            line_number = 0
            for line in f:
                line_number += 1
                line = line.strip()
                
                # 빈 줄이나 주석 건너뛰기
                if not line or line.startswith('#'):
                    continue
                
                # = 기호가 없는 줄 건너뛰기
                if '=' not in line:
                    logger.warning(f"잘못된 형식의 줄 건너뛰기 ({file_path}:{line_number}): {line}")
                    continue
                
                # 키=값 분리
                key, value = line.split('=', 1)
                key = key.strip()
                value = value.strip().strip('"\'')
                
                if not key:
                    logger.warning(f"빈 키 건너뛰기 ({file_path}:{line_number}): {line}")
                    continue
                
                env_vars[key] = value
        
        logger.info(f"환경 파일 로드 완료: {file_path} ({len(env_vars)}개 변수)")
        return env_vars
        
    except Exception as e:
        error_msg = f"환경 파일 로드 실패: {file_path} - {str(e)}"
        logger.error(error_msg, exc_info=True)
        raise CICDError(error_msg) from e


def get_current_timestamp() -> str:
    """현재 타임스탬프 반환 (배포 ID용)"""
    return datetime.now().strftime('%Y%m%d-%H%M%S')


def validate_environment_variables(required_vars: List[str]) -> bool:
    """필수 환경 변수 검증"""
    logger = Logger.get_logger("utils")
    missing_vars = []
    empty_vars = []
    
    for var in required_vars:
        value = os.environ.get(var)
        if value is None:
            missing_vars.append(var)
        elif not value.strip():
            empty_vars.append(var)
    
    if missing_vars:
        logger.error(f"필수 환경 변수가 설정되지 않았습니다: {', '.join(missing_vars)}")
    
    if empty_vars:
        logger.error(f"필수 환경 변수가 비어있습니다: {', '.join(empty_vars)}")
    
    if missing_vars or empty_vars:
        return False
    
    logger.info(f"모든 필수 환경 변수가 설정되었습니다 ({len(required_vars)}개)")
    return True


def create_directory_if_not_exists(directory: str) -> None:
    """디렉토리가 없으면 생성"""
    logger = Logger.get_logger("utils")
    
    if not os.path.exists(directory):
        try:
            os.makedirs(directory, exist_ok=True)
            logger.info(f"디렉토리 생성: {directory}")
        except Exception as e:
            error_msg = f"디렉토리 생성 실패: {directory} - {str(e)}"
            logger.error(error_msg)
            raise CICDError(error_msg) from e
    else:
        logger.debug(f"디렉토리가 이미 존재합니다: {directory}")


def write_file_with_permissions(file_path: str, content: str, permissions: int = 0o600) -> None:
    """파일을 특정 권한으로 작성"""
    logger = Logger.get_logger("utils")
    
    try:
        # 디렉토리 생성
        directory = os.path.dirname(file_path)
        if directory:
            create_directory_if_not_exists(directory)
        
        # 파일 작성
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(content)
        
        # 권한 설정
        os.chmod(file_path, permissions)
        
        logger.info(f"파일 작성 완료: {file_path} (권한: {oct(permissions)})")
        
    except Exception as e:
        error_msg = f"파일 작성 실패: {file_path} - {str(e)}"
        logger.error(error_msg, exc_info=True)
        raise CICDError(error_msg) from e


def merge_configurations(base_config: Dict[str, str], override_config: Dict[str, str]) -> Dict[str, str]:
    """설정 병합 (override_config가 base_config를 덮어씀)"""
    logger = Logger.get_logger("utils")
    
    merged = base_config.copy()
    merged.update(override_config)
    
    logger.debug(f"설정 병합 완료: 기본 {len(base_config)}개 + 덮어쓰기 {len(override_config)}개 = 최종 {len(merged)}개")
    
    return merged


def validate_deployment_payload(payload: Dict[str, str]) -> bool:
    """배포 페이로드 검증"""
    logger = Logger.get_logger("utils")
    
    required_fields = ['source_repo', 'ref', 'version', 'service_kind', 'environment']
    missing_fields = []
    
    for field in required_fields:
        if field not in payload or not payload[field]:
            missing_fields.append(field)
    
    if missing_fields:
        logger.error(f"배포 페이로드에 필수 필드가 누락되었습니다: {', '.join(missing_fields)}")
        return False
    
    # 환경 및 서비스 종류 검증
    if not Config.validate_environment(payload['environment']):
        logger.error(f"지원되지 않는 환경: {payload['environment']}")
        return False
    
    if not Config.validate_service_kind(payload['service_kind']):
        logger.error(f"지원되지 않는 서비스 종류: {payload['service_kind']}")
        return False
    
    logger.info("배포 페이로드 검증 성공")
    return True


if __name__ == "__main__":
    # 테스트 코드
    logger = Logger.get_logger("test")
    logger.info("유틸리티 모듈 테스트 시작")
    
    # 설정 테스트
    logger.info(f"지원되는 환경: {Config.SUPPORTED_ENVIRONMENTS}")
    logger.info(f"지원되는 서비스 종류: {Config.SUPPORTED_SERVICE_KINDS}")
    logger.info(f"기본 AWS 리전: {Config.DEFAULT_AWS_REGION}")
    
    # 환경 검증 테스트
    test_payload = {
        'source_repo': 'test/repo',
        'ref': 'main',
        'version': 'v1.0.0',
        'service_kind': 'fe',
        'environment': 'prod'
    }
    
    if validate_deployment_payload(test_payload):
        logger.info("배포 페이로드 검증 테스트 성공")
    else:
        logger.error("배포 페이로드 검증 테스트 실패")
    
    # SSM 클라이언트 테스트 (자격 증명이 있는 경우)
    try:
        ssm = SSMClient()
        logger.info("SSM 클라이언트 초기화 성공")
    except SSMError as e:
        logger.warning(f"SSM 클라이언트 초기화 실패 (정상적임): {str(e)}")
    except Exception as e:
        logger.error(f"예상치 못한 SSM 에러: {str(e)}")
    
    # 헬스 체커 테스트
    try:
        health_checker = HealthChecker()
        result = health_checker.check_url("https://httpbin.org/status/200", timeout=5)
        logger.info(f"헬스 체크 테스트 결과: {result}")
    except Exception as e:
        logger.warning(f"헬스 체크 테스트 실패 (네트워크 문제일 수 있음): {str(e)}")
    
    # 재시도 헬퍼 테스트
    retry_helper = RetryHelper()
    
    def test_function():
        import random
        if random.random() < 0.7:  # 70% 확률로 실패
            raise Exception("테스트 실패")
        return "성공"
    
    try:
        result = retry_helper.retry_with_backoff(test_function, max_retries=3, backoff_factor=0.1)
        logger.info(f"재시도 테스트 결과: {result}")
    except Exception as e:
        logger.info(f"재시도 테스트 최종 실패 (정상적임): {str(e)}")
    
    logger.info("유틸리티 모듈 테스트 완료")