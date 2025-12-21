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
import shlex
from datetime import datetime
from pathlib import Path
from typing import Dict, Optional


class EnvManager:
    """환경 변수 통합 관리자"""
    
    def __init__(self, environment: str = "prod", project_root: str = None, use_consul: bool = False):
        self.environment = environment
        self.project_root = Path(project_root or os.getcwd())
        self.use_consul = use_consul

        # 파일 경로
        self.common_env = self.project_root / ".env.common"
        self.env_file = self.project_root / f".env.{environment}"
        self.runner_env = self.project_root / ".runner.env"  # 중앙서버에서 전파되는 환경 변수
        self.local_env = self.project_root / ".env.local"
        consul_env_file = os.environ.get("CONSUL_ENV_FILE", ".env.runtime")
        self.consul_env = self.project_root / consul_env_file  # Consul 환경 변수 파일
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
        
        # 2. .runner.env (중앙서버에서 전파)
        if self.runner_env.exists():
            runner_data = self._read_env_file(self.runner_env)
            if key in runner_data:
                return runner_data[key]
        
        # 3. .env.{environment}
        env_data = self._read_env_file(self.env_file)
        if key in env_data:
            return env_data[key]
        
        # 4. .env.common
        if self.common_env.exists():
            common_data = self._read_env_file(self.common_env)
            if key in common_data:
                return common_data[key]
        
        # 5. 기본값
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

        # 3. Consul 환경 변수 (USE_CONSUL=true일 때)
        # - read-only 정책 준수: 캐시 파일을 "쓰기"로 갱신하지 않고, 가능하면 라이브로 조회
        # - 라이브 조회 실패 시에만 캐시 파일로 fallback
        if self.use_consul:
            consul_live = self._load_consul_live()
            if consul_live:
                result.update(consul_live)
            elif self.consul_env.exists():
                result.update(self._read_env_file(self.consul_env))

        # 4. .runner.env (중앙서버에서 전파)
        if self.runner_env.exists():
            result.update(self._read_env_file(self.runner_env))

        # 5. .env.local (로컬 오버라이드)
        if self.local_env.exists():
            result.update(self._read_env_file(self.local_env))

        # 6. .build-info (최우선 - 로컬 빌드 이미지)
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
    
    def export(self, include_warning: bool = True, preserve_user_deploy_image: bool = False) -> str:
        """docker-compose용 환경 변수 export"""

        env_data = self.load_all()
        
        # 사용자 설정 DEPLOY_IMAGE 보호 로직
        if preserve_user_deploy_image:
            user_deploy_image = None
            deploy_source = None
            
            # .env.local 우선 확인
            if self.local_env.exists():
                local_data = self._read_env_file(self.local_env)
                if "DEPLOY_IMAGE" in local_data:
                    user_deploy_image = local_data["DEPLOY_IMAGE"]
                    deploy_source = ".env.local"
            
            # .env.local에 없으면 .runner.env 확인
            if not user_deploy_image and self.runner_env.exists():
                runner_data = self._read_env_file(self.runner_env)
                if "DEPLOY_IMAGE" in runner_data:
                    user_deploy_image = runner_data["DEPLOY_IMAGE"]
                    deploy_source = ".runner.env"
            
            # 사용자가 설정한 DEPLOY_IMAGE가 있으면 보호
            if user_deploy_image and env_data.get("DEPLOY_IMAGE") == user_deploy_image:
                print(f"📌 사용자 설정 DEPLOY_IMAGE 유지: {user_deploy_image} (소스: {deploy_source})", file=sys.stderr)
        
        lines = []

        if include_warning:
            lines.append("# ⚠️  이 파일은 자동 생성됩니다. 직접 수정하지 마세요!")
            lines.append(f"# 환경: {self.environment}")
            lines.append(f"# 생성 시각: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")

            # .build-info가 있으면 표시 (IGNORE_BUILD_INFO가 설정되지 않은 경우만)
            load_order = f".env.common → .env.{self.environment}"
            if self.use_consul:
                load_order += " → Consul"
            load_order += " → .runner.env → .env.local"
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
        consul_data = {}
        runner_data = {}
        local_data = {}
        build_data = {}
        
        if self.common_env.exists():
            common_data = self._read_env_file(self.common_env)
        
        if self.env_file.exists():
            env_data = self._read_env_file(self.env_file)
        
        if self.use_consul:
            consul_data = self._load_consul_live()
            if not consul_data and self.consul_env.exists():
                consul_data = self._read_env_file(self.consul_env)
        
        if self.runner_env.exists():
            runner_data = self._read_env_file(self.runner_env)
        
        if self.local_env.exists():
            local_data = self._read_env_file(self.local_env)

        # build-info (DEPLOY_IMAGE 최우선) - load_all과 동일한 규칙 유지
        ignore_build_info = os.environ.get("IGNORE_BUILD_INFO", "").lower() in ("1", "true", "yes")
        if not ignore_build_info and self.build_info.exists():
            build_image = self._read_build_info()
            if build_image:
                build_data["DEPLOY_IMAGE"] = build_image
        
        # 모든 키 수집
        all_keys = set()
        all_keys.update(common_data.keys())
        all_keys.update(env_data.keys())
        all_keys.update(consul_data.keys())
        all_keys.update(runner_data.keys())
        all_keys.update(local_data.keys())
        all_keys.update(build_data.keys())
        
        result = []
        for key in sorted(all_keys):
            sources = []
            final_value = None
            final_source = "unknown"
            
            # 각 소스에서 값 확인 (우선순위 순서)
            if key in common_data:
                sources.append(("common", common_data[key]))
                final_value = common_data[key]
                final_source = "common"
            
            if key in env_data:
                sources.append((self.environment, env_data[key]))
                final_value = env_data[key]
                final_source = self.environment
            
            if key in consul_data:
                sources.append(("Consul", consul_data[key]))
                final_value = consul_data[key]
                final_source = "Consul"
            
            if key in runner_data:
                sources.append(("runner", runner_data[key]))
                final_value = runner_data[key]
                final_source = "runner"
            
            if key in local_data:
                sources.append(("local", local_data[key]))
                final_value = local_data[key]
                final_source = "local"

            if key in build_data:
                sources.append(("build", build_data[key]))
                final_value = build_data[key]
                final_source = "build"

            # 상태 판정
            # - conflict: 서로 다른 값이 2개 이상 존재 (실제 override)
            # - dup: 여러 소스지만 값은 동일 (중복 정의)
            distinct_values = {v for _, v in sources if v is not None}
            is_conflict = len(distinct_values) > 1
            is_dup = (len(sources) > 1) and (len(distinct_values) == 1)
            
            # 결과 생성
            result.append({
                "key": key,
                "value": final_value,
                "sources": sources,
                "final_source": final_source,
                "is_conflict": is_conflict,
                "is_dup": is_dup,
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
            final_source = (item.get("final_source") or "unknown")
            is_conflict = bool(item.get("is_conflict"))
            is_dup = bool(item.get("is_dup"))
            sources = item.get("sources") or []
            
            # 태그(항상 최종 소스 1개 + 필요 시 상태)
            tags = [final_source]
            if is_conflict:
                tags.append("override")
            elif show_override and is_dup:
                tags.append("dup")

            if show_override and len(sources) > 1:
                # 상세 소스 정보 표시
                lines.append(f"{key}|{value}|{' '.join(f'[{t}]' for t in tags)}")
                for i, (source_name, source_value) in enumerate(sources):
                    marker = "✓" if i == len(sources) - 1 else " "
                    lines.append(f"  {marker} {source_name}|{source_value}|")
            else:
                lines.append(f"{key}|{value}|{' '.join(f'[{t}]' for t in tags)}")
        
        return "\n".join(lines)
    
    def _format_colored(self, data: list, show_override: bool) -> str:
        """색상 포함 형식으로 포맷 (ANSI 색상 코드)"""
        # ANSI 색상 코드
        BLUE = "\033[34m"
        CYAN = "\033[36m"
        GREEN = "\033[32m"
        RED = "\033[31m"
        YELLOW = "\033[33m"
        GRAY = "\033[90m"
        NC = "\033[0m"  # No Color
        
        lines = []

        def _tag(src: str) -> str:
            # 최종 소스 태그는 소문자/환경명 그대로 노출
            if src == "Consul":
                return "consul"
            return (src or "unknown").lower()
        
        for item in data:
            key = item["key"]
            value = item["value"]
            sources = item.get("sources") or []
            final_source = item.get("final_source") or (sources[-1][0] if sources else "unknown")
            is_conflict = bool(item.get("is_conflict"))
            is_dup = bool(item.get("is_dup"))

            tags = [f"[{_tag(final_source)}]"]
            if is_conflict:
                tags.append(f"{RED}[override]{NC}")
            elif show_override and is_dup:
                tags.append(f"{GRAY}[dup]{NC}")
            tag_str = " ".join(tags)
            
            # 상단 라인: 항상 최종 소스 태그를 표시
            if _tag(final_source) == "consul":
                tag_str = f"{CYAN}{tag_str}{NC}"
            lines.append(f"{BLUE}{key:<30}{NC} = {GREEN}{value:<40}{NC} {tag_str}")

            # 상세 트리: show_override일 때, 2개 이상 소스가 있으면 출력
            if show_override and len(sources) > 1:
                for i, (source_name, source_value) in enumerate(sources):
                    is_last = i == len(sources) - 1
                    prefix = "└─" if is_last else "├─"
                    marker = f" {YELLOW}✓{NC}" if is_last else ""
                    lines.append(f"{GRAY}  {prefix} {source_name}: {source_value}{marker}{NC}")
        
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
        
        result: Dict[str, str] = {}
        with open(path, 'r', encoding='utf-8') as f:
            for raw in f:
                line = raw.strip()
                if not line or line.startswith('#'):
                    continue

                # Allow common dotenv variants used in shell exports
                # - export KEY=VALUE
                # - declare -x KEY=VALUE (bash)
                if line.startswith("export "):
                    line = line[len("export "):].strip()
                elif line.startswith("declare -x "):
                    line = line[len("declare -x "):].strip()

                if '=' not in line:
                    continue

                key, value = line.split('=', 1)
                key = key.strip()
                value = value.strip()

                # strip surrounding quotes
                if len(value) >= 2 and ((value[0] == value[-1] == '"') or (value[0] == value[-1] == "'")):
                    value = value[1:-1]

                if key:
                    result[key] = value
        
        return result

    def _parse_env_text(self, text: str) -> Dict[str, str]:
        """env 텍스트(KEY=VALUE) 파싱 (파일 쓰기 없이 사용)"""

        result: Dict[str, str] = {}
        for raw in (text or "").splitlines():
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("export "):
                line = line[len("export "):].strip()
            if "=" not in line:
                continue

            key, value = line.split("=", 1)
            key = key.strip()
            value = value.strip()

            # strip surrounding quotes
            if len(value) >= 2 and ((value[0] == value[-1] == '"') or (value[0] == value[-1] == "'")):
                value = value[1:-1]

            if key:
                result[key] = value

        return result

    def _load_consul_live(self) -> Dict[str, str]:
        """Consul 값을 라이브로 조회해 env dict로 반환 (read-only). 실패 시 {}."""

        consul_app = os.environ.get("CONSUL_APP", "").strip()
        consul_prefix = os.environ.get("CONSUL_PREFIX", "").strip()

        if not consul_app and not consul_prefix:
            return {}

        # consul client 커맨드 결정: CONSUL_CLIENT(예: "python3 scripts/consul_web.py") 우선, 없으면 같은 디렉토리의 consul_web.py
        consul_client_raw = os.environ.get("CONSUL_CLIENT", "").strip()
        if consul_client_raw:
            consul_cmd = shlex.split(consul_client_raw)
        else:
            consul_cmd = [sys.executable, str(Path(__file__).resolve().parent / "consul_web.py")]

        # 라이브 export (stdout) - 기본 decrypt 활성화(= --no-decrypt 미사용)
        # NOTE: consul_web.py는 전역 옵션을 먼저 모으는 커스텀 파서가 있어서
        # "export" 서브커맨드를 첫 토큰으로 주는 게 안전함(예: "--quiet export ..." 형태는 깨질 수 있음)
        global_args: list[str] = []
        if consul_app:
            global_args += ["--app", consul_app, "--env", self.environment]
        else:
            global_args += ["--prefix", consul_prefix]

        export_args = ["export", "--format", "env", "--output", "-", "--quiet"]

        try:
            proc = subprocess.run(
                consul_cmd + global_args + export_args,
                capture_output=True,
                text=True,
                check=True,
            )
        except Exception:
            return {}

        return self._parse_env_text(proc.stdout)
    
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
    parser.add_argument("--use-consul", action="store_true", help="Consul 환경 변수 사용")
    parser.add_argument("--preserve-user-deploy-image", action="store_true", help="사용자가 설정한 DEPLOY_IMAGE 보호 (.env.local/.runner.env)")
    parser.add_argument("key", nargs="?", help="환경 변수 키")
    parser.add_argument("value", nargs="?", help="환경 변수 값")
    
    args = parser.parse_args()
    
    manager = EnvManager(environment=args.environment, use_consul=args.use_consul)
    
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
            print(manager.export(
                include_warning=not args.no_warning,
                preserve_user_deploy_image=args.preserve_user_deploy_image
            ))
        
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
