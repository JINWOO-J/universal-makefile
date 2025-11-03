#!/usr/bin/env python3
"""
커스텀 Post-deploy 훅 예제
프로젝트별 배포 후 검증 및 알림 로직을 구현합니다.
"""

import os
import sys
import time
import subprocess
import requests
from typing import Dict, List, Optional

# deploy_hooks 모듈 임포트
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'universal-makefile', 'scripts'))
from deploy_hooks import DeployHook


class CustomHealthCheck(DeployHook):
    """커스텀 헬스체크 훅"""
    
    hook_type = 'post'
    
    @property
    def name(self) -> str:
        return "custom_health_check"
    
    @property
    def description(self) -> str:
        return "프로젝트별 커스텀 헬스체크"
    
    def execute(self) -> bool:
        """커스텀 헬스체크 실행"""
        try:
            self.logger.info("커스텀 헬스체크 시작")
            
            # 서비스별 다른 헬스체크
            if self.service_kind == 'fe':
                return self._check_frontend_health()
            elif self.service_kind == 'be':
                return self._check_backend_health()
            else:
                self.logger.warning("알 수 없는 서비스 타입")
                return True
                
        except Exception as e:
            self.logger.error(f"커스텀 헬스체크 실패: {str(e)}")
            return False
    
    def _check_frontend_health(self) -> bool:
        """프론트엔드 헬스체크"""
        try:
            self.logger.info("프론트엔드 헬스체크 실행 중...")
            
            # 기본 페이지 로드 확인
            frontend_url = os.environ.get('FRONTEND_URL', 'http://localhost:3000')
            
            response = requests.get(frontend_url, timeout=30)
            if response.status_code != 200:
                self.logger.error(f"프론트엔드 페이지 로드 실패: {response.status_code}")
                return False
            
            # JavaScript 번들 로드 확인
            if not self._check_js_bundles(response.text):
                return False
            
            # API 연결 확인
            if not self._check_api_connectivity():
                return False
            
            self.logger.info("프론트엔드 헬스체크 완료")
            return True
            
        except Exception as e:
            self.logger.error(f"프론트엔드 헬스체크 실패: {str(e)}")
            return False
    
    def _check_backend_health(self) -> bool:
        """백엔드 헬스체크"""
        try:
            self.logger.info("백엔드 헬스체크 실행 중...")
            
            # API 엔드포인트 확인
            api_url = os.environ.get('API_URL', 'http://localhost:8000')
            
            # 헬스체크 엔드포인트
            health_response = requests.get(f"{api_url}/health", timeout=30)
            if health_response.status_code != 200:
                self.logger.error(f"헬스체크 엔드포인트 실패: {health_response.status_code}")
                return False
            
            # 데이터베이스 연결 확인
            if not self._check_database_connection():
                return False
            
            # 캐시 시스템 확인
            if not self._check_cache_system():
                return False
            
            # 중요 API 엔드포인트 확인
            if not self._check_critical_endpoints():
                return False
            
            self.logger.info("백엔드 헬스체크 완료")
            return True
            
        except Exception as e:
            self.logger.error(f"백엔드 헬스체크 실패: {str(e)}")
            return False
    
    def _check_js_bundles(self, html_content: str) -> bool:
        """JavaScript 번들 로드 확인"""
        try:
            # HTML에서 script 태그 확인
            if '<script' not in html_content:
                self.logger.error("JavaScript 번들을 찾을 수 없습니다.")
                return False
            
            # 번들 파일 직접 확인 (선택사항)
            bundle_url = os.environ.get('JS_BUNDLE_URL')
            if bundle_url:
                response = requests.head(bundle_url, timeout=10)
                if response.status_code != 200:
                    self.logger.error(f"JavaScript 번들 로드 실패: {response.status_code}")
                    return False
            
            self.logger.info("JavaScript 번들 확인 완료")
            return True
            
        except Exception as e:
            self.logger.error(f"JavaScript 번들 확인 실패: {str(e)}")
            return False
    
    def _check_api_connectivity(self) -> bool:
        """API 연결 확인"""
        try:
            api_url = os.environ.get('API_URL')
            if not api_url:
                self.logger.info("API_URL이 설정되지 않음")
                return True
            
            response = requests.get(f"{api_url}/health", timeout=10)
            if response.status_code == 200:
                self.logger.info("API 연결 확인 완료")
                return True
            else:
                self.logger.error(f"API 연결 실패: {response.status_code}")
                return False
                
        except Exception as e:
            self.logger.error(f"API 연결 확인 실패: {str(e)}")
            return False
    
    def _check_database_connection(self) -> bool:
        """데이터베이스 연결 확인"""
        try:
            api_url = os.environ.get('API_URL', 'http://localhost:8000')
            
            # 데이터베이스 상태 확인 엔드포인트
            response = requests.get(f"{api_url}/health/db", timeout=15)
            
            if response.status_code == 200:
                db_status = response.json()
                if db_status.get('status') == 'healthy':
                    self.logger.info("데이터베이스 연결 확인 완료")
                    return True
                else:
                    self.logger.error(f"데이터베이스 상태 이상: {db_status}")
                    return False
            else:
                self.logger.error(f"데이터베이스 상태 확인 실패: {response.status_code}")
                return False
                
        except Exception as e:
            self.logger.error(f"데이터베이스 연결 확인 실패: {str(e)}")
            return False
    
    def _check_cache_system(self) -> bool:
        """캐시 시스템 확인"""
        try:
            redis_url = os.environ.get('REDIS_URL')
            if not redis_url:
                self.logger.info("Redis URL이 설정되지 않음")
                return True
            
            api_url = os.environ.get('API_URL', 'http://localhost:8000')
            
            # Redis 상태 확인 엔드포인트
            response = requests.get(f"{api_url}/health/cache", timeout=10)
            
            if response.status_code == 200:
                cache_status = response.json()
                if cache_status.get('status') == 'healthy':
                    self.logger.info("캐시 시스템 확인 완료")
                    return True
                else:
                    self.logger.warning(f"캐시 시스템 상태 이상: {cache_status}")
                    return True  # 캐시 실패는 경고로만 처리
            else:
                self.logger.warning(f"캐시 상태 확인 실패: {response.status_code}")
                return True  # 캐시 실패는 경고로만 처리
                
        except Exception as e:
            self.logger.warning(f"캐시 시스템 확인 실패: {str(e)}")
            return True  # 캐시 실패는 경고로만 처리
    
    def _check_critical_endpoints(self) -> bool:
        """중요 API 엔드포인트 확인"""
        try:
            api_url = os.environ.get('API_URL', 'http://localhost:8000')
            
            # 중요 엔드포인트 목록
            critical_endpoints = [
                '/api/v1/status',
                '/api/v1/users/me',  # 인증 확인
                '/api/v1/health/detailed'
            ]
            
            # 환경 변수로 추가 엔드포인트 설정 가능
            additional_endpoints = os.environ.get('CRITICAL_ENDPOINTS', '').split(',')
            for endpoint in additional_endpoints:
                if endpoint.strip():
                    critical_endpoints.append(endpoint.strip())
            
            failed_endpoints = []
            
            for endpoint in critical_endpoints:
                try:
                    response = requests.get(f"{api_url}{endpoint}", timeout=10)
                    if response.status_code not in [200, 401]:  # 401은 인증 필요한 엔드포인트
                        failed_endpoints.append(f"{endpoint} ({response.status_code})")
                    else:
                        self.logger.info(f"엔드포인트 확인 완료: {endpoint}")
                        
                except Exception as e:
                    failed_endpoints.append(f"{endpoint} (error: {str(e)})")
            
            if failed_endpoints:
                self.logger.error(f"중요 엔드포인트 실패: {', '.join(failed_endpoints)}")
                return False
            
            self.logger.info("모든 중요 엔드포인트 확인 완료")
            return True
            
        except Exception as e:
            self.logger.error(f"중요 엔드포인트 확인 실패: {str(e)}")
            return False


class PerformanceTest(DeployHook):
    """성능 테스트 훅"""
    
    hook_type = 'post'
    
    @property
    def name(self) -> str:
        return "performance_test"
    
    @property
    def description(self) -> str:
        return "배포 후 성능 테스트 실행"
    
    def execute(self) -> bool:
        """성능 테스트 실행"""
        try:
            # 프로덕션 환경에서만 실행
            if self.environment != 'production':
                self.logger.info("프로덕션 환경이 아니므로 성능 테스트 건너뜀")
                return True
            
            self.logger.info("성능 테스트 시작")
            
            # 응답 시간 테스트
            if not self._test_response_time():
                return False
            
            # 부하 테스트 (간단한 버전)
            if not self._test_load():
                return False
            
            self.logger.info("성능 테스트 완료")
            return True
            
        except Exception as e:
            self.logger.error(f"성능 테스트 실패: {str(e)}")
            return False
    
    def _test_response_time(self) -> bool:
        """응답 시간 테스트"""
        try:
            api_url = os.environ.get('API_URL', 'http://localhost:8000')
            max_response_time = float(os.environ.get('MAX_RESPONSE_TIME_MS', '1000'))  # 1초
            
            start_time = time.time()
            response = requests.get(f"{api_url}/health", timeout=30)
            end_time = time.time()
            
            response_time_ms = (end_time - start_time) * 1000
            
            if response.status_code == 200 and response_time_ms <= max_response_time:
                self.logger.info(f"응답 시간 테스트 통과: {response_time_ms:.2f}ms")
                return True
            else:
                self.logger.error(f"응답 시간 테스트 실패: {response_time_ms:.2f}ms (최대: {max_response_time}ms)")
                return False
                
        except Exception as e:
            self.logger.error(f"응답 시간 테스트 실패: {str(e)}")
            return False
    
    def _test_load(self) -> bool:
        """간단한 부하 테스트"""
        try:
            # 외부 부하 테스트 도구 사용 (예: Apache Bench)
            load_test_script = os.environ.get('LOAD_TEST_SCRIPT')
            
            if not load_test_script or not os.path.exists(load_test_script):
                self.logger.info("부하 테스트 스크립트가 없어 건너뜀")
                return True
            
            self.logger.info("부하 테스트 실행 중...")
            
            result = subprocess.run(
                [load_test_script, self.environment],
                capture_output=True,
                text=True,
                timeout=300  # 5분 타임아웃
            )
            
            if result.returncode == 0:
                self.logger.info("부하 테스트 통과")
                if result.stdout:
                    self.logger.info(f"부하 테스트 결과: {result.stdout}")
                return True
            else:
                self.logger.error(f"부하 테스트 실패: {result.stderr}")
                return False
                
        except subprocess.TimeoutExpired:
            self.logger.error("부하 테스트 시간 초과")
            return False
        except Exception as e:
            self.logger.error(f"부하 테스트 실패: {str(e)}")
            return False


class SlackNotification(DeployHook):
    """Slack 알림 훅"""
    
    hook_type = 'post'
    
    @property
    def name(self) -> str:
        return "slack_notification"
    
    @property
    def description(self) -> str:
        return "Slack으로 배포 완료 알림 전송"
    
    def execute(self) -> bool:
        """Slack 알림 전송"""
        try:
            webhook_url = os.environ.get('SLACK_WEBHOOK_URL')
            
            if not webhook_url:
                self.logger.info("Slack 웹훅 URL이 설정되지 않음")
                return True
            
            # 배포 정보 구성
            version = os.environ.get('VERSION', 'unknown')
            deployer = os.environ.get('USER', 'unknown')
            
            # 환경별 다른 채널/메시지
            if self.environment == 'production':
                channel = '#production-deployments'
                emoji = '🚀'
                color = 'good'
            elif self.environment == 'staging':
                channel = '#staging-deployments'
                emoji = '🧪'
                color = 'warning'
            else:
                channel = '#dev-deployments'
                emoji = '🔧'
                color = '#36a64f'
            
            message = {
                "channel": channel,
                "username": "Deploy Bot",
                "icon_emoji": ":rocket:",
                "attachments": [
                    {
                        "color": color,
                        "title": f"{emoji} 배포 완료",
                        "fields": [
                            {
                                "title": "서비스",
                                "value": self.service_kind.upper(),
                                "short": True
                            },
                            {
                                "title": "환경",
                                "value": self.environment.upper(),
                                "short": True
                            },
                            {
                                "title": "버전",
                                "value": version,
                                "short": True
                            },
                            {
                                "title": "배포자",
                                "value": deployer,
                                "short": True
                            }
                        ],
                        "footer": "Universal Makefile Deploy System",
                        "ts": int(time.time())
                    }
                ]
            }
            
            response = requests.post(webhook_url, json=message, timeout=10)
            
            if response.status_code == 200:
                self.logger.info("Slack 알림 전송 완료")
                return True
            else:
                self.logger.warning(f"Slack 알림 전송 실패: {response.status_code}")
                return True  # 알림 실패는 배포를 중단하지 않음
                
        except Exception as e:
            self.logger.warning(f"Slack 알림 실패: {str(e)}")
            return True  # 알림 실패는 배포를 중단하지 않음


class MonitoringRegistration(DeployHook):
    """모니터링 시스템 등록 훅"""
    
    hook_type = 'post'
    
    @property
    def name(self) -> str:
        return "monitoring_registration"
    
    @property
    def description(self) -> str:
        return "모니터링 시스템에 서비스 등록"
    
    def execute(self) -> bool:
        """모니터링 시스템에 서비스 등록"""
        try:
            monitoring_api_url = os.environ.get('MONITORING_API_URL')
            monitoring_api_key = os.environ.get('MONITORING_API_KEY')
            
            if not monitoring_api_url or not monitoring_api_key:
                self.logger.info("모니터링 API 설정이 없어 건너뜀")
                return True
            
            # 서비스 정보 구성
            service_info = {
                'name': f"{self.service_kind}-{self.environment}",
                'environment': self.environment,
                'service_type': self.service_kind,
                'version': os.environ.get('VERSION', 'unknown'),
                'health_url': self._get_health_url(),
                'metrics_url': self._get_metrics_url(),
                'tags': {
                    'environment': self.environment,
                    'service': self.service_kind,
                    'deployment_time': int(time.time())
                }
            }
            
            # 모니터링 시스템에 등록
            response = requests.post(
                f"{monitoring_api_url}/services",
                json=service_info,
                headers={'Authorization': f'Bearer {monitoring_api_key}'},
                timeout=30
            )
            
            if response.status_code in [200, 201]:
                self.logger.info("모니터링 시스템 등록 완료")
                return True
            else:
                self.logger.warning(f"모니터링 시스템 등록 실패: {response.status_code}")
                return True  # 모니터링 등록 실패는 배포를 중단하지 않음
                
        except Exception as e:
            self.logger.warning(f"모니터링 시스템 등록 실패: {str(e)}")
            return True  # 모니터링 등록 실패는 배포를 중단하지 않음
    
    def _get_health_url(self) -> str:
        """헬스체크 URL 반환"""
        if self.service_kind == 'fe':
            base_url = os.environ.get('FRONTEND_URL', 'http://localhost:3000')
            return f"{base_url}/health"
        else:
            base_url = os.environ.get('API_URL', 'http://localhost:8000')
            return f"{base_url}/health"
    
    def _get_metrics_url(self) -> Optional[str]:
        """메트릭 URL 반환"""
        if self.service_kind == 'be':
            base_url = os.environ.get('API_URL', 'http://localhost:8000')
            return f"{base_url}/metrics"
        return None


class DeploymentMetrics(DeployHook):
    """배포 메트릭 수집 훅"""
    
    hook_type = 'post'
    
    @property
    def name(self) -> str:
        return "deployment_metrics"
    
    @property
    def description(self) -> str:
        return "배포 메트릭 수집 및 전송"
    
    def execute(self) -> bool:
        """배포 메트릭 수집"""
        try:
            metrics_api_url = os.environ.get('METRICS_API_URL')
            
            if not metrics_api_url:
                self.logger.info("메트릭 API URL이 설정되지 않음")
                return True
            
            # 배포 메트릭 수집
            metrics = {
                'deployment_completed': 1,
                'deployment_timestamp': int(time.time()),
                'environment': self.environment,
                'service': self.service_kind,
                'version': os.environ.get('VERSION', 'unknown'),
                'deployer': os.environ.get('USER', 'unknown')
            }
            
            # 추가 메트릭 수집
            metrics.update(self._collect_system_metrics())
            
            # 메트릭 전송
            response = requests.post(
                metrics_api_url,
                json=metrics,
                timeout=10
            )
            
            if response.status_code in [200, 201, 202]:
                self.logger.info("배포 메트릭 전송 완료")
                return True
            else:
                self.logger.warning(f"배포 메트릭 전송 실패: {response.status_code}")
                return True  # 메트릭 전송 실패는 배포를 중단하지 않음
                
        except Exception as e:
            self.logger.warning(f"배포 메트릭 수집 실패: {str(e)}")
            return True  # 메트릭 수집 실패는 배포를 중단하지 않음
    
    def _collect_system_metrics(self) -> Dict[str, any]:
        """시스템 메트릭 수집"""
        metrics = {}
        
        try:
            # 컨테이너 수 확인
            result = subprocess.run(
                ['docker', 'ps', '--format', '{{.Names}}'],
                capture_output=True,
                text=True
            )
            
            if result.returncode == 0:
                container_count = len([line for line in result.stdout.strip().split('\n') if line])
                metrics['container_count'] = container_count
            
            # 이미지 크기 확인 (선택사항)
            image_name = os.environ.get('DOCKER_IMAGE_NAME')
            if image_name:
                result = subprocess.run(
                    ['docker', 'images', image_name, '--format', '{{.Size}}'],
                    capture_output=True,
                    text=True
                )
                
                if result.returncode == 0 and result.stdout.strip():
                    metrics['image_size'] = result.stdout.strip()
            
        except Exception as e:
            self.logger.warning(f"시스템 메트릭 수집 실패: {str(e)}")
        
        return metrics