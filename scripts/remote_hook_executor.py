#!/usr/bin/env python3
"""
원격 훅 실행기 - URL에서 스크립트를 다운로드하여 실행
보안을 고려한 원격 스크립트 실행 시스템
"""

import os
import sys
import hashlib
import tempfile
import subprocess
import requests
from typing import Dict, List, Optional, Tuple
from urllib.parse import urlparse

# 현재 스크립트 디렉토리를 Python 경로에 추가
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from utils import Logger


class RemoteHookExecutor:
    """원격 훅 실행기"""
    
    def __init__(self, environment: str, service_kind: str):
        self.environment = environment
        self.service_kind = service_kind
        self.logger = Logger(f"RemoteHookExecutor-{environment}-{service_kind}")
        
        # 보안 설정
        self.allowed_domains = self._get_allowed_domains()
        self.verify_ssl = os.environ.get('VERIFY_SSL', 'true').lower() == 'true'
        self.max_script_size = int(os.environ.get('MAX_SCRIPT_SIZE', '1048576'))  # 1MB
        
        # 캐시 디렉토리
        self.cache_dir = os.path.join(tempfile.gettempdir(), 'deploy_hooks_cache')
        os.makedirs(self.cache_dir, exist_ok=True)
    
    def _get_allowed_domains(self) -> List[str]:
        """허용된 도메인 목록 반환"""
        allowed = os.environ.get('ALLOWED_HOOK_DOMAINS', '').split(',')
        allowed = [domain.strip() for domain in allowed if domain.strip()]
        
        # 기본 허용 도메인
        default_domains = [
            'raw.githubusercontent.com',
            'gist.githubusercontent.com',
        ]
        
        return list(set(allowed + default_domains))
    
    def execute_remote_hook(self, 
                          hook_url: str, 
                          hook_type: str = 'script',
                          expected_hash: Optional[str] = None,
                          args: Optional[List[str]] = None) -> bool:
        """원격 훅 실행"""
        try:
            self.logger.info(f"원격 훅 실행: {hook_url}")
            
            # URL 검증
            if not self._validate_url(hook_url):
                self.logger.error(f"허용되지 않은 URL: {hook_url}")
                return False
            
            # 스크립트 다운로드
            script_content = self._download_script(hook_url)
            if not script_content:
                return False
            
            # 해시 검증 (제공된 경우)
            if expected_hash and not self._verify_hash(script_content, expected_hash):
                self.logger.error("스크립트 해시 검증 실패")
                return False
            
            # 스크립트 실행
            return self._execute_script(script_content, hook_type, args or [])
            
        except Exception as e:
            self.logger.error(f"원격 훅 실행 실패: {str(e)}")
            return False
    
    def _validate_url(self, url: str) -> bool:
        """URL 유효성 검사"""
        try:
            parsed = urlparse(url)
            
            # HTTPS만 허용
            if parsed.scheme != 'https':
                self.logger.error(f"HTTPS가 아닌 URL: {url}")
                return False
            
            # 허용된 도메인 확인
            if self.allowed_domains and parsed.netloc not in self.allowed_domains:
                self.logger.error(f"허용되지 않은 도메인: {parsed.netloc}")
                return False
            
            return True
            
        except Exception as e:
            self.logger.error(f"URL 검증 실패: {str(e)}")
            return False
    
    def _download_script(self, url: str) -> Optional[str]:
        """스크립트 다운로드"""
        try:
            # 캐시 확인
            cache_key = hashlib.md5(url.encode()).hexdigest()
            cache_file = os.path.join(self.cache_dir, f"{cache_key}.cache")
            
            # 캐시된 파일이 있고 최근 것이면 사용
            if os.path.exists(cache_file):
                cache_age = time.time() - os.path.getmtime(cache_file)
                max_cache_age = int(os.environ.get('HOOK_CACHE_TTL', '3600'))  # 1시간
                
                if cache_age < max_cache_age:
                    with open(cache_file, 'r', encoding='utf-8') as f:
                        self.logger.info("캐시된 스크립트 사용")
                        return f.read()
            
            # 다운로드
            headers = {
                'User-Agent': 'Universal-Makefile-Deploy-Hook/1.0'
            }
            
            # 인증 토큰이 있으면 추가
            auth_token = os.environ.get('HOOK_AUTH_TOKEN')
            if auth_token:
                headers['Authorization'] = f'Bearer {auth_token}'
            
            response = requests.get(
                url, 
                headers=headers,
                verify=self.verify_ssl,
                timeout=30,
                stream=True
            )
            
            response.raise_for_status()
            
            # 크기 제한 확인
            content_length = response.headers.get('content-length')
            if content_length and int(content_length) > self.max_script_size:
                self.logger.error(f"스크립트 크기 초과: {content_length} bytes")
                return None
            
            # 내용 읽기
            content = ''
            total_size = 0
            
            for chunk in response.iter_content(chunk_size=8192, decode_unicode=True):
                if chunk:
                    total_size += len(chunk.encode('utf-8'))
                    if total_size > self.max_script_size:
                        self.logger.error(f"스크립트 크기 초과: {total_size} bytes")
                        return None
                    content += chunk
            
            # 캐시에 저장
            with open(cache_file, 'w', encoding='utf-8') as f:
                f.write(content)
            
            self.logger.info(f"스크립트 다운로드 완료: {len(content)} bytes")
            return content
            
        except requests.RequestException as e:
            self.logger.error(f"스크립트 다운로드 실패: {str(e)}")
            return None
        except Exception as e:
            self.logger.error(f"스크립트 다운로드 중 예외: {str(e)}")
            return None
    
    def _verify_hash(self, content: str, expected_hash: str) -> bool:
        """스크립트 해시 검증"""
        try:
            # SHA256 해시 계산
            actual_hash = hashlib.sha256(content.encode('utf-8')).hexdigest()
            
            if actual_hash == expected_hash:
                self.logger.info("스크립트 해시 검증 성공")
                return True
            else:
                self.logger.error(f"해시 불일치: expected={expected_hash}, actual={actual_hash}")
                return False
                
        except Exception as e:
            self.logger.error(f"해시 검증 실패: {str(e)}")
            return False
    
    def _execute_script(self, 
                       content: str, 
                       script_type: str, 
                       args: List[str]) -> bool:
        """스크립트 실행"""
        try:
            # 임시 파일 생성
            with tempfile.NamedTemporaryFile(
                mode='w', 
                suffix=self._get_script_extension(script_type),
                delete=False,
                encoding='utf-8'
            ) as temp_file:
                temp_file.write(content)
                temp_file_path = temp_file.name
            
            try:
                # 실행 권한 부여
                os.chmod(temp_file_path, 0o755)
                
                # 실행 명령 구성
                cmd = self._build_command(script_type, temp_file_path, args)
                
                # 환경 변수 설정
                env = os.environ.copy()
                env.update({
                    'ENVIRONMENT': self.environment,
                    'SERVICE_KIND': self.service_kind,
                    'HOOK_TYPE': script_type
                })
                
                # 스크립트 실행
                self.logger.info(f"스크립트 실행: {' '.join(cmd)}")
                
                result = subprocess.run(
                    cmd,
                    env=env,
                    capture_output=True,
                    text=True,
                    timeout=300  # 5분 타임아웃
                )
                
                # 결과 로깅
                if result.stdout:
                    self.logger.info(f"스크립트 출력: {result.stdout}")
                
                if result.stderr:
                    self.logger.warning(f"스크립트 에러: {result.stderr}")
                
                if result.returncode == 0:
                    self.logger.info("스크립트 실행 성공")
                    return True
                else:
                    self.logger.error(f"스크립트 실행 실패 (exit code: {result.returncode})")
                    return False
                    
            finally:
                # 임시 파일 정리
                try:
                    os.unlink(temp_file_path)
                except:
                    pass
                    
        except subprocess.TimeoutExpired:
            self.logger.error("스크립트 실행 시간 초과")
            return False
        except Exception as e:
            self.logger.error(f"스크립트 실행 실패: {str(e)}")
            return False
    
    def _get_script_extension(self, script_type: str) -> str:
        """스크립트 타입별 확장자 반환"""
        extensions = {
            'bash': '.sh',
            'shell': '.sh',
            'python': '.py',
            'node': '.js',
            'ruby': '.rb',
            'perl': '.pl'
        }
        return extensions.get(script_type, '.sh')
    
    def _build_command(self, script_type: str, script_path: str, args: List[str]) -> List[str]:
        """실행 명령 구성"""
        interpreters = {
            'bash': ['bash'],
            'shell': ['sh'],
            'python': ['python3'],
            'node': ['node'],
            'ruby': ['ruby'],
            'perl': ['perl']
        }
        
        if script_type in interpreters:
            return interpreters[script_type] + [script_path] + args
        else:
            # 기본값은 직접 실행
            return [script_path] + args


def main():
    """메인 함수"""
    import argparse
    import time
    
    parser = argparse.ArgumentParser(description="원격 훅 실행기")
    
    parser.add_argument('environment', help='배포 환경')
    parser.add_argument('service_kind', choices=['fe', 'be'], help='서비스 종류')
    parser.add_argument('hook_url', help='훅 스크립트 URL')
    
    parser.add_argument('--type', default='bash', help='스크립트 타입')
    parser.add_argument('--hash', help='예상 SHA256 해시')
    parser.add_argument('--args', nargs='*', default=[], help='스크립트 인자')
    
    args = parser.parse_args()
    
    try:
        executor = RemoteHookExecutor(args.environment, args.service_kind)
        
        success = executor.execute_remote_hook(
            args.hook_url,
            args.type,
            args.hash,
            args.args
        )
        
        if success:
            print("SUCCESS: Remote hook executed successfully")
            sys.exit(0)
        else:
            print("ERROR: Remote hook execution failed", file=sys.stderr)
            sys.exit(1)
            
    except Exception as e:
        print(f"ERROR: {str(e)}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()