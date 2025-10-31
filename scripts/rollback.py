#!/usr/bin/env python3
"""
자동 롤백 시스템
이전 성공한 배포로 롤백을 수행합니다.
"""

import os
import sys
import argparse
import subprocess
from typing import Dict, Optional

# 현재 스크립트 디렉토리를 Python 경로에 추가
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from utils import Logger, SlackNotifier, load_env_file
from release_manager import ReleaseManager


class RollbackManager:
    """롤백 관리"""
    
    def __init__(self, environment: str, service_kind: str):
        self.environment = environment
        self.service_kind = service_kind
        self.logger = Logger(f"RollbackManager-{environment}-{service_kind}")
        
        # 릴리스 매니저 초기화
        self.release_manager = ReleaseManager()
        
        # Slack 알림 초기화
        self.slack_notifier = SlackNotifier()
        
        # 프로젝트 루트 디렉토리
        self.project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        
        # 환경 변수 로드
        self._load_environment_variables()
        
        self.logger.info(f"RollbackManager 초기화 완료 (환경: {environment}, 서비스: {service_kind})")
    
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
    
    def execute_rollback(self, target_deployment_id: str = None) -> bool:
        """롤백 실행"""
        try:
            self.logger.info("롤백 프로세스 시작")
            
            # 1. 롤백 대상 결정
            rollback_target = self._determine_rollback_target(target_deployment_id)
            if not rollback_target:
                self.logger.error("롤백 대상을 찾을 수 없습니다.")
                return False
            
            self.logger.info(f"롤백 대상: {rollback_target['deployment_id']} (다이제스트: {rollback_target['image_digest']})")
            
            # 2. 롤백 전 검증
            if not self._validate_rollback_target(rollback_target):
                self.logger.error("롤백 대상 검증 실패")
                return False
            
            # 3. 현재 서비스 중지
            if not self._stop_current_services():
                self.logger.error("현재 서비스 중지 실패")
                return False
            
            # 4. 이전 이미지로 배포
            if not self._deploy_rollback_image(rollback_target):
                self.logger.error("롤백 이미지 배포 실패")
                return False
            
            # 5. 롤백 후 헬스 체크
            if not self._verify_rollback_health():
                self.logger.error("롤백 후 헬스 체크 실패")
                return False
            
            # 6. 롤백 완료 처리
            self._finalize_rollback(rollback_target)
            
            self.logger.info("롤백 프로세스 완료")
            return True
            
        except Exception as e:
            self.logger.error(f"롤백 실행 중 예외 발생: {str(e)}")
            return False
    
    def _determine_rollback_target(self, target_deployment_id: str = None) -> Optional[Dict]:
        """롤백 대상 결정"""
        try:
            if target_deployment_id:
                # 특정 배포 ID로 롤백
                target = self.release_manager.get_deployment_record(target_deployment_id)
                if target and target.get('status') == 'success':
                    self.logger.info(f"지정된 배포로 롤백: {target_deployment_id}")
                    return target
                else:
                    self.logger.error(f"지정된 배포를 찾을 수 없거나 성공 상태가 아닙니다: {target_deployment_id}")
                    return None
            else:
                # 가장 최근 성공한 배포로 롤백
                target = self.release_manager.get_rollback_target(
                    self.service_kind, 
                    self.environment
                )
                if target:
                    self.logger.info(f"최근 성공 배포로 롤백: {target['deployment_id']}")
                    return target
                else:
                    self.logger.error("롤백할 성공한 배포를 찾을 수 없습니다.")
                    return None
                    
        except Exception as e:
            self.logger.error(f"롤백 대상 결정 실패: {str(e)}")
            return None
    
    def _validate_rollback_target(self, rollback_target: Dict) -> bool:
        """롤백 대상 검증"""
        try:
            # 필수 필드 확인
            required_fields = ['deployment_id', 'image_digest', 'image_tag']
            for field in required_fields:
                if not rollback_target.get(field):
                    self.logger.error(f"롤백 대상에 필수 필드가 없습니다: {field}")
                    return False
            
            # 다이제스트 형식 검증
            if not self.release_manager.validate_digest(rollback_target['image_digest']):
                self.logger.error("롤백 대상의 다이제스트 형식이 잘못되었습니다.")
                return False
            
            # 이미지 존재 확인
            if not self._verify_image_exists(rollback_target['image_digest']):
                self.logger.error("롤백 대상 이미지를 찾을 수 없습니다.")
                return False
            
            self.logger.info("롤백 대상 검증 통과")
            return True
            
        except Exception as e:
            self.logger.error(f"롤백 대상 검증 실패: {str(e)}")
            return False
    
    def _verify_image_exists(self, image_digest: str) -> bool:
        """이미지 존재 확인"""
        try:
            # Docker 레지스트리에서 이미지 존재 확인
            registry = os.environ.get('DOCKER_REGISTRY', 'docker.io')
            repo_hub = os.environ.get('DOCKER_REPO_HUB', '42tape')
            
            # 다이제스트로 이미지 참조
            image_ref = f"{registry}/{repo_hub}/app@{image_digest}"
            
            # docker manifest inspect로 이미지 존재 확인
            result = subprocess.run(
                ['docker', 'manifest', 'inspect', image_ref],
                capture_output=True,
                text=True,
                timeout=30
            )
            
            if result.returncode == 0:
                self.logger.info(f"롤백 이미지 존재 확인: {image_ref}")
                return True
            else:
                self.logger.error(f"롤백 이미지 존재하지 않음: {image_ref}")
                return False
                
        except subprocess.TimeoutExpired:
            self.logger.error("이미지 존재 확인 시간 초과")
            return False
        except Exception as e:
            self.logger.error(f"이미지 존재 확인 실패: {str(e)}")
            return False
    
    def _stop_current_services(self) -> bool:
        """현재 서비스 중지"""
        try:
            self.logger.info("현재 서비스 중지")
            
            # Docker Compose로 서비스 중지
            result = subprocess.run(
                ['docker', 'compose', 'down'],
                capture_output=True,
                text=True,
                cwd=self.project_root,
                timeout=120
            )
            
            if result.returncode == 0:
                self.logger.info("현재 서비스 중지 완료")
                return True
            else:
                self.logger.error(f"서비스 중지 실패: {result.stderr}")
                return False
                
        except subprocess.TimeoutExpired:
            self.logger.error("서비스 중지 시간 초과")
            return False
        except Exception as e:
            self.logger.error(f"서비스 중지 실패: {str(e)}")
            return False
    
    def _deploy_rollback_image(self, rollback_target: Dict) -> bool:
        """롤백 이미지 배포"""
        try:
            self.logger.info("롤백 이미지 배포 시작")
            
            # 환경 변수에 롤백 이미지 정보 설정
            os.environ['ROLLBACK_IMAGE_DIGEST'] = rollback_target['image_digest']
            os.environ['ROLLBACK_IMAGE_TAG'] = rollback_target['image_tag']
            
            # Docker Compose 파일에서 이미지를 다이제스트로 참조하도록 수정
            if not self._update_compose_for_rollback(rollback_target):
                self.logger.error("Docker Compose 파일 업데이트 실패")
                return False
            
            # Docker Compose로 서비스 시작
            result = subprocess.run(
                ['docker', 'compose', 'up', '-d', '--remove-orphans'],
                capture_output=True,
                text=True,
                cwd=self.project_root,
                timeout=300
            )
            
            if result.returncode == 0:
                self.logger.info("롤백 이미지 배포 완료")
                return True
            else:
                self.logger.error(f"롤백 이미지 배포 실패: {result.stderr}")
                return False
                
        except subprocess.TimeoutExpired:
            self.logger.error("롤백 이미지 배포 시간 초과")
            return False
        except Exception as e:
            self.logger.error(f"롤백 이미지 배포 실패: {str(e)}")
            return False
    
    def _update_compose_for_rollback(self, rollback_target: Dict) -> bool:
        """롤백을 위한 Docker Compose 파일 업데이트"""
        try:
            # 실제 구현에서는 Docker Compose 파일을 동적으로 수정하거나
            # 환경 변수를 통해 이미지를 지정할 수 있도록 구성
            
            # 여기서는 환경 변수를 통한 방식 사용
            registry = os.environ.get('DOCKER_REGISTRY', 'docker.io')
            repo_hub = os.environ.get('DOCKER_REPO_HUB', '42tape')
            
            # 다이제스트로 이미지 참조
            rollback_image = f"{registry}/{repo_hub}/app@{rollback_target['image_digest']}"
            
            # 환경 변수에 롤백 이미지 설정
            os.environ['DEPLOY_IMAGE'] = rollback_image
            
            self.logger.info(f"롤백 이미지 설정: {rollback_image}")
            return True
            
        except Exception as e:
            self.logger.error(f"Docker Compose 파일 업데이트 실패: {str(e)}")
            return False
    
    def _verify_rollback_health(self) -> bool:
        """롤백 후 헬스 체크"""
        try:
            self.logger.info("롤백 후 헬스 체크 시작")
            
            # post_deploy.py 스크립트를 사용하여 헬스 체크
            post_deploy_script = os.path.join(
                os.path.dirname(os.path.abspath(__file__)),
                'post_deploy.py'
            )
            
            if not os.path.exists(post_deploy_script):
                self.logger.error("post_deploy.py 스크립트를 찾을 수 없습니다.")
                return False
            
            # 헬스 체크 실행 (자동 롤백 비활성화)
            result = subprocess.run(
                [
                    'python', post_deploy_script,
                    self.environment, self.service_kind,
                    '--max-retries', '3',
                    '--retry-delay', '20'
                ],
                capture_output=True,
                text=True,
                timeout=300
            )
            
            if result.returncode == 0:
                self.logger.info("롤백 후 헬스 체크 성공")
                return True
            else:
                self.logger.error(f"롤백 후 헬스 체크 실패: {result.stderr}")
                return False
                
        except subprocess.TimeoutExpired:
            self.logger.error("롤백 후 헬스 체크 시간 초과")
            return False
        except Exception as e:
            self.logger.error(f"롤백 후 헬스 체크 실패: {str(e)}")
            return False
    
    def _finalize_rollback(self, rollback_target: Dict):
        """롤백 완료 처리"""
        try:
            # 롤백 알림 전송
            rollback_info = {
                'environment': self.environment,
                'service_kind': self.service_kind,
                'rollback_target': rollback_target['deployment_id'],
                'rollback_version': rollback_target.get('version', 'unknown'),
            }
            
            self.slack_notifier.send_rollback_notification(
                rollback_info,
                rollback_target['image_digest']
            )
            
            self.logger.info("롤백 완료 알림 전송")
            
        except Exception as e:
            self.logger.error(f"롤백 완료 처리 실패: {str(e)}")
    
    def list_rollback_candidates(self) -> list:
        """롤백 가능한 배포 목록 조회"""
        try:
            candidates = self.release_manager.list_deployments(
                service_kind=self.service_kind,
                environment=self.environment,
                status='success',
                limit=10
            )
            
            self.logger.info(f"롤백 가능한 배포 {len(candidates)}개 조회")
            return candidates
            
        except Exception as e:
            self.logger.error(f"롤백 후보 조회 실패: {str(e)}")
            return []
    
    def dry_run_rollback(self, target_deployment_id: str = None) -> bool:
        """롤백 시뮬레이션 (실제 실행 없이 검증만)"""
        try:
            self.logger.info("롤백 시뮬레이션 시작")
            
            # 1. 롤백 대상 결정
            rollback_target = self._determine_rollback_target(target_deployment_id)
            if not rollback_target:
                self.logger.error("롤백 대상을 찾을 수 없습니다.")
                return False
            
            # 2. 롤백 대상 검증
            if not self._validate_rollback_target(rollback_target):
                self.logger.error("롤백 대상 검증 실패")
                return False
            
            self.logger.info(f"롤백 시뮬레이션 성공: {rollback_target['deployment_id']}")
            return True
            
        except Exception as e:
            self.logger.error(f"롤백 시뮬레이션 실패: {str(e)}")
            return False


def main():
    """메인 함수"""
    parser = argparse.ArgumentParser(description="자동 롤백 시스템")
    
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
        '--target-deployment-id',
        help='롤백할 특정 배포 ID (지정하지 않으면 최근 성공 배포로 롤백)'
    )
    
    parser.add_argument(
        '--list-candidates',
        action='store_true',
        help='롤백 가능한 배포 목록 조회'
    )
    
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='실제 롤백 없이 시뮬레이션만 실행'
    )
    
    args = parser.parse_args()
    
    # 환경 변수 설정
    os.environ['ENVIRONMENT'] = args.environment
    os.environ['SERVICE_KIND'] = args.service_kind
    
    # 로거 초기화
    logger = Logger("rollback")
    
    try:
        # RollbackManager 초기화
        rollback_manager = RollbackManager(args.environment, args.service_kind)
        
        if args.list_candidates:
            # 롤백 후보 목록 조회
            candidates = rollback_manager.list_rollback_candidates()
            
            print(f"롤백 가능한 배포 목록 ({len(candidates)}개):")
            for candidate in candidates:
                print(f"  {candidate['deployment_id']} - {candidate['version']} - {candidate['timestamp']}")
            
        elif args.dry_run:
            # 롤백 시뮬레이션
            success = rollback_manager.dry_run_rollback(args.target_deployment_id)
            
            if success:
                print("SUCCESS: Rollback simulation passed")
            else:
                print("ERROR: Rollback simulation failed", file=sys.stderr)
                sys.exit(1)
                
        else:
            # 실제 롤백 실행
            success = rollback_manager.execute_rollback(args.target_deployment_id)
            
            if success:
                logger.info("롤백 성공")
                print("SUCCESS: Rollback completed successfully")
            else:
                logger.error("롤백 실패")
                print("ERROR: Rollback failed", file=sys.stderr)
                sys.exit(1)
        
    except Exception as e:
        logger.error(f"롤백 프로세스 중 예외 발생: {str(e)}")
        print(f"ERROR: {str(e)}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()