#!/usr/bin/env python3
"""
환경 변수 통합 관리 스크립트
- 환경별 .env 파일 관리
- 배포 상태 업데이트
- 환경 변수 조회/검증
- Git 커밋 자동화
"""

import os
import sys
import json
import argparse
import subprocess
from datetime import datetime
from pathlib import Path
from typing import Dict, Optional


class EnvManager:
    """환경 변수 통합 관리자"""
    
    def __init__(self, environment: str = "prod", project_root: str = None):
        self.environment = environment
        self.project_root = Path(project_root or os.getcwd())

        # 파일 경로
        self.common_env = self.project_root / ".env.common"
        self.env_file = self.project_root / f".env.{environment}"
        self.local_env = self.project_root / ".env.local"
        self.build_info = self.project_root / ".build-info"
        self.config_dir = self.project_root / "config" / environment
        
        # 필수 변수
        self.required_vars = [
            "DOCKER_REGISTRY",
            "DOCKER_REPO_HUB",
            "IMAGE_NAME",
            "ENVIRONMENT"
        ]
    
    def update_deploy_image(self, 
                           image: str,
                           ref: str,
                           version: str,
                           commit_sha: str,
                           deployed_by: str) -> None:
        """배포 이미지 정보 업데이트 (멱등)"""
        
        # 기존 내용 읽기
        env_data = self._read_env_file(self.env_file)
        
        # 업데이트
        env_data["ENVIRONMENT"] = self.environment
        env_data["DEPLOY_IMAGE"] = image
        env_data["LAST_DEPLOYED_AT"] = datetime.now().astimezone().isoformat()
        env_data["DEPLOYED_BY"] = deployed_by
        env_data["DEPLOYED_COMMIT"] = commit_sha
        env_data["DEPLOYED_REF"] = ref
        env_data["DEPLOYED_VERSION"] = version
        
        # 파일 쓰기 (멱등)
        header = f"# {self.environment.upper()} 배포 상태"
        self._write_env_file(self.env_file, env_data, header=header)
        
        # Git 커밋
        self._git_commit(f"deploy: {self.environment} to {image}")
        
        print(f"✓ {self.env_file} 업데이트 완료")
        print(f"  DEPLOY_IMAGE: {image}")
    
    def get(self, key: str, default: str = None) -> Optional[str]:
        """환경 변수 조회 (계층적)"""
        
        # 1. .env.local (최우선)
        if self.local_env.exists():
            local_data = self._read_env_file(self.local_env)
            if key in local_data:
                return local_data[key]
        
        # 2. .env.{environment}
        env_data = self._read_env_file(self.env_file)
        if key in env_data:
            return env_data[key]
        
        # 3. .env.common
        if self.common_env.exists():
            common_data = self._read_env_file(self.common_env)
            if key in common_data:
                return common_data[key]
        
        # 4. 기본값
        return default
    
    def set(self, key: str, value: str, commit: bool = True) -> None:
        """환경 변수 설정"""
        
        env_data = self._read_env_file(self.env_file)
        env_data[key] = value
        
        self._write_env_file(self.env_file, env_data)
        
        if commit:
            self._git_commit(f"env: set {key}={value} in {self.environment}")
        
        print(f"✓ {key}={value} 설정 완료")
    
    def load_all(self) -> Dict[str, str]:
        """모든 환경 변수 로드 (계층적)"""

        result = {}

        # 1. .env.common (기본)
        if self.common_env.exists():
            result.update(self._read_env_file(self.common_env))

        # 2. .env.{environment} (환경별 오버라이드)
        if self.env_file.exists():
            result.update(self._read_env_file(self.env_file))

        # 3. .env.local (로컬 오버라이드)
        if self.local_env.exists():
            result.update(self._read_env_file(self.local_env))

        # 4. .build-info (최우선 - 로컬 빌드 이미지)
        # IGNORE_BUILD_INFO 환경 변수가 설정되어 있으면 .build-info를 무시
        ignore_build_info = os.environ.get("IGNORE_BUILD_INFO", "").lower() in ("1", "true", "yes")
        if not ignore_build_info and self.build_info.exists():
            build_image = self._read_build_info()
            if build_image:
                result["DEPLOY_IMAGE"] = build_image

        return result
    
    def validate(self) -> bool:
        """필수 환경 변수 검증"""
        
        env_data = self.load_all()
        missing = []
        
        for var in self.required_vars:
            if var not in env_data or not env_data[var]:
                missing.append(var)
        
        if missing:
            print(f"❌ 누락된 필수 환경 변수: {', '.join(missing)}", file=sys.stderr)
            return False
        
        print(f"✓ 모든 필수 환경 변수 설정됨")
        return True
    
    def get_deploy_status(self) -> Dict:
        """배포 상태 조회"""
        
        env_data = self._read_env_file(self.env_file)
        
        return {
            "environment": self.environment,
            "deploy_image": env_data.get("DEPLOY_IMAGE", "N/A"),
            "last_deployed_at": env_data.get("LAST_DEPLOYED_AT", "N/A"),
            "deployed_by": env_data.get("DEPLOYED_BY", "N/A"),
            "deployed_commit": env_data.get("DEPLOYED_COMMIT", "N/A"),
            "deployed_ref": env_data.get("DEPLOYED_REF", "N/A"),
            "deployed_version": env_data.get("DEPLOYED_VERSION", "N/A"),
        }
    
    def export(self, include_warning: bool = True) -> str:
        """docker-compose용 환경 변수 export"""

        env_data = self.load_all()
        lines = []

        if include_warning:
            lines.append("# ⚠️  이 파일은 자동 생성됩니다. 직접 수정하지 마세요!")
            lines.append(f"# 환경: {self.environment}")
            lines.append(f"# 생성 시각: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")

            # .build-info가 있으면 표시 (IGNORE_BUILD_INFO가 설정되지 않은 경우만)
            load_order = f".env.common → .env.{self.environment} → .env.local"
            ignore_build_info = os.environ.get("IGNORE_BUILD_INFO", "").lower() in ("1", "true", "yes")
            if not ignore_build_info and self.build_info.exists():
                load_order += " → .build-info (DEPLOY_IMAGE 오버라이드)"

            lines.append(f"# 로드 순서: {load_order}")
            lines.append("")

        for key, value in sorted(env_data.items()):
            lines.append(f"{key}={value}")

        return "\n".join(lines)
    
    def export_with_sources(self, format: str = "json", show_override: bool = False) -> str:
        """오버라이드 정보를 포함한 환경 변수 export
        
        Args:
            format: 출력 형식 (json, table, colored)
            show_override: 오버라이드 정보 표시 여부
        """
        
        # 각 파일별로 로드
        common_data = {}
        env_data = {}
        local_data = {}
        
        if self.common_env.exists():
            common_data = self._read_env_file(self.common_env)
        
        if self.env_file.exists():
            env_data = self._read_env_file(self.env_file)
        
        if self.local_env.exists():
            local_data = self._read_env_file(self.local_env)
        
        # 모든 키 수집
        all_keys = set()
        all_keys.update(common_data.keys())
        all_keys.update(env_data.keys())
        all_keys.update(local_data.keys())
        
        result = []
        for key in sorted(all_keys):
            sources = []
            final_value = None
            
            # 각 소스에서 값 확인
            if key in common_data:
                sources.append(("common", common_data[key]))
                final_value = common_data[key]
            
            if key in env_data:
                sources.append((self.environment, env_data[key]))
                final_value = env_data[key]
            
            if key in local_data:
                sources.append(("local", local_data[key]))
                final_value = local_data[key]
            
            # 결과 생성
            result.append({
                "key": key,
                "value": final_value,
                "sources": sources,
                "overridden": len(sources) > 1
            })
        
        # 포맷에 따라 출력
        if format == "json":
            return json.dumps(result, ensure_ascii=False, indent=2)
        elif format == "table":
            return self._format_table(result, show_override)
        elif format == "colored":
            return self._format_colored(result, show_override)
        else:
            raise ValueError(f"Unknown format: {format}")
    
    def _format_table(self, data: list, show_override: bool) -> str:
        """테이블 형식으로 포맷"""
        lines = []
        
        for item in data:
            key = item["key"]
            value = item["value"]
            overridden = item["overridden"]
            
            if show_override and overridden:
                # 오버라이드된 경우 소스 정보 표시
                lines.append(f"{key}|{value}|OVERRIDE")
                for source_name, source_value in item["sources"]:
                    is_final = source_value == value
                    marker = "✓" if is_final else " "
                    lines.append(f"  {marker} {source_name}|{source_value}|")
            else:
                # 단일 소스
                source_name = item["sources"][0][0] if item["sources"] else "unknown"
                lines.append(f"{key}|{value}|{source_name}")
        
        return "\n".join(lines)
    
    def _format_colored(self, data: list, show_override: bool) -> str:
        """색상 포함 형식으로 포맷 (ANSI 색상 코드)"""
        # ANSI 색상 코드
        BLUE = "\033[34m"
        GREEN = "\033[32m"
        RED = "\033[31m"
        YELLOW = "\033[33m"
        GRAY = "\033[90m"
        NC = "\033[0m"  # No Color
        
        lines = []
        
        for item in data:
            key = item["key"]
            value = item["value"]
            overridden = item["overridden"]
            sources = item["sources"]
            
            if show_override and overridden:
                # 상세 오버라이드 정보 표시
                lines.append(f"{BLUE}{key:<30}{NC} = {GREEN}{value:<40}{NC} {RED}[Override]{NC}")
                for i, (source_name, source_value) in enumerate(sources):
                    is_last = i == len(sources) - 1
                    is_final = source_value == value
                    prefix = "└─" if is_last else "├─"
                    marker = f" {YELLOW}✓{NC}" if is_final else ""
                    lines.append(f"{GRAY}  {prefix} {source_name}: {source_value}{marker}{NC}")
            elif overridden:
                # 간단한 오버라이드 표시 (최종 소스만)
                final_source = sources[-1][0] if sources else "unknown"
                source_list = " → ".join([s[0] for s in sources])
                lines.append(f"{BLUE}{key:<30}{NC} = {GREEN}{value:<40}{NC} {YELLOW}[{source_list}]{NC}")
            else:
                # 단일 소스
                source_name = sources[0][0] if sources else "unknown"
                lines.append(f"{BLUE}{key:<30}{NC} = {GREEN}{value:<40}{NC} {GRAY}[{source_name}]{NC}")
        
        return "\n".join(lines)
    
    def init_env_file(self) -> None:
        """환경 파일 초기화"""
        
        if self.env_file.exists():
            print(f"⚠️  {self.env_file} 파일이 이미 존재합니다")
            return
        
        # 기본 내용
        env_data = {
            "ENVIRONMENT": self.environment,
        }
        
        header = f"# {self.environment.upper()} 배포 상태"
        self._write_env_file(self.env_file, env_data, header=header)
        
        print(f"✓ {self.env_file} 파일 생성 완료")
    
    # Private methods
    
    def _read_env_file(self, path: Path) -> Dict[str, str]:
        """env 파일 읽기"""
        
        if not path.exists():
            return {}
        
        result = {}
        with open(path, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('#'):
                    continue
                
                if '=' in line:
                    key, value = line.split('=', 1)
                    result[key.strip()] = value.strip()
        
        return result
    
    def _write_env_file(self, path: Path, data: Dict[str, str], header: str = None) -> None:
        """env 파일 쓰기 (멱등)"""

        lines = []

        if header:
            lines.append(header)
            lines.append(f"# 마지막 업데이트: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
            lines.append("")

        for key, value in sorted(data.items()):
            lines.append(f"{key}={value}")

        with open(path, 'w', encoding='utf-8') as f:
            f.write("\n".join(lines) + "\n")

    def _read_build_info(self) -> Optional[str]:
        """빌드 정보 파일 읽기 (.build-info에서 이미지 이름 추출)"""

        if not self.build_info.exists():
            return None

        try:
            with open(self.build_info, 'r', encoding='utf-8') as f:
                content = f.read().strip()
                if content:
                    return content
        except Exception as e:
            print(f"⚠️  .build-info 읽기 실패: {e}", file=sys.stderr)

        return None
    
    def _git_commit(self, message: str) -> None:
        """Git 커밋"""
        
        try:
            subprocess.run(
                ["git", "add", str(self.env_file)],
                check=True,
                cwd=self.project_root,
                capture_output=True
            )
            subprocess.run(
                ["git", "commit", "-m", message],
                check=True,
                cwd=self.project_root,
                capture_output=True
            )
            print(f"✓ Git 커밋: {message}")
        except subprocess.CalledProcessError:
            # 변경사항이 없거나 커밋 실패 시 무시
            pass


def main():
    parser = argparse.ArgumentParser(description="환경 변수 통합 관리")
    parser.add_argument(
        "command",
        choices=["update", "get", "set", "status", "validate", "export", "init", "export-sources"],
        help="실행할 명령"
    )
    parser.add_argument(
        "--environment", "-e",
        default="prod",
        help="환경 (기본: prod)"
    )
    parser.add_argument("--image", help="배포 이미지")
    parser.add_argument("--ref", help="Git 참조")
    parser.add_argument("--version", help="버전")
    parser.add_argument("--commit-sha", help="커밋 SHA")
    parser.add_argument("--deployed-by", help="배포자")
    parser.add_argument("--no-warning", action="store_true", help="export 시 경고 메시지 제외")
    parser.add_argument("--format", choices=["json", "table", "colored"], default="json", help="export-sources 출력 형식")
    parser.add_argument("--show-override", action="store_true", help="오버라이드 정보 표시")
    parser.add_argument("key", nargs="?", help="환경 변수 키")
    parser.add_argument("value", nargs="?", help="환경 변수 값")
    
    args = parser.parse_args()
    
    manager = EnvManager(environment=args.environment)
    
    try:
        if args.command == "update":
            if not all([args.image, args.ref, args.version, args.commit_sha, args.deployed_by]):
                print("❌ update 명령은 --image, --ref, --version, --commit-sha, --deployed-by 필요", file=sys.stderr)
                sys.exit(1)
            
            manager.update_deploy_image(
                image=args.image,
                ref=args.ref,
                version=args.version,
                commit_sha=args.commit_sha,
                deployed_by=args.deployed_by
            )
        
        elif args.command == "get":
            if not args.key:
                print("❌ get 명령은 key 인자 필요", file=sys.stderr)
                sys.exit(1)
            
            value = manager.get(args.key)
            if value:
                print(value)
            else:
                print(f"❌ {args.key} not found", file=sys.stderr)
                sys.exit(1)
        
        elif args.command == "set":
            if not args.key or not args.value:
                print("❌ set 명령은 key와 value 인자 필요", file=sys.stderr)
                sys.exit(1)
            
            manager.set(args.key, args.value)
        
        elif args.command == "status":
            status = manager.get_deploy_status()
            print(json.dumps(status, indent=2, ensure_ascii=False))
        
        elif args.command == "validate":
            if not manager.validate():
                sys.exit(1)
        
        elif args.command == "export":
            print(manager.export(include_warning=not args.no_warning))
        
        elif args.command == "export-sources":
            output = manager.export_with_sources(
                format=args.format,
                show_override=args.show_override
            )
            print(output)
        
        elif args.command == "init":
            manager.init_env_file()
    
    except Exception as e:
        print(f"❌ 에러 발생: {str(e)}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
