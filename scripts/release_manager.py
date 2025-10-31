#!/usr/bin/env python3
"""
배포 히스토리 및 릴리스 관리
RELEASES 디렉토리에 배포 정보를 기록하고 관리합니다.
"""

import os
import sys
import json
from typing import Dict, List, Optional
from datetime import datetime

# 현재 스크립트 디렉토리를 Python 경로에 추가
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from utils import Logger, get_current_timestamp


class ReleaseManager:
    """릴리스 및 배포 히스토리 관리"""
    
    def __init__(self):
        self.logger = Logger("ReleaseManager")
        
        # 프로젝트 루트 및 RELEASES 디렉토리
        self.project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        self.releases_dir = os.path.join(self.project_root, 'RELEASES')
        
        # RELEASES 디렉토리 생성
        os.makedirs(self.releases_dir, exist_ok=True)
        
        self.logger.info(f"ReleaseManager 초기화 완료 (RELEASES: {self.releases_dir})")
    
    def create_deployment_record(self,
                               source_repo: str,
                               ref: str,
                               version: str,
                               service_kind: str,
                               environment: str,
                               image_tag: str,
                               image_digest: str,
                               status: str = "in_progress") -> str:
        """배포 기록 생성"""
        try:
            # 배포 ID 생성 (타임스탬프 기반)
            timestamp = get_current_timestamp()
            deployment_id = f"{timestamp}-{service_kind}-{environment}"
            
            # 배포 기록 데이터
            deployment_record = {
                "deployment_id": deployment_id,
                "timestamp": datetime.now().isoformat(),
                "source_repo": source_repo,
                "ref": ref,
                "version": version,
                "service_kind": service_kind,
                "environment": environment,
                "image_tag": image_tag,
                "image_digest": image_digest,
                "status": status,
                "rollback_digest": None,
                "created_at": datetime.now().isoformat(),
                "updated_at": datetime.now().isoformat()
            }
            
            # 파일 경로
            record_file = os.path.join(self.releases_dir, f"{deployment_id}.json")
            
            # 파일 저장
            with open(record_file, 'w', encoding='utf-8') as f:
                json.dump(deployment_record, f, indent=2, ensure_ascii=False)
            
            self.logger.info(f"배포 기록 생성: {deployment_id}")
            return deployment_id
            
        except Exception as e:
            self.logger.error(f"배포 기록 생성 실패: {str(e)}")
            raise
    
    def update_deployment_status(self, 
                               deployment_id: str, 
                               status: str, 
                               rollback_digest: str = None) -> bool:
        """배포 상태 업데이트"""
        try:
            record_file = os.path.join(self.releases_dir, f"{deployment_id}.json")
            
            if not os.path.exists(record_file):
                self.logger.error(f"배포 기록을 찾을 수 없습니다: {deployment_id}")
                return False
            
            # 기존 기록 로드
            with open(record_file, 'r', encoding='utf-8') as f:
                record = json.load(f)
            
            # 상태 업데이트
            record['status'] = status
            record['updated_at'] = datetime.now().isoformat()
            
            if rollback_digest:
                record['rollback_digest'] = rollback_digest
            
            # 파일 저장
            with open(record_file, 'w', encoding='utf-8') as f:
                json.dump(record, f, indent=2, ensure_ascii=False)
            
            self.logger.info(f"배포 상태 업데이트: {deployment_id} -> {status}")
            return True
            
        except Exception as e:
            self.logger.error(f"배포 상태 업데이트 실패: {str(e)}")
            return False
    
    def get_deployment_record(self, deployment_id: str) -> Optional[Dict]:
        """배포 기록 조회"""
        try:
            record_file = os.path.join(self.releases_dir, f"{deployment_id}.json")
            
            if not os.path.exists(record_file):
                self.logger.warning(f"배포 기록을 찾을 수 없습니다: {deployment_id}")
                return None
            
            with open(record_file, 'r', encoding='utf-8') as f:
                record = json.load(f)
            
            return record
            
        except Exception as e:
            self.logger.error(f"배포 기록 조회 실패: {str(e)}")
            return None
    
    def get_latest_successful_deployment(self, 
                                       service_kind: str, 
                                       environment: str) -> Optional[Dict]:
        """최신 성공 배포 기록 조회"""
        try:
            deployments = self.list_deployments(
                service_kind=service_kind,
                environment=environment,
                status="success"
            )
            
            if deployments:
                # 타임스탬프 기준으로 정렬하여 최신 것 반환
                latest = max(deployments, key=lambda x: x['timestamp'])
                self.logger.info(f"최신 성공 배포 조회: {latest['deployment_id']}")
                return latest
            else:
                self.logger.warning(f"성공한 배포 기록이 없습니다: {service_kind}-{environment}")
                return None
                
        except Exception as e:
            self.logger.error(f"최신 성공 배포 조회 실패: {str(e)}")
            return None
    
    def list_deployments(self,
                        service_kind: str = None,
                        environment: str = None,
                        status: str = None,
                        limit: int = None) -> List[Dict]:
        """배포 기록 목록 조회"""
        try:
            deployments = []
            
            # RELEASES 디렉토리의 모든 JSON 파일 조회
            for filename in os.listdir(self.releases_dir):
                if filename.endswith('.json'):
                    file_path = os.path.join(self.releases_dir, filename)
                    
                    try:
                        with open(file_path, 'r', encoding='utf-8') as f:
                            record = json.load(f)
                        
                        # 필터링
                        if service_kind and record.get('service_kind') != service_kind:
                            continue
                        if environment and record.get('environment') != environment:
                            continue
                        if status and record.get('status') != status:
                            continue
                        
                        deployments.append(record)
                        
                    except Exception as e:
                        self.logger.warning(f"배포 기록 파일 읽기 실패: {filename} - {str(e)}")
                        continue
            
            # 타임스탬프 기준으로 내림차순 정렬 (최신 순)
            deployments.sort(key=lambda x: x.get('timestamp', ''), reverse=True)
            
            # 제한 개수 적용
            if limit:
                deployments = deployments[:limit]
            
            self.logger.info(f"배포 기록 조회 완료: {len(deployments)}개")
            return deployments
            
        except Exception as e:
            self.logger.error(f"배포 기록 목록 조회 실패: {str(e)}")
            return []
    
    def get_rollback_target(self, 
                          service_kind: str, 
                          environment: str,
                          current_deployment_id: str = None) -> Optional[Dict]:
        """롤백 대상 배포 조회"""
        try:
            # 성공한 배포들을 최신 순으로 조회
            successful_deployments = self.list_deployments(
                service_kind=service_kind,
                environment=environment,
                status="success"
            )
            
            # 현재 배포를 제외하고 가장 최근 성공 배포 찾기
            for deployment in successful_deployments:
                if current_deployment_id and deployment['deployment_id'] == current_deployment_id:
                    continue
                
                self.logger.info(f"롤백 대상 찾음: {deployment['deployment_id']}")
                return deployment
            
            self.logger.warning(f"롤백 대상을 찾을 수 없습니다: {service_kind}-{environment}")
            return None
            
        except Exception as e:
            self.logger.error(f"롤백 대상 조회 실패: {str(e)}")
            return None
    
    def cleanup_old_records(self, keep_count: int = 50) -> int:
        """오래된 배포 기록 정리"""
        try:
            all_deployments = self.list_deployments()
            
            if len(all_deployments) <= keep_count:
                self.logger.info(f"정리할 배포 기록이 없습니다 (현재: {len(all_deployments)}개)")
                return 0
            
            # 삭제할 기록들 (오래된 순)
            to_delete = all_deployments[keep_count:]
            deleted_count = 0
            
            for record in to_delete:
                try:
                    record_file = os.path.join(self.releases_dir, f"{record['deployment_id']}.json")
                    if os.path.exists(record_file):
                        os.remove(record_file)
                        deleted_count += 1
                        self.logger.debug(f"배포 기록 삭제: {record['deployment_id']}")
                except Exception as e:
                    self.logger.warning(f"배포 기록 삭제 실패: {record['deployment_id']} - {str(e)}")
            
            self.logger.info(f"오래된 배포 기록 정리 완료: {deleted_count}개 삭제")
            return deleted_count
            
        except Exception as e:
            self.logger.error(f"배포 기록 정리 실패: {str(e)}")
            return 0
    
    def export_deployment_history(self, output_file: str = None) -> str:
        """배포 히스토리 내보내기"""
        try:
            if output_file is None:
                timestamp = get_current_timestamp()
                output_file = os.path.join(self.releases_dir, f"deployment_history_{timestamp}.json")
            
            all_deployments = self.list_deployments()
            
            export_data = {
                "export_timestamp": datetime.now().isoformat(),
                "total_deployments": len(all_deployments),
                "deployments": all_deployments
            }
            
            with open(output_file, 'w', encoding='utf-8') as f:
                json.dump(export_data, f, indent=2, ensure_ascii=False)
            
            self.logger.info(f"배포 히스토리 내보내기 완료: {output_file}")
            return output_file
            
        except Exception as e:
            self.logger.error(f"배포 히스토리 내보내기 실패: {str(e)}")
            raise
    
    def validate_digest(self, digest: str) -> bool:
        """다이제스트 형식 검증"""
        try:
            # SHA256 다이제스트 형식 검증
            if not digest.startswith('sha256:'):
                return False
            
            # 해시 부분 길이 검증 (64자)
            hash_part = digest[7:]  # 'sha256:' 제거
            if len(hash_part) != 64:
                return False
            
            # 16진수 문자만 포함하는지 검증
            try:
                int(hash_part, 16)
                return True
            except ValueError:
                return False
                
        except Exception:
            return False


def main():
    """메인 함수 - 테스트 및 CLI 용"""
    import argparse
    
    parser = argparse.ArgumentParser(description="릴리스 관리 도구")
    parser.add_argument('action', choices=['create', 'update', 'list', 'get', 'cleanup'], 
                       help='실행할 작업')
    parser.add_argument('--deployment-id', help='배포 ID')
    parser.add_argument('--source-repo', help='소스 저장소')
    parser.add_argument('--ref', help='Git 참조')
    parser.add_argument('--version', help='버전')
    parser.add_argument('--service-kind', help='서비스 종류')
    parser.add_argument('--environment', help='환경')
    parser.add_argument('--image-tag', help='이미지 태그')
    parser.add_argument('--image-digest', help='이미지 다이제스트')
    parser.add_argument('--status', help='상태')
    parser.add_argument('--limit', type=int, help='조회 제한 개수')
    
    args = parser.parse_args()
    
    manager = ReleaseManager()
    
    try:
        if args.action == 'create':
            if not all([args.source_repo, args.ref, args.version, args.service_kind, 
                       args.environment, args.image_tag, args.image_digest]):
                print("Error: 배포 기록 생성에 필요한 인수가 부족합니다.", file=sys.stderr)
                sys.exit(1)
            
            deployment_id = manager.create_deployment_record(
                args.source_repo, args.ref, args.version, args.service_kind,
                args.environment, args.image_tag, args.image_digest
            )
            print(f"Created deployment record: {deployment_id}")
            
        elif args.action == 'update':
            if not args.deployment_id or not args.status:
                print("Error: --deployment-id와 --status가 필요합니다.", file=sys.stderr)
                sys.exit(1)
            
            success = manager.update_deployment_status(args.deployment_id, args.status)
            print(f"Update {'success' if success else 'failed'}")
            
        elif args.action == 'list':
            deployments = manager.list_deployments(
                service_kind=args.service_kind,
                environment=args.environment,
                status=args.status,
                limit=args.limit
            )
            
            print(f"Found {len(deployments)} deployments:")
            for deployment in deployments:
                print(f"  {deployment['deployment_id']} - {deployment['status']} - {deployment['timestamp']}")
                
        elif args.action == 'get':
            if not args.deployment_id:
                print("Error: --deployment-id가 필요합니다.", file=sys.stderr)
                sys.exit(1)
            
            record = manager.get_deployment_record(args.deployment_id)
            if record:
                print(json.dumps(record, indent=2, ensure_ascii=False))
            else:
                print("Deployment record not found")
                sys.exit(1)
                
        elif args.action == 'cleanup':
            deleted_count = manager.cleanup_old_records()
            print(f"Cleaned up {deleted_count} old records")
            
    except Exception as e:
        print(f"Error: {str(e)}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()