#!/usr/bin/env python3
"""
커스텀 Pre-deploy 훅 예제
프로젝트별 배포 전 검증 로직을 구현합니다.
"""

import os
import sys
import subprocess
import requests
from typing import Dict, List

# deploy_hooks 모듈 임포트
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'universal-makefile', 'scripts'))
from deploy_hooks import DeployHook


class CustomEnvironmentCheck(DeployHook):
    """커스텀 환경 검증 훅"""
    
    hook_type = 'pre'
    
    @property
    def name(self) -> str:
        return "custom_environment_check"
    
    @property
    def description(self) -> str:
        return "프로젝트별 환경 설정 검증"
    
    def execute(self) -> bool:
        """환경별 커스텀 검증 실행"""
        try:
            self.logger.info("커스텀 환경 검증 시작")
            
            # 환경별 다른 검증 로직
            if self.environment == 'production':
                return self._validate_production_environment()
            elif self.environment == 'staging':
                return self._validate_staging_environment()
            else:
                return self._validate_development_environment()
                
        except Exception as e:
            self.logger.error(f"커스텀 환경 검증 실패: {str(e)}")
            return False
    
    def _validate_production_environment(self) -> bool:
        """프로덕션 환경 검증"""
        self.logger.info("프로덕션 환경 검증 중...")
        
        # 프로덕션 전용 환경 변수 확인
        required_prod_vars = [
            'PROD_DATABASE_URL',
            'PROD_REDIS_URL',
            'MONITORING_API_KEY',
            'BACKUP_S3_BUCKET'
        ]
        
        for var in required_prod_vars:
            if not os.environ.get(var):
                self.logger.error(f"프로덕션 필수 환경 변수 없음: {var}")
                return False
        
        # SSL 인증서 확인
        if not self._check_ssl_certificates():
            return False
        
        # 백업 시스템 확인
        if not self._check_backup_system():
            return False
        
        self.logger.info("프로덕션 환경 검증 완료")
        return True
    
    def _validate_staging_environment(self) -> bool:
        """스테이징 환경 검증"""
        self.logger.info("스테이징 환경 검증 중...")
        
        # 스테이징 전용 검증 로직
        required_staging_vars = [
            'STAGING_DATABASE_URL',
            'TEST_API_KEY'
        ]
        
        for var in required_staging_vars:
            if not os.environ.get(var):
                self.logger.error(f"스테이징 필수 환경 변수 없음: {var}")
                return False
        
        self.logger.info("스테이징 환경 검증 완료")
        return True
    
    def _validate_development_environment(self) -> bool:
        """개발 환경 검증"""
        self.logger.info("개발 환경 검증 중...")
        
        # 개발 환경은 관대한 검증
        self.logger.info("개발 환경 검증 완료")
        return True
    
    def _check_ssl_certificates(self) -> bool:
        """SSL 인증서 유효성 확인"""
        try:
            cert_path = os.environ.get('SSL_CERT_PATH')
            if not cert_path or not os.path.exists(cert_path):
                self.logger.error("SSL 인증서 파일을 찾을 수 없습니다.")
                return False
            
            # 인증서 만료일 확인 (openssl 명령 사용)
            result = subprocess.run(
                ['openssl', 'x509', '-in', cert_path, '-noout', '-dates'],
                capture_output=True,
                text=True
            )
            
            if result.returncode != 0:
                self.logger.error("SSL 인증서 검증 실패")
                return False
            
            self.logger.info("SSL 인증서 검증 완료")
            return True
            
        except Exception as e:
            self.logger.error(f"SSL 인증서 확인 실패: {str(e)}")
            return False
    
    def _check_backup_system(self) -> bool:
        """백업 시스템 상태 확인"""
        try:
            backup_api_url = os.environ.get('BACKUP_API_URL')
            backup_api_key = os.environ.get('BACKUP_API_KEY')
            
            if not backup_api_url or not backup_api_key:
                self.logger.warning("백업 시스템 설정이 없습니다.")
                return True
            
            # 백업 시스템 API 호출
            response = requests.get(
                f"{backup_api_url}/status",
                headers={'Authorization': f'Bearer {backup_api_key}'},
                timeout=10
            )
            
            if response.status_code == 200:
                self.logger.info("백업 시스템 정상 작동")
                return True
            else:
                self.logger.error(f"백업 시스템 응답 오류: {response.status_code}")
                return False
                
        except Exception as e:
            self.logger.error(f"백업 시스템 확인 실패: {str(e)}")
            return False


class DatabaseMigrationCheck(DeployHook):
    """데이터베이스 마이그레이션 확인 훅"""
    
    hook_type = 'pre'
    
    @property
    def name(self) -> str:
        return "database_migration_check"
    
    @property
    def description(self) -> str:
        return "데이터베이스 마이그레이션 상태 확인 및 실행"
    
    def execute(self) -> bool:
        """마이그레이션 확인 및 실행"""
        try:
            # 백엔드 서비스만 마이그레이션 확인
            if self.service_kind != 'be':
                self.logger.info("프론트엔드 서비스, 마이그레이션 건너뜀")
                return True
            
            self.logger.info("데이터베이스 마이그레이션 확인 중...")
            
            # 마이그레이션 필요 여부 확인
            if not self._check_migration_needed():
                self.logger.info("적용할 마이그레이션이 없습니다.")
                return True
            
            # 프로덕션 환경에서는 백업 생성
            if self.environment == 'production':
                if not self._create_database_backup():
                    self.logger.error("데이터베이스 백업 생성 실패")
                    return False
            
            # 마이그레이션 실행
            return self._run_migrations()
            
        except Exception as e:
            self.logger.error(f"마이그레이션 확인 실패: {str(e)}")
            return False
    
    def _check_migration_needed(self) -> bool:
        """마이그레이션 필요 여부 확인"""
        try:
            # Django 예시
            result = subprocess.run(
                ['python', 'manage.py', 'showmigrations', '--plan'],
                capture_output=True,
                text=True,
                timeout=30
            )
            
            if result.returncode != 0:
                self.logger.error("마이그레이션 상태 확인 실패")
                return False
            
            # 미적용 마이그레이션이 있는지 확인
            return '[ ]' in result.stdout
            
        except subprocess.TimeoutExpired:
            self.logger.error("마이그레이션 상태 확인 시간 초과")
            return False
        except Exception as e:
            self.logger.error(f"마이그레이션 상태 확인 실패: {str(e)}")
            return False
    
    def _create_database_backup(self) -> bool:
        """데이터베이스 백업 생성"""
        try:
            self.logger.info("데이터베이스 백업 생성 중...")
            
            backup_script = os.environ.get('DB_BACKUP_SCRIPT', './scripts/backup_db.sh')
            
            if not os.path.exists(backup_script):
                self.logger.warning("백업 스크립트를 찾을 수 없습니다.")
                return True  # 백업 스크립트가 없어도 계속 진행
            
            result = subprocess.run(
                [backup_script, self.environment],
                capture_output=True,
                text=True,
                timeout=300  # 5분 타임아웃
            )
            
            if result.returncode == 0:
                self.logger.info("데이터베이스 백업 완료")
                return True
            else:
                self.logger.error(f"데이터베이스 백업 실패: {result.stderr}")
                return False
                
        except subprocess.TimeoutExpired:
            self.logger.error("데이터베이스 백업 시간 초과")
            return False
        except Exception as e:
            self.logger.error(f"데이터베이스 백업 실패: {str(e)}")
            return False
    
    def _run_migrations(self) -> bool:
        """마이그레이션 실행"""
        try:
            self.logger.info("데이터베이스 마이그레이션 실행 중...")
            
            # Django 마이그레이션 실행
            result = subprocess.run(
                ['python', 'manage.py', 'migrate'],
                capture_output=True,
                text=True,
                timeout=600  # 10분 타임아웃
            )
            
            if result.returncode == 0:
                self.logger.info("데이터베이스 마이그레이션 완료")
                if result.stdout:
                    self.logger.info(f"마이그레이션 출력: {result.stdout}")
                return True
            else:
                self.logger.error(f"데이터베이스 마이그레이션 실패: {result.stderr}")
                return False
                
        except subprocess.TimeoutExpired:
            self.logger.error("데이터베이스 마이그레이션 시간 초과")
            return False
        except Exception as e:
            self.logger.error(f"데이터베이스 마이그레이션 실패: {str(e)}")
            return False


class ExternalServiceNotification(DeployHook):
    """외부 서비스 배포 알림 훅"""
    
    hook_type = 'pre'
    
    @property
    def name(self) -> str:
        return "external_service_notification"
    
    @property
    def description(self) -> str:
        return "외부 서비스에 배포 시작 알림"
    
    def execute(self) -> bool:
        """외부 서비스에 배포 시작 알림"""
        try:
            webhook_url = os.environ.get('DEPLOY_START_WEBHOOK_URL')
            
            if not webhook_url:
                self.logger.info("배포 시작 웹훅 URL이 설정되지 않음")
                return True
            
            # 배포 정보 구성
            deploy_info = {
                'event': 'deployment_started',
                'environment': self.environment,
                'service': self.service_kind,
                'version': os.environ.get('VERSION', 'unknown'),
                'timestamp': time.time(),
                'deployer': os.environ.get('USER', 'unknown')
            }
            
            # 웹훅 호출
            response = requests.post(
                webhook_url,
                json=deploy_info,
                timeout=10
            )
            
            if response.status_code in [200, 201, 202]:
                self.logger.info("배포 시작 알림 전송 완료")
                return True
            else:
                self.logger.warning(f"배포 시작 알림 전송 실패: {response.status_code}")
                return True  # 알림 실패는 배포를 중단하지 않음
                
        except Exception as e:
            self.logger.warning(f"배포 시작 알림 실패: {str(e)}")
            return True  # 알림 실패는 배포를 중단하지 않음