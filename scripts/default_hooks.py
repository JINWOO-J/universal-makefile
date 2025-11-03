#!/usr/bin/env python3
"""
기본 배포 훅 구현
Universal Makefile System에서 제공하는 표준 훅들
"""

import os
import sys
import socket
import subprocess
import time
from typing import List, Dict, Optional

# 현재 스크립트 디렉토리를 Python 경로에 추가
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from deploy_hooks import DeployHook
from utils import Logger, HealthChecker, validate_environment_variables


# =============================================================================
# Pre-deploy 훅들
# =============================================================================

class EnvironmentVariableCheck(DeployHook):
    """환경 변수 검증 훅"""
    
    hook_type = 'pre'
    
    @property
    def name(self) -> str:
        return "environment_variable_check"
    
    @property
    def description(self) -> str:
        return "필수 환경 변수 존재 여부 확인"
    
    def execute(self) -> bool:
        try:
            # 기본 필수 환경 변수
            required_vars = [
                'ENVIRONMENT',
                'SERVICE_KIND',
            ]
            
            # 서비스별 추가 필수 변수
            if self.service_kind == 'fe':
                required_vars.extend([
                    'NODE_ENV',
                ])
            elif self.service_kind == 'be':
                required_vars.extend([
                    'DATABASE_URL',
                ])
            
            # 환경 변수 검증
            return validate_environment_variables(required_vars)
            
        except Exception as e:
            self.logger.error(f"환경 변수 검증 실패: {str(e)}")
            return False


class DockerEnvironmentCheck(DeployHook):
    """Docker 환경 검사 훅"""
    
    hook_type = 'pre'
    
    @property
    def name(self) -> str:
        return "docker_environment_check"
    
    @property
    def description(self) -> str:
        return "Docker 데몬 및 Docker Compose 실행 상태 확인"
    
    def execute(self) -> bool:
        try:
            # Docker 데몬 실행 상태 확인
            result = subprocess.run(
                ['docker', 'info'],
                capture_output=True,
                text=True,
                timeout=10
            )
            
            if result.returncode != 0:
                self.logger.error("Docker 데몬이 실행되지 않았습니다.")
                return False
            
            # Docker Compose 설치 확인
            result = subprocess.run(
                ['docker', 'compose', 'version'],
                capture_output=True,
                text=True,
                timeout=10
            )
            
            if result.returncode != 0:
                self.logger.error("Docker Compose가 설치되지 않았습니다.")
                return False
            
            self.logger.info("Docker 환경 검사 통과")
            return True
            
        except subprocess.TimeoutExpired:
            self.logger.error("Docker 명령 실행 시간 초과")
            return False
        except Exception as e:
            self.logger.error(f"Docker 환경 검사 실패: {str(e)}")
            return False


class DiskSpaceCheck(DeployHook):
    """디스크 공간 검사 훅"""
    
    hook_type = 'pre'
    
    @property
    def name(self) -> str:
        return "disk_space_check"
    
    @property
    def description(self) -> str:
        return "충분한 디스크 공간 확인"
    
    def execute(self) -> bool:
        try:
            min_free_gb = float(os.environ.get('MIN_DISK_SPACE_GB', '5.0'))
            
            # 현재 디렉토리의 디스크 사용량 확인
            project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
            statvfs = os.statvfs(project_root)
            
            # 사용 가능한 공간 계산 (GB)
            free_bytes = statvfs.f_frsize * statvfs.f_bavail
            free_gb = free_bytes / (1024 ** 3)
            
            if free_gb < min_free_gb:
                self.logger.error(f"디스크 공간 부족: {free_gb:.2f}GB (최소 {min_free_gb}GB 필요)")
                return False
            
            self.logger.info(f"디스크 공간 충분: {free_gb:.2f}GB 사용 가능")
            return True
            
        except Exception as e:
            self.logger.error(f"디스크 공간 검사 실패: {str(e)}")
            return False


class NetworkConnectivityCheck(DeployHook):
    """네트워크 연결 검사 훅"""
    
    hook_type = 'pre'
    
    @property
    def name(self) -> str:
        return "network_connectivity_check"
    
    @property
    def description(self) -> str:
        return "외부 네트워크 연결 상태 확인"
    
    def execute(self) -> bool:
        try:
            health_checker = HealthChecker()
            
            # 기본 연결 확인할 URL들
            test_urls = [
                'https://httpbin.org/status/200',  # 기본 인터넷 연결
            ]
            
            # Docker 레지스트리 연결 확인
            docker_registry = os.environ.get('DOCKER_REGISTRY', 'docker.io')
            if docker_registry != 'docker.io':
                test_urls.append(f'https://{docker_registry}')
            
            # 모든 URL 연결 테스트
            all_connected = True
            for url in test_urls:
                try:
                    if not health_checker.check_url(url, timeout=10):
                        all_connected = False
                        self.logger.warning(f"네트워크 연결 실패: {url}")
                    else:
                        self.logger.info(f"네트워크 연결 성공: {url}")
                except Exception as e:
                    self.logger.warning(f"네트워크 연결 테스트 실패 ({url}): {str(e)}")
                    # 일부 URL 실패는 경고로만 처리
            
            if all_connected:
                self.logger.info("네트워크 연결 검사 통과")
            else:
                self.logger.warning("일부 네트워크 연결 실패 (배포 계속 진행)")
            
            return True  # 네트워크 연결 실패는 배포를 중단하지 않음
            
        except Exception as e:
            self.logger.error(f"네트워크 연결 검사 실패: {str(e)}")
            return False


class ServiceDependencyCheck(DeployHook):
    """서비스 의존성 검사 훅"""
    
    hook_type = 'pre'
    
    @property
    def name(self) -> str:
        return "service_dependency_check"
    
    @property
    def description(self) -> str:
        return "서비스 의존성 확인"
    
    def execute(self) -> bool:
        try:
            health_checker = HealthChecker()
            
            # 외부 API 의존성 확인
            external_apis = os.environ.get('EXTERNAL_APIS', '').split(',')
            for api_url in external_apis:
                if api_url.strip():
                    if not health_checker.check_url(api_url.strip(), timeout=5):
                        self.logger.warning(f"외부 API 연결 실패: {api_url}")
                    else:
                        self.logger.info(f"외부 API 연결 성공: {api_url}")
            
            return True
            
        except Exception as e:
            self.logger.error(f"서비스 의존성 검사 실패: {str(e)}")
            return False


class DatabaseConnectivityCheck(DeployHook):
    """데이터베이스 연결 검사 훅"""
    
    hook_type = 'pre'
    
    @property
    def name(self) -> str:
        return "database_connectivity_check"
    
    @property
    def description(self) -> str:
        return "데이터베이스 연결 상태 확인"
    
    def execute(self) -> bool:
        try:
            # 백엔드 서비스만 데이터베이스 연결 확인
            if self.service_kind != 'be':
                self.logger.info("프론트엔드 서비스, 데이터베이스 연결 검사 건너뜀")
                return True
            
            db_host = os.environ.get('DB_HOST')
            db_port = os.environ.get('DB_PORT', '5432')
            
            if not db_host:
                self.logger.warning("DB_HOST가 설정되지 않았습니다.")
                return True  # 데이터베이스가 필수가 아닐 수 있음
            
            # 간단한 포트 연결 테스트
            try:
                sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                sock.settimeout(5)
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
            self.logger.error(f"데이터베이스 연결 검사 실패: {str(e)}")
            return False


class PortAvailabilityCheck(DeployHook):
    """포트 가용성 검사 훅"""
    
    hook_type = 'pre'
    
    @property
    def name(self) -> str:
        return "port_availability_check"
    
    @property
    def description(self) -> str:
        return "서비스 포트 가용성 확인"
    
    def execute(self) -> bool:
        try:
            # 서비스에서 사용할 포트 확인
            service_port = os.environ.get('PORT', '3000' if self.service_kind == 'fe' else '8000')
            
            try:
                sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                sock.settimeout(1)
                result = sock.connect_ex(('localhost', int(service_port)))
                sock.close()
                
                if result == 0:
                    self.logger.warning(f"포트 {service_port}가 이미 사용 중입니다.")
                    # 포트가 사용 중이어도 Docker Compose가 처리할 수 있으므로 경고만
                    return True
                else:
                    self.logger.info(f"포트 {service_port} 사용 가능")
                    return True
                    
            except Exception as e:
                self.logger.warning(f"포트 가용성 검사 실패: {str(e)}")
                return True  # 포트 검사 실패는 배포를 중단하지 않음
                
        except Exception as e:
            self.logger.error(f"포트 가용성 검사 실패: {str(e)}")
            return False


# =============================================================================
# Post-deploy 훅들
# =============================================================================

class ContainerStatusCheck(DeployHook):
    """컨테이너 상태 확인 훅"""
    
    hook_type = 'post'
    
    @property
    def name(self) -> str:
        return "container_status_check"
    
    @property
    def description(self) -> str:
        return "Docker 컨테이너 실행 상태 확인"
    
    def execute(self) -> bool:
        try:
            project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
            
            # Docker Compose 서비스 상태 확인
            result = subprocess.run(
                ['docker', 'compose', 'ps', '--format', 'json'],
                capture_output=True,
                text=True,
                cwd=project_root
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


class ServiceResponseCheck(DeployHook):
    """서비스 응답 확인 훅"""
    
    hook_type = 'post'
    
    @property
    def name(self) -> str:
        return "service_response_check"
    
    @property
    def description(self) -> str:
        return "서비스 헬스체크 엔드포인트 응답 확인"
    
    def execute(self) -> bool:
        try:
            health_checker = HealthChecker()
            
            # 서비스별 헬스체크 URL 구성
            health_urls = self._get_health_check_urls()
            
            if not health_urls:
                self.logger.warning("헬스체크 URL이 설정되지 않았습니다.")
                return True
            
            # 모든 헬스체크 URL 확인
            all_healthy = True
            for url in health_urls:
                if not health_checker.check_url(url, timeout=30):
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


class DatabaseHealthCheck(DeployHook):
    """데이터베이스 헬스 확인 훅"""
    
    hook_type = 'post'
    
    @property
    def name(self) -> str:
        return "database_health_check"
    
    @property
    def description(self) -> str:
        return "데이터베이스 연결 및 상태 확인"
    
    def execute(self) -> bool:
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


class ExternalDependencyCheck(DeployHook):
    """외부 의존성 확인 훅"""
    
    hook_type = 'post'
    
    @property
    def name(self) -> str:
        return "external_dependency_check"
    
    @property
    def description(self) -> str:
        return "외부 서비스 의존성 확인"
    
    def execute(self) -> bool:
        try:
            health_checker = HealthChecker()
            
            # 외부 API 의존성 확인
            external_apis = os.environ.get('EXTERNAL_APIS', '').split(',')
            
            all_healthy = True
            for api_url in external_apis:
                if api_url.strip():
                    if not health_checker.check_url(api_url.strip(), timeout=10):
                        self.logger.warning(f"외부 API 연결 실패: {api_url}")
                        # 외부 의존성 실패는 경고로만 처리
                    else:
                        self.logger.info(f"외부 API 연결 성공: {api_url}")
            
            return all_healthy
            
        except Exception as e:
            self.logger.error(f"외부 의존성 확인 실패: {str(e)}")
            return False


class ApplicationLogCheck(DeployHook):
    """애플리케이션 로그 확인 훅"""
    
    hook_type = 'post'
    
    @property
    def name(self) -> str:
        return "application_log_check"
    
    @property
    def description(self) -> str:
        return "애플리케이션 로그에서 에러 패턴 확인"
    
    def execute(self) -> bool:
        try:
            project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
            
            # Docker Compose 로그에서 에러 확인
            result = subprocess.run(
                ['docker', 'compose', 'logs', '--tail=100'],
                capture_output=True,
                text=True,
                cwd=project_root
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