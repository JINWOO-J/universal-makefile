#!/usr/bin/env python3
"""
사후 배포 헬스 체크 및 알림 시스템
배포 완료 후 애플리케이션 상태를 확인하고 결과를 알립니다.
"""

import os
import sys
import argparse
import time
import subprocess
from typing import Dict, List, Optional, Tuple

# 현재 스크립트 디렉토리를 Python 경로에 추가
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from utils import Logger, HealthChecker, SlackNotifier, load_env_file


class PostDeployChecker:
    """사후 배포 헬스 체크"""
    
    def __init__(self, 
                 environment: str, 
                 service_kind: str,
                 deployment_id: str = None):
        self.environment = environment
        self.service_kind = service_kind
        self.deployment_id = deployment_id
        self.logger = Logger(f"PostDeployChecker-{environment}-{service_kind}")
        self.health_checker = HealthChecker()
        
        # Slack 알림 초기화
        self.slack_notifier = SlackNotifier()
        
        # 프로젝트 루트 디렉토리
        self.project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        
        # 환경 변수 로드
        self._load_environment_variables()
        
        self.logger.info(f"PostDeployChecker 초기화 완료 (환경: {environment}, 서비스: {service_kind})")
    
    def _load_environment_variables(self):
        """환경 변수 로드"""
        try:
            env_runtime_path = os.path.join(self.project_root, '.env.runtime')
            if os.path.exists(env_runtime_path):
                env_vars = load_env_file(env_runtime_path)
                for key, value in env_vars.items():
                    os.environ[key] = value
                self.logger.info(f".env.runtime에서 {len(env_vars)}개 환경 변수 로드")
        except Exception as e:
            self.logger.warning(f"환경 변수 로드 실패: {str(e)}")
    
    def run_health_checks(self, max_retries: int = 5, retry_delay: int = 30) -> bool:
        """헬스 체크 실행"""
        try:
            self.logger.info("사후 배포 헬스 체크 시작")
            
            # 서비스 시작 대기
            self._wait_for_service_startup()
            
            # 헬스 체크 항목들
            health_checks = [
                ("컨테이너 상태 확인", self.check_container_status),
                ("서비스 응답 확인", self.check_service_response),
                ("데이터베이스 연결 확인", self.check_database_health),
                ("외부 의존성 확인", self.check_external_dependencies),
                ("로그 에러 확인", self.check_application_logs),
            ]
            
            # 재시도 로직
            for attempt in range(max_retries):
                self.logger.info(f"헬스 체크 시도 {attempt + 1}/{max_retries}")
                
                failed_checks = []
                
                for check_name, check_func in health_checks:
                    try:
                        self.logger.info(f"실행 중: {check_name}")
                        if not check_func():
                            failed_checks.append(check_name)
                            self.logger.error(f"헬스 체크 실패: {check_name}")
                        else:
                            self.logger.info(f"헬스 체크 성공: {check_name}")
                    except Exception as e:
                        failed_checks.append(check_name)
                        self.logger.error(f"헬스 체크 중 예외 발생 ({check_name}): {str(e)}")
                
                if not failed_checks:
                    self.logger.info("모든 헬스 체크 통과")
                    return True
                
                if attempt < max_retries - 1:
                    self.logger.warning(f"헬스 체크 실패, {retry_delay}초 후 재시도: {', '.join(failed_checks)}")
                    time.sleep(retry_delay)
                else:
                    self.logger.error(f"최대 재시도 횟수 초과. 실패한 검사: {', '.join(failed_checks)}")
            
            return False
            
        except Exception as e:
            self.logger.error(f"헬스 체크 중 예외 발생: {str(e)}")
            return False
    
    def _wait_for_service_startup(self, max_wait: int = 120):
        """서비스 시작 대기"""
        try:
            self.logger.info(f"서비스 시작 대기 (최대 {max_wait}초)")
            
            start_time = time.time()
            while time.time() - start_time < max_wait:
                if self._is_service_ready():
                    self.logger.info("서비스 시작 확인됨")
                    return
                
                time.sleep(5)
            
            self.logger.warning("서비스 시작 대기 시간 초과")
            
        except Exception as e:
            self.logger.error(f"서비스 시작 대기 중 예외 발생: {str(e)}")
    
    def _is_service_ready(self) -> bool:
        """서비스 준비 상태 확인"""
        try:
            # Docker Compose 서비스 상태 확인
            result = subprocess.run(
                ['docker', 'compose', 'ps', '--services', '--filter', 'status=running'],
                capture_output=True,
                text=True,
                cwd=self.project_root
            )
            
            if result.returncode == 0 and result.stdout.strip():
                return True
            
            return False
            
        except Exception:
            return False
    
    def check_container_status(self) -> bool:
        """컨테이너 상태 확인"""
        try:
            # Docker Compose 서비스 상태 확인
            result = subprocess.run(
                ['docker', 'compose', 'ps', '--format', 'json'],
                capture_output=True,
                text=True,
                cwd=self.project_root
            )
            
            if result.returncode != 0:
                self.logger.error("Docker Compose 상태 확인 실패")
                return False
            
            import json
            
            # JSON 출력 파싱
            containers = []
            for line in result.stdout.strip().split('\n'):
                if line.strip():
                    try:
                        container = json.loads(line)
                        containers.append(container)
                    except json.JSONDecodeError:
                        continue
            
            if not containers:
                self.logger.error("실행 중인 컨테이너를 찾을 수 없습니다.")
                return False
            
            # 모든 컨테이너가 healthy 상태인지 확인
            unhealthy_containers = []
            for container in containers:
                status = container.get('State', '').lower()
                health = container.get('Health', '').lower()
                
                if status != 'running':
                    unhealthy_containers.append(f"{container.get('Name', 'unknown')} (상태: {status})")
                elif health and health not in ['healthy', '']:
                    unhealthy_containers.append(f"{container.get('Name', 'unknown')} (헬스: {health})")
            
            if unhealthy_containers:
                self.logger.error(f"비정상 컨테이너: {', '.join(unhealthy_containers)}")
                return False
            
            self.logger.info(f"{len(containers)}개 컨테이너 모두 정상 상태")
            return True
            
        except Exception as e:
            self.logger.error(f"컨테이너 상태 확인 실패: {str(e)}")
            return False
    
    def check_service_response(self) -> bool:
        """서비스 응답 확인"""
        try:
            # 서비스별 헬스체크 URL 구성
            health_urls = self._get_health_check_urls()
            
            if not health_urls:
                self.logger.warning("헬스체크 URL이 설정되지 않았습니다.")
                return True
            
            # 모든 헬스체크 URL 확인
            all_healthy = True
            for url in health_urls:
                if not self.health_checker.check_url(url, timeout=30):
                    all_healthy = False
                    self.logger.error(f"서비스 응답 실패: {url}")
                else:
                    self.logger.info(f"서비스 응답 성공: {url}")
            
            return all_healthy
            
        except Exception as e:
            self.logger.error(f"서비스 응답 확인 실패: {str(e)}")
            return False
    
    def _get_health_check_urls(self) -> List[str]:
        """헬스체크 URL 목록 반환"""
        urls = []
        
        try:
            if self.service_kind == 'fe':
                # 프론트엔드 헬스체크
                frontend_url = os.environ.get('FRONTEND_URL', 'http://localhost:3000')
                urls.append(frontend_url)
                
                # 프론트엔드 헬스체크 엔드포인트가 있다면
                health_endpoint = os.environ.get('FRONTEND_HEALTH_ENDPOINT', '/health')
                if health_endpoint:
                    urls.append(f"{frontend_url.rstrip('/')}{health_endpoint}")
                    
            elif self.service_kind == 'be':
                # 백엔드 헬스체크
                api_url = os.environ.get('API_URL', 'http://localhost:8000')
                urls.append(f"{api_url.rstrip('/')}/health")
                
                # 추가 API 엔드포인트
                additional_endpoints = os.environ.get('HEALTH_CHECK_ENDPOINTS', '').split(',')
                for endpoint in additional_endpoints:
                    if endpoint.strip():
                        urls.append(f"{api_url.rstrip('/')}{endpoint.strip()}")
            
            # 커스텀 헬스체크 URL
            custom_urls = os.environ.get('CUSTOM_HEALTH_URLS', '').split(',')
            for url in custom_urls:
                if url.strip():
                    urls.append(url.strip())
            
            return urls
            
        except Exception as e:
            self.logger.error(f"헬스체크 URL 구성 실패: {str(e)}")
            return []
    
    def check_database_health(self) -> bool:
        """데이터베이스 헬스 확인"""
        try:
            # 백엔드 서비스만 데이터베이스 확인
            if self.service_kind != 'be':
                self.logger.info("프론트엔드 서비스, 데이터베이스 헬스 확인 건너뜀")
                return True
            
            db_host = os.environ.get('DB_HOST')
            db_port = os.environ.get('DB_PORT', '5432')
            
            if not db_host:
                self.logger.info("DB_HOST가 설정되지 않음, 데이터베이스 헬스 확인 건너뜀")
                return True
            
            # 데이터베이스 연결 테스트
            import socket
            
            try:
                sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                sock.settimeout(10)
                result = sock.connect_ex((db_host, int(db_port)))
                sock.close()
                
                if result == 0:
                    self.logger.info(f"데이터베이스 연결 성공: {db_host}:{db_port}")
                    return True
                else:
                    self.logger.error(f"데이터베이스 연결 실패: {db_host}:{db_port}")
                    return False
                    
            except Exception as e:
                self.logger.error(f"데이터베이스 연결 테스트 실패: {str(e)}")
                return False
                
        except Exception as e:
            self.logger.error(f"데이터베이스 헬스 확인 실패: {str(e)}")
            return False
    
    def check_external_dependencies(self) -> bool:
        """외부 의존성 확인"""
        try:
            # 외부 API 의존성 확인
            external_apis = os.environ.get('EXTERNAL_APIS', '').split(',')
            
            all_healthy = True
            for api_url in external_apis:
                if api_url.strip():
                    if not self.health_checker.check_url(api_url.strip(), timeout=10):
                        self.logger.warning(f"외부 API 연결 실패: {api_url}")
                        # 외부 의존성 실패는 경고로만 처리
                    else:
                        self.logger.info(f"외부 API 연결 성공: {api_url}")
            
            # Redis 연결 확인 (있는 경우)
            redis_url = os.environ.get('REDIS_URL')
            if redis_url:
                # Redis 연결 테스트는 실제 구현에서 추가
                self.logger.info("Redis 연결 확인 (구현 필요)")
            
            return all_healthy
            
        except Exception as e:
            self.logger.error(f"외부 의존성 확인 실패: {str(e)}")
            return False
    
    def check_application_logs(self) -> bool:
        """애플리케이션 로그 에러 확인"""
        try:
            # Docker Compose 로그에서 에러 확인
            result = subprocess.run(
                ['docker', 'compose', 'logs', '--tail=100'],
                capture_output=True,
                text=True,
                cwd=self.project_root
            )
            
            if result.returncode != 0:
                self.logger.warning("Docker Compose 로그 조회 실패")
                return True  # 로그 조회 실패는 배포를 중단하지 않음
            
            logs = result.stdout.lower()
            
            # 심각한 에러 패턴 확인
            error_patterns = [
                'fatal error',
                'panic:',
                'segmentation fault',
                'out of memory',
                'connection refused',
                'failed to start',
                'exit code 1',
            ]
            
            found_errors = []
            for pattern in error_patterns:
                if pattern in logs:
                    found_errors.append(pattern)
            
            if found_errors:
                self.logger.warning(f"로그에서 에러 패턴 발견: {', '.join(found_errors)}")
                # 로그 에러는 경고로만 처리 (일부 에러는 정상적일 수 있음)
            else:
                self.logger.info("로그에서 심각한 에러 패턴 없음")
            
            return True
            
        except Exception as e:
            self.logger.error(f"애플리케이션 로그 확인 실패: {str(e)}")
            return True  # 로그 확인 실패는 배포를 중단하지 않음
    
    def send_success_notification(self, deployment_info: Dict[str, str]) -> bool:
        """배포 성공 알림 전송"""
        try:
            self.logger.info("배포 성공 알림 전송")
            
            # 배포 정보 보완
            notification_info = {
                'environment': self.environment,
                'service_kind': self.service_kind,
                'deployment_id': self.deployment_id,
                **deployment_info
            }
            
            # Slack 알림 전송
            success = self.slack_notifier.send_deployment_success(notification_info)
            
            if success:
                self.logger.info("배포 성공 알림 전송 완료")
            else:
                self.logger.warning("배포 성공 알림 전송 실패")
            
            return success
            
        except Exception as e:
            self.logger.error(f"배포 성공 알림 전송 실패: {str(e)}")
            return False
    
    def send_failure_notification(self, deployment_info: Dict[str, str], error_message: str) -> bool:
        """배포 실패 알림 전송"""
        try:
            self.logger.info("배포 실패 알림 전송")
            
            # 배포 정보 보완
            notification_info = {
                'environment': self.environment,
                'service_kind': self.service_kind,
                'deployment_id': self.deployment_id,
                **deployment_info
            }
            
            # Slack 알림 전송
            success = self.slack_notifier.send_deployment_failure(notification_info, error_message)
            
            if success:
                self.logger.info("배포 실패 알림 전송 완료")
            else:
                self.logger.warning("배포 실패 알림 전송 실패")
            
            return success
            
        except Exception as e:
            self.logger.error(f"배포 실패 알림 전송 실패: {str(e)}")
            return False
    
    def trigger_rollback(self) -> bool:
        """롤백 트리거"""
        try:
            self.logger.info("자동 롤백 트리거")
            
            # 롤백 스크립트 실행
            rollback_script = os.path.join(
                os.path.dirname(os.path.abspath(__file__)),
                'rollback.py'
            )
            
            if not os.path.exists(rollback_script):
                self.logger.error("롤백 스크립트를 찾을 수 없습니다.")
                return False
            
            # 롤백 실행
            result = subprocess.run(
                ['python', rollback_script, self.environment, self.service_kind],
                capture_output=True,
                text=True,
                timeout=300  # 5분 타임아웃
            )
            
            if result.returncode == 0:
                self.logger.info("자동 롤백 성공")
                return True
            else:
                self.logger.error(f"자동 롤백 실패: {result.stderr}")
                return False
                
        except subprocess.TimeoutExpired:
            self.logger.error("롤백 실행 시간 초과")
            return False
        except Exception as e:
            self.logger.error(f"롤백 트리거 실패: {str(e)}")
            return False


def main():
    """메인 함수"""
    parser = argparse.ArgumentParser(description="사후 배포 헬스 체크 및 알림")
    
    parser.add_argument(
        'environment',
        help='배포 환경 (예: prod, staging)'
    )
    
    parser.add_argument(
        'service_kind',
        choices=['fe', 'be'],
        help='서비스 종류 (fe: 프론트엔드, be: 백엔드)'
    )
    
    parser.add_argument(
        '--deployment-id',
        help='배포 ID'
    )
    
    parser.add_argument(
        '--source-repo',
        help='소스 저장소'
    )
    
    parser.add_argument(
        '--version',
        help='배포 버전'
    )
    
    parser.add_argument(
        '--max-retries',
        type=int,
        default=5,
        help='최대 재시도 횟수'
    )
    
    parser.add_argument(
        '--retry-delay',
        type=int,
        default=30,
        help='재시도 간격 (초)'
    )
    
    parser.add_argument(
        '--auto-rollback',
        action='store_true',
        help='헬스 체크 실패 시 자동 롤백'
    )
    
    args = parser.parse_args()
    
    # 환경 변수 설정
    os.environ['ENVIRONMENT'] = args.environment
    os.environ['SERVICE_KIND'] = args.service_kind
    
    # 로거 초기화
    logger = Logger("post_deploy")
    
    try:
        # PostDeployChecker 초기화
        checker = PostDeployChecker(
            args.environment, 
            args.service_kind,
            args.deployment_id
        )
        
        # 배포 정보 구성
        deployment_info = {
            'source_repo': args.source_repo or 'unknown',
            'version': args.version or 'unknown',
            'environment': args.environment,
            'service_kind': args.service_kind,
        }
        
        # 헬스 체크 실행
        health_check_passed = checker.run_health_checks(
            max_retries=args.max_retries,
            retry_delay=args.retry_delay
        )
        
        if health_check_passed:
            # 성공 알림 전송
            checker.send_success_notification(deployment_info)
            logger.info("사후 배포 헬스 체크 성공")
            print("SUCCESS: Post-deployment health checks passed")
        else:
            # 실패 처리
            error_message = "헬스 체크 실패"
            
            # 실패 알림 전송
            checker.send_failure_notification(deployment_info, error_message)
            
            # 자동 롤백 실행
            if args.auto_rollback:
                logger.info("자동 롤백 시작")
                rollback_success = checker.trigger_rollback()
                
                if rollback_success:
                    # 롤백 성공 알림
                    rollback_info = deployment_info.copy()
                    rollback_info['action'] = 'rollback'
                    checker.slack_notifier.send_rollback_notification(
                        rollback_info, 
                        "previous_digest"  # 실제 구현에서는 이전 다이제스트 조회
                    )
                    logger.info("자동 롤백 완료")
                else:
                    logger.error("자동 롤백 실패")
            
            logger.error("사후 배포 헬스 체크 실패")
            print("ERROR: Post-deployment health checks failed", file=sys.stderr)
            sys.exit(1)
        
    except Exception as e:
        logger.error(f"사후 배포 헬스 체크 중 예외 발생: {str(e)}")
        print(f"ERROR: {str(e)}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()