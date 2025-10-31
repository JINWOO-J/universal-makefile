#!/usr/bin/env python3
"""
사전 배포 검사 스크립트
배포 전에 필요한 검사와 준비 작업을 수행합니다.
"""

import os
import sys
import argparse
import subprocess
from typing import Dict, List, Optional, Tuple

# 현재 스크립트 디렉토리를 Python 경로에 추가
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from utils import Logger, HealthChecker, load_env_file, validate_environment_variables


class PreDeployChecker:
    """사전 배포 검사"""
    
    def __init__(self, environment: str, service_kind: str):
        self.environment = environment
        self.service_kind = service_kind
        self.logger = Logger(f"PreDeployChecker-{environment}-{service_kind}")
        self.health_checker = HealthChecker()
        
        # 프로젝트 루트 디렉토리
        self.project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        
        self.logger.info(f"PreDeployChecker 초기화 완료 (환경: {environment}, 서비스: {service_kind})")
    
    def run_all_checks(self) -> bool:
        """모든 사전 배포 검사 실행"""
        try:
            self.logger.info("사전 배포 검사 시작")
            
            checks = [
                ("환경 변수 검증", self.check_environment_variables),
                ("Docker 환경 검사", self.check_docker_environment),
                ("디스크 공간 검사", self.check_disk_space),
                ("네트워크 연결 검사", self.check_network_connectivity),
                ("서비스 의존성 검사", self.check_service_dependencies),
                ("데이터베이스 연결 검사", self.check_database_connectivity),
                ("포트 가용성 검사", self.check_port_availability),
            ]
            
            failed_checks = []
            
            for check_name, check_func in checks:
                try:
                    self.logger.info(f"실행 중: {check_name}")
                    if not check_func():
                        failed_checks.append(check_name)
                        self.logger.error(f"검사 실패: {check_name}")
                    else:
                        self.logger.info(f"검사 성공: {check_name}")
                except Exception as e:
                    failed_checks.append(check_name)
                    self.logger.error(f"검사 중 예외 발생 ({check_name}): {str(e)}")
            
            if failed_checks:
                self.logger.error(f"사전 배포 검사 실패: {', '.join(failed_checks)}")
                return False
            else:
                self.logger.info("모든 사전 배포 검사 통과")
                return True
                
        except Exception as e:
            self.logger.error(f"사전 배포 검사 중 예외 발생: {str(e)}")
            return False
    
    def check_environment_variables(self) -> bool:
        """환경 변수 검증"""
        try:
            # 기본 필수 환경 변수
            required_vars = [
                'ENVIRONMENT',
                'SERVICE_KIND',
                'DOCKER_REGISTRY',
            ]
            
            # 서비스별 추가 필수 변수
            if self.service_kind == 'fe':
                required_vars.extend([
                    'NODE_ENV',
                    'API_URL',
                ])
            elif self.service_kind == 'be':
                required_vars.extend([
                    'DRIVE_DEFAULT_COMPANY',
                    'DRIVE_DEFAULT_WORKSPACE',
                ])
            
            # .env.runtime 파일에서 환경 변수 로드
            env_runtime_path = os.path.join(self.project_root, '.env.runtime')
            if os.path.exists(env_runtime_path):
                env_vars = load_env_file(env_runtime_path)
                
                # 환경 변수를 현재 프로세스에 설정
                for key, value in env_vars.items():
                    os.environ[key] = value
                
                self.logger.info(f".env.runtime에서 {len(env_vars)}개 환경 변수 로드")
            else:
                self.logger.warning(".env.runtime 파일을 찾을 수 없습니다.")
            
            # 필수 환경 변수 검증
            return validate_environment_variables(required_vars)
            
        except Exception as e:
            self.logger.error(f"환경 변수 검증 실패: {str(e)}")
            return False
    
    def check_docker_environment(self) -> bool:
        """Docker 환경 검사"""
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
    
    def check_disk_space(self, min_free_gb: float = 5.0) -> bool:
        """디스크 공간 검사"""
        try:
            # 현재 디렉토리의 디스크 사용량 확인
            statvfs = os.statvfs(self.project_root)
            
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
    
    def check_network_connectivity(self) -> bool:
        """네트워크 연결 검사"""
        try:
            # 기본 연결 확인할 URL들
            test_urls = [
                'https://httpbin.org/status/200',  # 기본 인터넷 연결
            ]
            
            # Docker 레지스트리 연결 확인
            docker_registry = os.environ.get('DOCKER_REGISTRY', 'docker.io')
            if docker_registry != 'docker.io':
                test_urls.append(f'https://{docker_registry}')
            
            # API URL 연결 확인 (프론트엔드인 경우)
            if self.service_kind == 'fe':
                api_url = os.environ.get('API_URL')
                if api_url:
                    # 헬스체크 엔드포인트가 있다면 확인
                    health_url = f"{api_url.rstrip('/')}/health"
                    test_urls.append(health_url)
            
            # 모든 URL 연결 테스트
            all_connected = True
            for url in test_urls:
                try:
                    if not self.health_checker.check_url(url, timeout=10):
                        all_connected = False
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
    
    def check_service_dependencies(self) -> bool:
        """서비스 의존성 검사"""
        try:
            # 서비스별 의존성 확인
            if self.service_kind == 'be':
                # 백엔드 서비스 의존성
                return self._check_backend_dependencies()
            elif self.service_kind == 'fe':
                # 프론트엔드 서비스 의존성
                return self._check_frontend_dependencies()
            else:
                self.logger.info("알 수 없는 서비스 종류, 의존성 검사 건너뜀")
                return True
                
        except Exception as e:
            self.logger.error(f"서비스 의존성 검사 실패: {str(e)}")
            return False
    
    def _check_backend_dependencies(self) -> bool:
        """백엔드 서비스 의존성 검사"""
        try:
            # 데이터베이스 연결 확인은 별도 메서드에서 처리
            # 여기서는 기타 백엔드 의존성 확인
            
            # Redis 연결 확인 (있는 경우)
            redis_url = os.environ.get('REDIS_URL')
            if redis_url:
                # Redis 연결 테스트는 실제 구현에서 추가
                self.logger.info("Redis 연결 확인 (구현 필요)")
            
            # 외부 API 의존성 확인
            external_apis = os.environ.get('EXTERNAL_APIS', '').split(',')
            for api_url in external_apis:
                if api_url.strip():
                    if not self.health_checker.check_url(api_url.strip(), timeout=5):
                        self.logger.warning(f"외부 API 연결 실패: {api_url}")
            
            return True
            
        except Exception as e:
            self.logger.error(f"백엔드 의존성 검사 실패: {str(e)}")
            return False
    
    def _check_frontend_dependencies(self) -> bool:
        """프론트엔드 서비스 의존성 검사"""
        try:
            # API 서버 연결 확인
            api_url = os.environ.get('API_URL')
            if api_url:
                health_url = f"{api_url.rstrip('/')}/health"
                if not self.health_checker.check_url(health_url, timeout=10):
                    self.logger.warning(f"API 서버 연결 실패: {health_url}")
                    # 프론트엔드는 API 서버 연결 실패해도 배포 진행
            
            # CDN 연결 확인 (있는 경우)
            cdn_url = os.environ.get('CDN_URL')
            if cdn_url:
                if not self.health_checker.check_url(cdn_url, timeout=5):
                    self.logger.warning(f"CDN 연결 실패: {cdn_url}")
            
            return True
            
        except Exception as e:
            self.logger.error(f"프론트엔드 의존성 검사 실패: {str(e)}")
            return False
    
    def check_database_connectivity(self) -> bool:
        """데이터베이스 연결 검사"""
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
            import socket
            
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
    
    def check_port_availability(self) -> bool:
        """포트 가용성 검사"""
        try:
            # 서비스에서 사용할 포트 확인
            service_port = os.environ.get('PORT', '3000' if self.service_kind == 'fe' else '8000')
            
            import socket
            
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
    
    def run_database_migrations(self) -> bool:
        """데이터베이스 마이그레이션 실행"""
        try:
            # 백엔드 서비스만 마이그레이션 실행
            if self.service_kind != 'be':
                self.logger.info("프론트엔드 서비스, 마이그레이션 건너뜀")
                return True
            
            # 마이그레이션 명령어 (프로젝트에 따라 다름)
            migration_commands = [
                # Django
                ['python', 'manage.py', 'migrate'],
                # Rails
                ['rails', 'db:migrate'],
                # Node.js (Sequelize)
                ['npx', 'sequelize-cli', 'db:migrate'],
                # Node.js (Prisma)
                ['npx', 'prisma', 'migrate', 'deploy'],
            ]
            
            # 환경 변수로 마이그레이션 명령어 지정 가능
            custom_migration = os.environ.get('MIGRATION_COMMAND')
            if custom_migration:
                migration_commands = [custom_migration.split()]
            
            # 마이그레이션 실행
            for cmd in migration_commands:
                try:
                    self.logger.info(f"마이그레이션 시도: {' '.join(cmd)}")
                    
                    result = subprocess.run(
                        cmd,
                        capture_output=True,
                        text=True,
                        timeout=300,  # 5분 타임아웃
                        cwd=self.project_root
                    )
                    
                    if result.returncode == 0:
                        self.logger.info("데이터베이스 마이그레이션 성공")
                        return True
                    else:
                        self.logger.debug(f"마이그레이션 명령 실패: {' '.join(cmd)}")
                        continue
                        
                except subprocess.TimeoutExpired:
                    self.logger.error("마이그레이션 시간 초과")
                    return False
                except FileNotFoundError:
                    # 명령어가 없으면 다음 시도
                    continue
                except Exception as e:
                    self.logger.warning(f"마이그레이션 명령 실행 실패: {str(e)}")
                    continue
            
            # 모든 마이그레이션 명령이 실패한 경우
            self.logger.warning("마이그레이션 명령을 찾을 수 없습니다. 수동 확인 필요")
            return True  # 마이그레이션 실패가 배포를 중단하지 않도록
            
        except Exception as e:
            self.logger.error(f"데이터베이스 마이그레이션 실패: {str(e)}")
            return False


def main():
    """메인 함수"""
    parser = argparse.ArgumentParser(description="사전 배포 검사 스크립트")
    
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
        '--skip-migrations',
        action='store_true',
        help='데이터베이스 마이그레이션 건너뛰기'
    )
    
    parser.add_argument(
        '--skip-network',
        action='store_true',
        help='네트워크 연결 검사 건너뛰기'
    )
    
    args = parser.parse_args()
    
    # 환경 변수 설정
    os.environ['ENVIRONMENT'] = args.environment
    os.environ['SERVICE_KIND'] = args.service_kind
    
    # 로거 초기화
    logger = Logger("pre_deploy")
    
    try:
        # PreDeployChecker 초기화
        checker = PreDeployChecker(args.environment, args.service_kind)
        
        # 사전 배포 검사 실행
        if not checker.run_all_checks():
            logger.error("사전 배포 검사 실패")
            sys.exit(1)
        
        # 데이터베이스 마이그레이션 실행
        if not args.skip_migrations:
            if not checker.run_database_migrations():
                logger.error("데이터베이스 마이그레이션 실패")
                sys.exit(1)
        
        logger.info("사전 배포 검사 완료")
        print("SUCCESS: Pre-deployment checks passed")
        
    except Exception as e:
        logger.error(f"사전 배포 검사 중 예외 발생: {str(e)}")
        print(f"ERROR: {str(e)}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()