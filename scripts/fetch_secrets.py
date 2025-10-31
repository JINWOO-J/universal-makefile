#!/usr/bin/env python3
"""
AWS SSM Parameter Store에서 비밀 정보를 가져와 .env.runtime 파일을 생성합니다.
공개 구성 파일과 SSM 비밀을 병합하여 배포에 필요한 환경 변수를 준비합니다.
"""

import os
import sys
import argparse
from typing import Dict, Optional

# 현재 스크립트 디렉토리를 Python 경로에 추가
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from utils import SSMClient, Logger, load_env_file, validate_environment_variables


class SecretsFetcher:
    """비밀 정보 가져오기 및 환경 파일 생성"""
    
    def __init__(self, environment: str):
        self.environment = environment
        self.logger = Logger(f"SecretsFetcher-{environment}")
        self.ssm_client = SSMClient()
        
        # 프로젝트 루트 디렉토리 경로
        self.project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        
        self.logger.info(f"SecretsFetcher 초기화 완료 (환경: {environment})")
    
    def fetch_ssm_secrets(self) -> Dict[str, str]:
        """SSM Parameter Store에서 환경별 비밀 정보 조회"""
        try:
            secrets = self.ssm_client.get_environment_secrets(self.environment)
            self.logger.info(f"SSM에서 {len(secrets)}개의 비밀 정보를 가져왔습니다.")
            return secrets
        except Exception as e:
            self.logger.error(f"SSM 비밀 정보 조회 실패: {str(e)}")
            raise
    
    def load_public_config(self) -> Dict[str, str]:
        """공개 구성 파일 로드"""
        config = {}
        
        # 기본 .env 파일 로드
        base_env_path = os.path.join(self.project_root, '.env')
        if os.path.exists(base_env_path):
            base_config = load_env_file(base_env_path)
            config.update(base_config)
            self.logger.info(f"기본 .env 파일에서 {len(base_config)}개 변수 로드")
        
        # 환경별 공개 구성 파일 로드
        env_config_path = os.path.join(
            self.project_root, 
            'config', 
            self.environment, 
            'app.env.public'
        )
        
        if os.path.exists(env_config_path):
            env_config = load_env_file(env_config_path)
            config.update(env_config)
            self.logger.info(f"환경별 구성 파일에서 {len(env_config)}개 변수 로드")
        else:
            self.logger.warning(f"환경별 구성 파일을 찾을 수 없습니다: {env_config_path}")
        
        return config
    
    def merge_configs(self, public_config: Dict[str, str], ssm_secrets: Dict[str, str]) -> Dict[str, str]:
        """공개 구성과 SSM 비밀 병합"""
        merged_config = {}
        
        # 공개 구성 추가
        merged_config.update(public_config)
        
        # SSM 비밀 추가 (덮어쓰기)
        merged_config.update(ssm_secrets)
        
        self.logger.info(
            f"구성 병합 완료: 공개 {len(public_config)}개 + 비밀 {len(ssm_secrets)}개 "
            f"= 총 {len(merged_config)}개"
        )
        
        return merged_config
    
    def write_env_runtime(self, config: Dict[str, str], output_path: str = None) -> str:
        """병합된 구성을 .env.runtime 파일로 저장"""
        if output_path is None:
            output_path = os.path.join(self.project_root, '.env.runtime')
        
        try:
            # 파일 내용 생성
            content_lines = [
                "# Runtime Environment Variables",
                f"# Generated at: {self._get_current_timestamp()}",
                f"# Environment: {self.environment}",
                "# This file contains secrets and should not be committed to Git",
                "",
            ]
            
            # 환경 변수를 알파벳 순으로 정렬하여 추가
            for key in sorted(config.keys()):
                value = config[key]
                content_lines.append(f"{key}={value}")
            
            # 파일 쓰기
            with open(output_path, 'w', encoding='utf-8') as f:
                f.write('\n'.join(content_lines))
            
            # 파일 권한을 600으로 설정 (소유자만 읽기/쓰기)
            os.chmod(output_path, 0o600)
            
            self.logger.info(f".env.runtime 파일 생성 완료: {output_path} (권한: 600)")
            return output_path
            
        except Exception as e:
            self.logger.error(f".env.runtime 파일 생성 실패: {str(e)}")
            raise
    
    def validate_required_secrets(self, config: Dict[str, str], required_secrets: list = None) -> bool:
        """필수 비밀 정보 검증"""
        if required_secrets is None:
            # 기본 필수 비밀 정보 목록
            required_secrets = [
                'SLACK_WEBHOOK_URL',  # Slack 알림용
            ]
        
        missing_secrets = []
        for secret in required_secrets:
            if secret not in config or not config[secret]:
                missing_secrets.append(secret)
        
        if missing_secrets:
            self.logger.error(f"필수 비밀 정보가 누락되었습니다: {', '.join(missing_secrets)}")
            return False
        
        self.logger.info("모든 필수 비밀 정보가 확인되었습니다.")
        return True
    
    def generate_env_runtime(self, validate_secrets: bool = True, required_secrets: list = None) -> str:
        """전체 프로세스 실행: SSM 조회 → 구성 병합 → 파일 생성"""
        try:
            self.logger.info("환경 파일 생성 프로세스 시작")
            
            # 1. 공개 구성 로드
            public_config = self.load_public_config()
            
            # 2. SSM 비밀 조회
            ssm_secrets = self.fetch_ssm_secrets()
            
            # 3. 구성 병합
            merged_config = self.merge_configs(public_config, ssm_secrets)
            
            # 4. 필수 비밀 검증 (옵션)
            if validate_secrets:
                if not self.validate_required_secrets(merged_config, required_secrets):
                    raise ValueError("필수 비밀 정보 검증 실패")
            
            # 5. .env.runtime 파일 생성
            output_path = self.write_env_runtime(merged_config)
            
            self.logger.info("환경 파일 생성 프로세스 완료")
            return output_path
            
        except Exception as e:
            self.logger.error(f"환경 파일 생성 프로세스 실패: {str(e)}")
            raise
    
    def _get_current_timestamp(self) -> str:
        """현재 타임스탬프 반환"""
        from datetime import datetime
        return datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC')


def main():
    """메인 함수"""
    parser = argparse.ArgumentParser(
        description="AWS SSM Parameter Store에서 비밀 정보를 가져와 .env.runtime 파일을 생성합니다."
    )
    
    parser.add_argument(
        'environment',
        help='배포 환경 (예: prod, staging)'
    )
    
    parser.add_argument(
        '--output', '-o',
        help='출력 파일 경로 (기본값: .env.runtime)',
        default=None
    )
    
    parser.add_argument(
        '--no-validate',
        action='store_true',
        help='필수 비밀 정보 검증 건너뛰기'
    )
    
    parser.add_argument(
        '--required-secrets',
        nargs='*',
        help='필수 비밀 정보 목록 (공백으로 구분)',
        default=None
    )
    
    args = parser.parse_args()
    
    # 로거 초기화
    logger = Logger("fetch_secrets")
    
    try:
        # SecretsFetcher 초기화
        fetcher = SecretsFetcher(args.environment)
        
        # 환경 파일 생성
        output_path = fetcher.generate_env_runtime(
            validate_secrets=not args.no_validate,
            required_secrets=args.required_secrets
        )
        
        logger.info(f"성공: {output_path}")
        print(f"SUCCESS: {output_path}")
        
    except Exception as e:
        logger.error(f"실패: {str(e)}")
        print(f"ERROR: {str(e)}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()