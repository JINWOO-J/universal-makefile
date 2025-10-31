#!/usr/bin/env python3
"""
Docker 이미지 빌드 및 레지스트리 관리
이미지 태그 생성, 빌드, 푸시, 다이제스트 관리를 담당합니다.
"""

import os
import sys
import subprocess
import re
from typing import Dict, Optional, Tuple
from datetime import datetime

# 현재 스크립트 디렉토리를 Python 경로에 추가
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from utils import Logger


class DockerImageManager:
    """Docker 이미지 관리"""
    
    def __init__(self, registry: Optional[str] = None, repo_hub: Optional[str] = None):
        self.logger = Logger("DockerImageManager")
        self.registry = registry or os.environ.get('DOCKER_REGISTRY', 'docker.io')
        self.repo_hub = repo_hub or os.environ.get('DOCKER_REPO_HUB', 'mycompany')
        
        # 프로젝트 루트 디렉토리
        self.project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        
        self.logger.info(f"DockerImageManager 초기화 완료 (레지스트리: {self.registry}, 허브: {self.repo_hub})")
    
    def generate_image_tag(self, 
                          image_name: str,
                          service_kind: str,
                          version: str,
                          branch: str,
                          commit_sha: Optional[str] = None) -> str:
        """
        Docker 이미지 태그 생성
        형식: {registry}/{repo_hub}/{image_name}:{service_kind}-{version}-{branch}-{date}-{sha8}
        """
        try:
            # 현재 날짜 (YYYYMMDD 형식)
            current_date = datetime.now().strftime('%Y%m%d')
            
            # 커밋 SHA가 없으면 현재 Git SHA 조회 시도
            if not commit_sha:
                commit_sha = self._get_current_git_sha()
            
            # SHA를 8자리로 자르기
            sha8 = commit_sha[:8] if commit_sha else 'unknown'
            
            # 브랜치명에서 특수문자 제거 (Docker 태그 규칙 준수)
            clean_branch = self._clean_branch_name(branch)
            
            # 태그 생성
            tag_suffix = f"{service_kind}-{version}-{clean_branch}-{current_date}-{sha8}"
            full_tag = f"{self.registry}/{self.repo_hub}/{image_name}:{tag_suffix}"
            
            self.logger.info(f"이미지 태그 생성: {full_tag}")
            return full_tag
            
        except Exception as e:
            self.logger.error(f"이미지 태그 생성 실패: {str(e)}")
            raise
    
    def _get_current_git_sha(self) -> Optional[str]:
        """현재 Git 커밋 SHA 조회"""
        try:
            result = subprocess.run(
                ['git', 'rev-parse', 'HEAD'],
                capture_output=True,
                text=True,
                cwd=self.project_root
            )
            
            if result.returncode == 0:
                sha = result.stdout.strip()
                self.logger.debug(f"현재 Git SHA: {sha}")
                return sha
            else:
                self.logger.warning("Git SHA 조회 실패")
                return None
                
        except Exception as e:
            self.logger.warning(f"Git SHA 조회 중 예외: {str(e)}")
            return None
    
    def _clean_branch_name(self, branch: str) -> str:
        """브랜치명을 Docker 태그 규칙에 맞게 정리"""
        # 슬래시를 하이픈으로 변경 (feature/abc -> feature-abc)
        clean_name = branch.replace('/', '-')
        
        # Docker 태그에서 허용되지 않는 문자 제거
        clean_name = re.sub(r'[^a-zA-Z0-9._-]', '', clean_name)
        
        # 연속된 하이픈 제거
        clean_name = re.sub(r'-+', '-', clean_name)
        
        # 앞뒤 하이픈 제거
        clean_name = clean_name.strip('-')
        
        return clean_name or 'unknown'
    
    def build_image(self, 
                   dockerfile_path: str,
                   context_path: str,
                   image_tag: str,
                   build_args: Optional[Dict[str, str]] = None) -> bool:
        """Docker 이미지 빌드 (실시간 출력)"""
        try:
            self.logger.info(f"Docker 이미지 빌드 시작: {image_tag}")
            
            # Docker 빌드 명령 구성
            cmd = [
                'docker', 'build',
                '-f', dockerfile_path,
                '-t', image_tag,
                context_path
            ]
            
            # 빌드 인수 추가
            if build_args:
                for key, value in build_args.items():
                    cmd.extend(['--build-arg', f'{key}={value}'])
            
            # Docker Buildkit 활성화
            env = os.environ.copy()
            env['DOCKER_BUILDKIT'] = '1'
            
            self.logger.info(f"빌드 명령 실행: {' '.join(cmd)}")
            print(f"\n{'='*60}")
            print(f"🔨 Docker 빌드 시작: {image_tag}")
            print(f"{'='*60}\n")
            
            # 빌드 실행 (실시간 출력)
            process = subprocess.Popen(
                cmd,
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1
            )
            
            # 실시간으로 출력 스트리밍
            output_lines = []
            try:
                if process.stdout:
                    for line in process.stdout:
                        print(line, end='')  # 실시간 출력
                        output_lines.append(line)
                
                # 프로세스 종료 대기
                return_code = process.wait()
                
            except KeyboardInterrupt:
                self.logger.warning("빌드가 사용자에 의해 중단되었습니다.")
                process.terminate()
                process.wait()
                print(f"\n{'='*60}")
                print(f"❌ 빌드 중단됨")
                print(f"{'='*60}\n")
                return False
            
            # 결과 처리
            if return_code == 0:
                print(f"\n{'='*60}")
                print(f"✅ Docker 이미지 빌드 성공: {image_tag}")
                print(f"{'='*60}\n")
                self.logger.info(f"Docker 이미지 빌드 성공: {image_tag}")
                return True
            else:
                print(f"\n{'='*60}")
                print(f"❌ Docker 이미지 빌드 실패 (exit code: {return_code})")
                print(f"{'='*60}\n")
                self.logger.error(f"Docker 이미지 빌드 실패 (exit code: {return_code})")
                
                # 에러 로그 출력 (마지막 20줄)
                if output_lines:
                    print("\n마지막 에러 로그:")
                    print("-" * 60)
                    for line in output_lines[-20:]:
                        print(line, end='')
                    print("-" * 60)
                
                return False
                
        except Exception as e:
            print(f"\n{'='*60}")
            print(f"❌ Docker 이미지 빌드 중 예외 발생: {str(e)}")
            print(f"{'='*60}\n")
            self.logger.error(f"Docker 이미지 빌드 중 예외 발생: {str(e)}")
            return False
    
    def push_image(self, image_tag: str) -> Optional[str]:
        """Docker 이미지 푸시 및 다이제스트 반환 (실시간 출력)"""
        try:
            self.logger.info(f"Docker 이미지 푸시 시작: {image_tag}")
            print(f"\n{'='*60}")
            print(f"📤 Docker 이미지 푸시 시작: {image_tag}")
            print(f"{'='*60}\n")
            
            # 푸시 명령 실행 (실시간 출력)
            process = subprocess.Popen(
                ['docker', 'push', image_tag],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1
            )
            
            # 실시간으로 출력 스트리밍
            output_lines = []
            try:
                if process.stdout:
                    for line in process.stdout:
                        print(line, end='')  # 실시간 출력
                        output_lines.append(line)
                
                # 프로세스 종료 대기
                return_code = process.wait()
                
            except KeyboardInterrupt:
                self.logger.warning("푸시가 사용자에 의해 중단되었습니다.")
                process.terminate()
                process.wait()
                print(f"\n{'='*60}")
                print(f"❌ 푸시 중단됨")
                print(f"{'='*60}\n")
                return None
            
            # 결과 처리
            if return_code == 0:
                print(f"\n{'='*60}")
                print(f"✅ Docker 이미지 푸시 성공: {image_tag}")
                print(f"{'='*60}\n")
                self.logger.info(f"Docker 이미지 푸시 성공: {image_tag}")
                
                # 다이제스트 조회
                digest = self._get_image_digest(image_tag)
                if digest:
                    print(f"📋 이미지 다이제스트: {digest}\n")
                    self.logger.info(f"이미지 다이제스트: {digest}")
                    return digest
                else:
                    print(f"⚠️  이미지 다이제스트 조회 실패\n")
                    self.logger.warning("이미지 다이제스트 조회 실패")
                    return None
            else:
                print(f"\n{'='*60}")
                print(f"❌ Docker 이미지 푸시 실패 (exit code: {return_code})")
                print(f"{'='*60}\n")
                self.logger.error(f"Docker 이미지 푸시 실패 (exit code: {return_code})")
                
                # 에러 로그 출력
                if output_lines:
                    print("\n에러 로그:")
                    print("-" * 60)
                    for line in output_lines[-10:]:
                        print(line, end='')
                    print("-" * 60)
                
                return None
                
        except Exception as e:
            print(f"\n{'='*60}")
            print(f"❌ Docker 이미지 푸시 중 예외 발생: {str(e)}")
            print(f"{'='*60}\n")
            self.logger.error(f"Docker 이미지 푸시 중 예외 발생: {str(e)}")
            return None
    
    def _get_image_digest(self, image_tag: str) -> Optional[str]:
        """이미지 다이제스트 조회"""
        try:
            # docker inspect를 사용하여 다이제스트 조회
            result = subprocess.run(
                ['docker', 'inspect', '--format={{index .RepoDigests 0}}', image_tag],
                capture_output=True,
                text=True
            )
            
            if result.returncode == 0:
                repo_digest = result.stdout.strip()
                if repo_digest and '@sha256:' in repo_digest:
                    # 다이제스트 부분만 추출
                    digest = repo_digest.split('@')[1]
                    return digest
                else:
                    self.logger.warning(f"유효하지 않은 다이제스트 형식: {repo_digest}")
                    return None
            else:
                self.logger.error(f"다이제스트 조회 실패: {result.stderr}")
                return None
                
        except Exception as e:
            self.logger.error(f"다이제스트 조회 중 예외 발생: {str(e)}")
            return None
    
    def build_and_push(self,
                      dockerfile_path: str,
                      context_path: str,
                      image_name: str,
                      service_kind: str,
                      version: str,
                      branch: str,
                      commit_sha: Optional[str] = None,
                      build_args: Optional[Dict[str, str]] = None) -> Tuple[Optional[str], Optional[str]]:
        """이미지 빌드 및 푸시 통합 실행"""
        try:
            # 이미지 태그 생성
            image_tag = self.generate_image_tag(
                image_name, service_kind, version, branch, commit_sha
            )
            
            # 이미지 빌드
            if not self.build_image(dockerfile_path, context_path, image_tag, build_args):
                return None, None
            
            # 이미지 푸시
            digest = self.push_image(image_tag)
            if not digest:
                return image_tag, None
            
            return image_tag, digest
            
        except Exception as e:
            self.logger.error(f"빌드 및 푸시 프로세스 실패: {str(e)}")
            return None, None
    
    def validate_dockerfile(self, dockerfile_path: str) -> bool:
        """Dockerfile 유효성 검사"""
        try:
            if not os.path.exists(dockerfile_path):
                self.logger.error(f"Dockerfile을 찾을 수 없습니다: {dockerfile_path}")
                return False
            
            # 기본적인 Dockerfile 구문 검사
            with open(dockerfile_path, 'r', encoding='utf-8') as f:
                content = f.read()
            
            # FROM 명령어가 있는지 확인
            if not re.search(r'^FROM\s+\S+', content, re.MULTILINE | re.IGNORECASE):
                self.logger.error("Dockerfile에 FROM 명령어가 없습니다.")
                return False
            
            self.logger.info(f"Dockerfile 유효성 검사 통과: {dockerfile_path}")
            return True
            
        except Exception as e:
            self.logger.error(f"Dockerfile 유효성 검사 실패: {str(e)}")
            return False
    
    def cleanup_old_images(self, keep_count: int = 5) -> bool:
        """오래된 이미지 정리"""
        try:
            self.logger.info(f"오래된 이미지 정리 시작 (보관 개수: {keep_count})")
            
            # dangling 이미지 제거
            result = subprocess.run(
                ['docker', 'image', 'prune', '-f'],
                capture_output=True,
                text=True
            )
            
            if result.returncode == 0:
                self.logger.info("Dangling 이미지 정리 완료")
            else:
                self.logger.warning(f"Dangling 이미지 정리 실패: {result.stderr}")
            
            # 추가적인 정리 로직은 필요에 따라 구현
            return True
            
        except Exception as e:
            self.logger.error(f"이미지 정리 중 예외 발생: {str(e)}")
            return False


def main():
    """메인 함수 - 테스트용"""
    import argparse
    
    parser = argparse.ArgumentParser(description="Docker 이미지 관리 도구")
    parser.add_argument('action', choices=['build', 'push', 'build-push', 'tag'], help='실행할 작업')
    parser.add_argument('--dockerfile', required=True, help='Dockerfile 경로')
    parser.add_argument('--context', default='.', help='빌드 컨텍스트 경로')
    parser.add_argument('--image-name', required=True, help='이미지 이름')
    parser.add_argument('--service-kind', required=True, help='서비스 종류 (fe/be)')
    parser.add_argument('--version', required=True, help='버전')
    parser.add_argument('--branch', required=True, help='브랜치명')
    parser.add_argument('--commit-sha', help='커밋 SHA')
    parser.add_argument('--build-arg', action='append', dest='build_args',
                       help='Docker 빌드 인자 (KEY=VALUE 형식, 여러 번 사용 가능)')
    
    args = parser.parse_args()
    
    # build_args 파싱
    build_args_dict = {}
    if args.build_args:
        for arg in args.build_args:
            if '=' in arg:
                key, value = arg.split('=', 1)
                build_args_dict[key] = value
            else:
                print(f"Warning: Invalid build-arg format '{arg}', expected KEY=VALUE", file=sys.stderr)
    
    # DockerImageManager 초기화
    manager = DockerImageManager()
    
    try:
        if args.action == 'tag':
            # 태그만 생성
            tag = manager.generate_image_tag(
                args.image_name, args.service_kind, args.version, 
                args.branch, args.commit_sha
            )
            print(f"Generated tag: {tag}")
            
        elif args.action == 'build':
            # 빌드만 실행
            tag = manager.generate_image_tag(
                args.image_name, args.service_kind, args.version, 
                args.branch, args.commit_sha
            )
            success = manager.build_image(args.dockerfile, args.context, tag, build_args=build_args_dict if build_args_dict else None)
            print(f"Build {'success' if success else 'failed'}: {tag}")
            
        elif args.action == 'push':
            # 푸시만 실행 (이미 빌드된 이미지)
            tag = manager.generate_image_tag(
                args.image_name, args.service_kind, args.version, 
                args.branch, args.commit_sha
            )
            digest = manager.push_image(tag)
            print(f"Push {'success' if digest else 'failed'}: {tag}")
            if digest:
                print(f"Digest: {digest}")
                
        elif args.action == 'build-push':
            # 빌드 및 푸시 통합 실행
            tag, digest = manager.build_and_push(
                args.dockerfile, args.context, args.image_name,
                args.service_kind, args.version, args.branch, args.commit_sha,
                build_args=build_args_dict if build_args_dict else None
            )
            
            if tag and digest:
                print(f"Build and push success: {tag}")
                print(f"Digest: {digest}")
            else:
                print("Build and push failed")
                sys.exit(1)
                
    except Exception as e:
        print(f"Error: {str(e)}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()