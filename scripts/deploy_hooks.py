#!/usr/bin/env python3
"""
배포 훅 시스템 - 범용 전처리/후처리 스크립트 관리
프로젝트별 커스텀 훅을 로드하고 실행하는 시스템
"""

import os
import sys
import importlib.util
import inspect
from typing import Dict, List, Callable, Any, Optional
from abc import ABC, abstractmethod

# 현재 스크립트 디렉토리를 Python 경로에 추가
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from utils import Logger


class DeployHook(ABC):
    """배포 훅 베이스 클래스"""
    
    def __init__(self, environment: str, service_kind: str, logger: Logger):
        self.environment = environment
        self.service_kind = service_kind
        self.logger = logger
    
    @abstractmethod
    def execute(self) -> bool:
        """훅 실행 - 서브클래스에서 구현"""
        pass
    
    @property
    @abstractmethod
    def name(self) -> str:
        """훅 이름"""
        pass
    
    @property
    def description(self) -> str:
        """훅 설명 (선택사항)"""
        return f"{self.name} hook"


class DeployHookManager:
    """배포 훅 매니저"""
    
    def __init__(self, environment: str, service_kind: str):
        self.environment = environment
        self.service_kind = service_kind
        self.logger = Logger(f"DeployHookManager-{environment}-{service_kind}")
        
        # 프로젝트 루트 디렉토리
        self.project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        
        # 훅 저장소
        self.pre_deploy_hooks: List[DeployHook] = []
        self.post_deploy_hooks: List[DeployHook] = []
        
        # 기본 훅 로드
        self._load_default_hooks()
        
        # 프로젝트별 커스텀 훅 로드
        self._load_custom_hooks()
    
    def _load_default_hooks(self):
        """기본 훅 로드"""
        try:
            # 기본 pre-deploy 훅들
            from default_hooks import (
                EnvironmentVariableCheck,
                DockerEnvironmentCheck,
                DiskSpaceCheck,
                NetworkConnectivityCheck,
                ServiceDependencyCheck,
                DatabaseConnectivityCheck,
                PortAvailabilityCheck
            )
            
            default_pre_hooks = [
                EnvironmentVariableCheck,
                DockerEnvironmentCheck,
                DiskSpaceCheck,
                NetworkConnectivityCheck,
                ServiceDependencyCheck,
                DatabaseConnectivityCheck,
                PortAvailabilityCheck
            ]
            
            for hook_class in default_pre_hooks:
                hook = hook_class(self.environment, self.service_kind, self.logger)
                self.pre_deploy_hooks.append(hook)
            
            # 기본 post-deploy 훅들
            from default_hooks import (
                ContainerStatusCheck,
                ServiceResponseCheck,
                DatabaseHealthCheck,
                ExternalDependencyCheck,
                ApplicationLogCheck
            )
            
            default_post_hooks = [
                ContainerStatusCheck,
                ServiceResponseCheck,
                DatabaseHealthCheck,
                ExternalDependencyCheck,
                ApplicationLogCheck
            ]
            
            for hook_class in default_post_hooks:
                hook = hook_class(self.environment, self.service_kind, self.logger)
                self.post_deploy_hooks.append(hook)
            
            self.logger.info(f"기본 훅 로드 완료: pre={len(self.pre_deploy_hooks)}, post={len(self.post_deploy_hooks)}")
            
        except ImportError as e:
            self.logger.warning(f"기본 훅 로드 실패: {str(e)}")
    
    def _load_custom_hooks(self):
        """프로젝트별 커스텀 훅 로드"""
        try:
            # 프로젝트 루트의 deploy_hooks 디렉토리에서 커스텀 훅 로드
            custom_hooks_dir = os.path.join(self.project_root, 'deploy_hooks')
            
            if not os.path.exists(custom_hooks_dir):
                self.logger.info("커스텀 훅 디렉토리가 없습니다. 기본 훅만 사용합니다.")
                return
            
            # Python 파일들을 찾아서 로드
            for filename in os.listdir(custom_hooks_dir):
                if filename.endswith('.py') and not filename.startswith('__'):
                    self._load_hooks_from_file(os.path.join(custom_hooks_dir, filename))
            
            self.logger.info(f"커스텀 훅 로드 완료")
            
        except Exception as e:
            self.logger.error(f"커스텀 훅 로드 실패: {str(e)}")
    
    def _load_hooks_from_file(self, file_path: str):
        """파일에서 훅 클래스 로드"""
        try:
            # 모듈 동적 로드
            spec = importlib.util.spec_from_file_location("custom_hooks", file_path)
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            
            # DeployHook을 상속받은 클래스들 찾기
            for name, obj in inspect.getmembers(module):
                if (inspect.isclass(obj) and 
                    issubclass(obj, DeployHook) and 
                    obj != DeployHook):
                    
                    try:
                        hook = obj(self.environment, self.service_kind, self.logger)
                        
                        # 훅 타입 결정 (파일명 또는 클래스 속성으로)
                        if hasattr(hook, 'hook_type'):
                            hook_type = hook.hook_type
                        elif 'pre' in file_path.lower():
                            hook_type = 'pre'
                        elif 'post' in file_path.lower():
                            hook_type = 'post'
                        else:
                            # 기본값은 pre-deploy
                            hook_type = 'pre'
                        
                        if hook_type == 'pre':
                            self.pre_deploy_hooks.append(hook)
                        else:
                            self.post_deploy_hooks.append(hook)
                        
                        self.logger.info(f"커스텀 훅 로드: {hook.name} ({hook_type}-deploy)")
                        
                    except Exception as e:
                        self.logger.error(f"훅 인스턴스 생성 실패 ({name}): {str(e)}")
            
        except Exception as e:
            self.logger.error(f"훅 파일 로드 실패 ({file_path}): {str(e)}")
    
    def run_pre_deploy_hooks(self) -> bool:
        """Pre-deploy 훅 실행"""
        return self._run_hooks(self.pre_deploy_hooks, "Pre-deploy")
    
    def run_post_deploy_hooks(self) -> bool:
        """Post-deploy 훅 실행"""
        return self._run_hooks(self.post_deploy_hooks, "Post-deploy")
    
    def _run_hooks(self, hooks: List[DeployHook], hook_type: str) -> bool:
        """훅 실행"""
        try:
            self.logger.info(f"{hook_type} 훅 실행 시작 ({len(hooks)}개)")
            
            failed_hooks = []
            
            for hook in hooks:
                try:
                    self.logger.info(f"실행 중: {hook.name}")
                    
                    if hook.execute():
                        self.logger.info(f"훅 성공: {hook.name}")
                    else:
                        failed_hooks.append(hook.name)
                        self.logger.error(f"훅 실패: {hook.name}")
                        
                except Exception as e:
                    failed_hooks.append(hook.name)
                    self.logger.error(f"훅 실행 중 예외 발생 ({hook.name}): {str(e)}")
            
            if failed_hooks:
                self.logger.error(f"{hook_type} 훅 실패: {', '.join(failed_hooks)}")
                return False
            else:
                self.logger.info(f"모든 {hook_type} 훅 성공")
                return True
                
        except Exception as e:
            self.logger.error(f"{hook_type} 훅 실행 중 예외 발생: {str(e)}")
            return False
    
    def add_pre_deploy_hook(self, hook: DeployHook):
        """Pre-deploy 훅 추가"""
        self.pre_deploy_hooks.append(hook)
        self.logger.info(f"Pre-deploy 훅 추가: {hook.name}")
    
    def add_post_deploy_hook(self, hook: DeployHook):
        """Post-deploy 훅 추가"""
        self.post_deploy_hooks.append(hook)
        self.logger.info(f"Post-deploy 훅 추가: {hook.name}")
    
    def list_hooks(self) -> Dict[str, List[str]]:
        """등록된 훅 목록 반환"""
        return {
            'pre_deploy': [hook.name for hook in self.pre_deploy_hooks],
            'post_deploy': [hook.name for hook in self.post_deploy_hooks]
        }


# 편의 함수들
def create_hook_manager(environment: str, service_kind: str) -> DeployHookManager:
    """훅 매니저 생성"""
    return DeployHookManager(environment, service_kind)


def run_pre_deploy_hooks(environment: str, service_kind: str) -> bool:
    """Pre-deploy 훅 실행"""
    manager = create_hook_manager(environment, service_kind)
    return manager.run_pre_deploy_hooks()


def run_post_deploy_hooks(environment: str, service_kind: str) -> bool:
    """Post-deploy 훅 실행"""
    manager = create_hook_manager(environment, service_kind)
    return manager.run_post_deploy_hooks()


if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description="배포 훅 시스템")
    parser.add_argument('hook_type', choices=['pre', 'post'], help='훅 타입')
    parser.add_argument('environment', help='배포 환경')
    parser.add_argument('service_kind', choices=['fe', 'be'], help='서비스 종류')
    parser.add_argument('--list', action='store_true', help='등록된 훅 목록 표시')
    
    args = parser.parse_args()
    
    try:
        manager = create_hook_manager(args.environment, args.service_kind)
        
        if args.list:
            hooks = manager.list_hooks()
            print(f"Pre-deploy hooks: {', '.join(hooks['pre_deploy'])}")
            print(f"Post-deploy hooks: {', '.join(hooks['post_deploy'])}")
            sys.exit(0)
        
        if args.hook_type == 'pre':
            success = manager.run_pre_deploy_hooks()
        else:
            success = manager.run_post_deploy_hooks()
        
        if success:
            print(f"SUCCESS: {args.hook_type}-deploy hooks completed")
            sys.exit(0)
        else:
            print(f"ERROR: {args.hook_type}-deploy hooks failed", file=sys.stderr)
            sys.exit(1)
            
    except Exception as e:
        print(f"ERROR: {str(e)}", file=sys.stderr)
        sys.exit(1)