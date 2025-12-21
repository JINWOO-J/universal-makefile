#!/usr/bin/env python3
"""
Consul API Client - FastAPI 서버를 통한 Configuration 관리

- FastAPI 서버를 통해 Consul KV를 조회/설정/삭제
- APP/ENV 또는 PREFIX 기반으로 키 prefix 관리
- .env / shell / json export (기본: 따옴표 없이, --use-quotes 로 "값" 형태)
- 설정 우선순위: CLI > .env > OS env > default
- -v/--verbose 일 때 "어디서 값을 읽었는지" 함께 출력
"""

import argparse
import sys
import os
import logging
import requests
import json
import time
import socket
from typing import Optional, Dict, Tuple


# 로깅 기본 설정 - stderr로 출력하여 stdout과 분리
logging.basicConfig(
    level=logging.INFO,
    format='%(levelname)s: %(message)s',
    stream=sys.stderr  # 로그는 stderr로, 데이터는 stdout으로 분리
)
logger = logging.getLogger(__name__)

# urllib3 디버그 로깅 (verbose 모드에서만)
urllib3_logger = logging.getLogger('urllib3.connectionpool')
urllib3_logger.setLevel(logging.WARNING)  # 기본은 WARNING, verbose에서 DEBUG로 변경

# DNS 조회 시간 추적을 위한 monkey patch
_original_getaddrinfo = socket.getaddrinfo
def _timed_getaddrinfo(host, port, family=0, type=0, proto=0, flags=0):
    t_start = time.perf_counter()
    result = _original_getaddrinfo(host, port, family, type, proto, flags)
    t_end = time.perf_counter()
    if (t_end - t_start) > 0.001:  # 1ms 이상 걸린 경우만 로그
        logger.debug(f"[TIMING] DNS lookup for {host}:{port}: {(t_end - t_start)*1000:.2f}ms")
    return result

# Monkey patch 적용 (verbose 모드에서만 적용될 예정)
_dns_patched = False


# ----------------------------
# 출력 유틸리티
# ----------------------------
def write_output(content: str, output_file: Optional[str] = None, overwrite: bool = True) -> None:
    """
    출력을 파일 또는 stdout으로 안전하게 쓰기
    - output_file이 None이면 stdout으로 출력 (순수 데이터만)
    - 파일 출력 시 원자적 쓰기 (임시파일 → rename)
    """
    if output_file is None or output_file == '-':
        # stdout으로 출력 (순수 데이터만)
        print(content)
        return
    
    # 파일 존재 여부 확인
    if os.path.exists(output_file) and not overwrite:
        logger.error(f"File already exists: {output_file} (use --overwrite to replace)")
        sys.exit(1)
    
    # 원자적 파일 쓰기
    import tempfile
    temp_file = None
    try:
        # 같은 디렉토리에 임시 파일 생성
        dir_name = os.path.dirname(output_file) or '.'
        with tempfile.NamedTemporaryFile(
            mode='w', 
            encoding='utf-8', 
            dir=dir_name, 
            delete=False,
            prefix='.tmp_' + os.path.basename(output_file) + '_'
        ) as f:
            f.write(content)
            if not content.endswith('\n'):
                f.write('\n')
            temp_file = f.name
        
        # 파일 권한 설정 (0600 - 소유자만 읽기/쓰기)
        os.chmod(temp_file, 0o600)
        
        # 원자적 교체
        os.rename(temp_file, output_file)
        logger.info(f"✓ Wrote {output_file}")
        
    except Exception as e:
        # 실패 시 임시 파일 정리
        if temp_file and os.path.exists(temp_file):
            try:
                os.unlink(temp_file)
            except:
                pass
        logger.error(f"Failed to write {output_file}: {e}")
        sys.exit(1)


# ----------------------------
# .env loader (간단 구현)
# ----------------------------
def load_dotenv_file(path: str) -> Dict[str, str]:
    """
    .env 파일을 읽어서 dict로 반환.
    - KEY=VALUE 형식만 지원
    - 따옴표("..."/'...')는 양끝만 제거
    - export KEY=VALUE 도 지원
    - 주석(#) 라인은 무시
    """
    out: Dict[str, str] = {}
    if not path:
        return out
    if not os.path.exists(path):
        return out

    try:
        with open(path, "r", encoding="utf-8") as f:
            for raw in f:
                line = raw.strip()
                if not line or line.startswith("#"):
                    continue
                if line.startswith("export "):
                    line = line[len("export "):].strip()
                if "=" not in line:
                    continue
                k, v = line.split("=", 1)
                k = k.strip()
                v = v.strip()

                # remove surrounding quotes
                if (len(v) >= 2) and ((v[0] == v[-1] == '"') or (v[0] == v[-1] == "'")):
                    v = v[1:-1]

                out[k] = v
    except Exception as e:
        logger.warning(f"Warning: Could not load .env file '{path}': {e}")
    return out


def parse_bool(s: str) -> bool:
    return str(s).strip().lower() in ("1", "true", "yes", "y", "on")


def resolve_value(
    key_name: str,
    cli_val,
    dotenv: Dict[str, str],
    env_key: str,
    default=None,
    cast=None,
) -> Tuple[str, str]:
    """
    우선순위: CLI > .env > OS env > default
    반환: (value, source)
    """
    if cli_val is not None:
        return (cli_val if cast is None else cast(cli_val), f"CLI(--{key_name})")

    if env_key in dotenv:
        v = dotenv[env_key]
        return ((v if cast is None else cast(v)), f".env({env_key})")

    if os.environ.get(env_key) is not None:
        v = os.environ.get(env_key)
        return ((v if cast is None else cast(v)), f"OS_ENV({env_key})")

    return (default, "DEFAULT")


# ----------------------------
# Client
# ----------------------------
class ConsulAPIClient:
    """FastAPI 서버를 통한 Consul 클라이언트"""

    def __init__(
        self,
        base_url: str,
        api_key: str,
        prefix: str = '',
        timeout: int = 5,
        quote_values: bool = False,  # env 형식에서 "값" 으로 감쌀지 여부 (기본: False)
    ):
        t_init_start = time.perf_counter()
        
        self.base_url = base_url.rstrip('/')
        self.api_key = api_key
        self.prefix = prefix.strip('/')
        self.timeout = timeout
        self.quote_values = quote_values

        t_before_session = time.perf_counter()
        self.session = requests.Session()
        self.session.headers.update({
            'X-API-Key': api_key,
            'Connection': 'close'  # Force connection close to avoid delayed ACK
        })
        
        # Connection pooling 최적화
        adapter = requests.adapters.HTTPAdapter(
            pool_connections=1,
            pool_maxsize=1,
            max_retries=0,
            pool_block=False
        )
        self.session.mount('http://', adapter)
        self.session.mount('https://', adapter)
        
        t_after_session = time.perf_counter()
        logger.debug(f"[TIMING] Session creation: {(t_after_session - t_before_session)*1000:.2f}ms")
        logger.debug(f"[TIMING] ConsulAPIClient.__init__ total: {(t_after_session - t_init_start)*1000:.2f}ms")

    def validate_app_env_existence(self, app: str, env_name: str, strict_mode: bool = False) -> Tuple[bool, str]:
        """
        지정된 app과 env가 실제로 Consul에 존재하는지 검증
        
        Args:
            app: 애플리케이션 이름
            env_name: 환경 이름  
            strict_mode: True면 존재하지 않을 때 에러, False면 경고
            
        Returns:
            (exists, message) 튜플
        """
        try:
            t_start = time.perf_counter()
            
            # 1. app 레벨 확인 - app/* 패턴으로 키가 있는지 확인
            app_exists = False
            app_envs = set()
            
            # 전체 키 목록을 가져와서 app 패턴 확인
            resp = self.session.get(
                f"{self.base_url}/api/v1/config",
                params={'prefix': '', 'include_metadata': 'false'},
                timeout=self.timeout,
            )
            
            if resp.status_code == 200:
                data = resp.json()
                all_keys = list(data.get('items', {}).keys())
                
                # app으로 시작하는 키들 찾기
                app_prefix = f"{app}/"
                for key in all_keys:
                    if key.startswith(app_prefix):
                        app_exists = True
                        # env 추출 (app/env/... 패턴에서 env 부분)
                        remaining = key[len(app_prefix):]
                        if '/' in remaining:
                            env_part = remaining.split('/')[0]
                            app_envs.add(env_part)
                        else:
                            # app/key 형태 (env 없이 직접 키)
                            app_envs.add('(direct)')
            
            t_request = time.perf_counter()
            logger.debug(f"[TIMING] validate_app_env_existence: {(t_request - t_start)*1000:.2f}ms")
            
            # 2. 검증 결과 분석
            if not app_exists:
                msg = f"App '{app}' not found in Consul. No keys found with prefix '{app}/'"
                if strict_mode:
                    return False, f"ERROR: {msg}"
                else:
                    return False, f"WARNING: {msg}"
            
            # 3. env 검증 (env_name이 지정된 경우)
            if env_name and env_name != '':
                if env_name not in app_envs:
                    available_envs = sorted(list(app_envs))
                    msg = f"Environment '{env_name}' not found for app '{app}'. Available environments: {available_envs}"
                    if strict_mode:
                        return False, f"ERROR: {msg}"
                    else:
                        return False, f"WARNING: {msg}"
            
            # 4. 성공 케이스
            if env_name and env_name != '':
                return True, f"✓ App '{app}' and environment '{env_name}' exist in Consul"
            else:
                available_envs = sorted(list(app_envs))
                return True, f"✓ App '{app}' exists in Consul with environments: {available_envs}"
                
        except Exception as e:
            msg = f"Failed to validate app/env existence: {e}"
            logger.debug(f"Validation error: {e}")
            if strict_mode:
                return False, f"ERROR: {msg}"
            else:
                return False, f"WARNING: {msg} (continuing anyway)"

    def get_config(self, key: str, decrypt: bool = True) -> Optional[str]:
        """단일 설정 조회"""
        t_start = time.perf_counter()
        resp = self.session.get(
            f"{self.base_url}/api/v1/config/{key}",
            params={'prefix': self.prefix, 'decrypt': decrypt},
            timeout=self.timeout,
        )
        t_request = time.perf_counter()
        logger.debug(f"[TIMING] HTTP GET /api/v1/config/{key}: {(t_request - t_start)*1000:.2f}ms")
        
        if resp.status_code == 404:
            return None
        resp.raise_for_status()
        data = resp.json()
        return data['value']

    def get_all_configs(self, decrypt: bool = False, mask_secrets: bool = True) -> Dict[str, str]:
        """prefix 아래 모든 설정 조회 (일괄)"""
        t_start = time.perf_counter()
        
        if decrypt:
            # 복호화된 값을 빠르게 가져오기
            url = f"{self.base_url}/api/v1/export/json"
            params = {'prefix': self.prefix, 'decrypt': 'true'}
            
            t_before_request = time.perf_counter()
            logger.debug(f"[TIMING] Preparing request to: {url}")
            logger.debug(f"[TIMING]   - Session adapter pool: {self.session.adapters}")
            
            # 저수준 타이밍을 위한 훅 사용
            timings = {}
            def response_hook(r, *args, **kwargs):
                timings['response_received'] = time.perf_counter()
            
            resp = self.session.get(
                url,
                params=params,
                timeout=self.timeout,
                hooks={'response': response_hook}
            )
            
            t_after_request = time.perf_counter()
            
            # 세부 타이밍 출력
            if 'response_received' in timings:
                logger.debug(f"[TIMING] HTTP GET /api/v1/export/json:")
                logger.debug(f"[TIMING]   - Total request time: {(t_after_request - t_before_request)*1000:.2f}ms")
                logger.debug(f"[TIMING]   - Until response received: {(timings['response_received'] - t_before_request)*1000:.2f}ms")
                logger.debug(f"[TIMING]   - Hook processing: {(t_after_request - timings['response_received'])*1000:.2f}ms")
            else:
                logger.debug(f"[TIMING] HTTP GET /api/v1/export/json (decrypt): {(t_after_request - t_before_request)*1000:.2f}ms")
            
            logger.debug(f"[TIMING]   - Response status: {resp.status_code}, size: {len(resp.content)} bytes")
            
            t_before_parse = time.perf_counter()
            resp.raise_for_status()
            data = resp.json()
            
            t_after_parse = time.perf_counter()
            logger.debug(f"[TIMING]   - JSON parsing: {(t_after_parse - t_before_parse)*1000:.2f}ms")
            
            return data.get('configurations', {})
        else:
            # 메타데이터 포함 조회 (마스킹 지원)
            resp = self.session.get(
                f"{self.base_url}/api/v1/config",
                params={
                    'prefix': self.prefix,
                    'include_metadata': 'true',
                    'decrypt': 'false',
                    'mask_secrets': str(mask_secrets).lower(),
                },
                timeout=self.timeout,
            )
            t_request = time.perf_counter()
            logger.debug(f"[TIMING] HTTP GET /api/v1/config (metadata): {(t_request - t_start)*1000:.2f}ms")
            
            resp.raise_for_status()
            data = resp.json()
            return {k: v['value'] for k, v in data.get('items', {}).items()}

    def export_to_env(
        self,
        decrypt: bool = True,
        mask_secrets: bool = False,
        strip_prefix: str = "",
        format_type: str = "env",
        uppercase: bool = True,
        sort_keys: bool = True,
    ) -> str:
        """ .env / shell / json 형식으로 export """
        t_start = time.perf_counter()
        items = self.get_all_configs(decrypt=decrypt, mask_secrets=mask_secrets)
        t_fetch = time.perf_counter()
        logger.debug(f"[TIMING] export_to_env - get_all_configs: {(t_fetch - t_start)*1000:.2f}ms")

        def to_env_name(key: str) -> str:
            if strip_prefix:
                prefix_with_slash = strip_prefix.rstrip('/') + '/'
                if key.startswith(prefix_with_slash):
                    key = key[len(prefix_with_slash):]
            key = key.replace('/', '_')
            return key.upper() if uppercase else key

        def escape_value(value: str) -> str:
            return value.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n')

        keys = sorted(items.keys()) if sort_keys else list(items.keys())

        if format_type == "json":
            env_dict = {to_env_name(k): items[k] for k in keys}
            return json.dumps(env_dict, ensure_ascii=False)

        lines = []
        for key in keys:
            name = to_env_name(key)
            raw = items[key]

            if format_type == "shell":
                # shell: 항상 안전하게 따옴표 사용
                val = escape_value(raw)
                lines.append(f'export {name}="{val}"')
            else:  # env
                if self.quote_values:
                    val = escape_value(raw)
                    lines.append(f'{name}="{val}"')
                else:
                    lines.append(f'{name}={raw}')
        
        t_format = time.perf_counter()
        logger.debug(f"[TIMING] export_to_env - formatting: {(t_format - t_fetch)*1000:.2f}ms")
        logger.debug(f"[TIMING] export_to_env - total: {(t_format - t_start)*1000:.2f}ms")

        return '\n'.join(lines)

    def set_config(self, key: str, value: str, is_secret: bool = False) -> bool:
        """설정 저장"""
        try:
            t_start = time.perf_counter()
            resp = self.session.post(
                f"{self.base_url}/api/v1/config",
                params={'prefix': self.prefix},
                json={'key': key, 'value': value, 'is_secret': is_secret},
                timeout=self.timeout,
            )
            t_request = time.perf_counter()
            logger.debug(f"[TIMING] HTTP POST /api/v1/config: {(t_request - t_start)*1000:.2f}ms")
            
            resp.raise_for_status()
            return True
        except Exception as e:
            logger.error(f"Failed to set config: {e}")
            return False

    def delete_config(self, key: str) -> bool:
        """설정 삭제"""
        try:
            t_start = time.perf_counter()
            resp = self.session.delete(
                f"{self.base_url}/api/v1/config/{key}",
                params={'prefix': self.prefix},
                timeout=self.timeout,
            )
            t_request = time.perf_counter()
            logger.debug(f"[TIMING] HTTP DELETE /api/v1/config/{key}: {(t_request - t_start)*1000:.2f}ms")
            
            resp.raise_for_status()
            return True
        except Exception as e:
            logger.error(f"Failed to delete config: {e}")
            return False


# ----------------------------
# CLI
# ----------------------------
def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description='Consul API Client (with app/env & .env export)',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # .env 먼저 사용하고, CLI로 덮어쓰기
  consul_api_client.py --env-file .env -v list

  # APP/ENV 방식(추천)
  consul_api_client.py --app web_service --env prod list

  # prefix 직접 지정
  consul_api_client.py --prefix web_service/prod export --output .env

  # 따옴표 포함하여 export
  consul_api_client.py --use-quotes export
        """
    )

    # ==== 전역 옵션 (기본값은 None으로 두고, main에서 우선순위 적용) ====
    parser.add_argument('--env-file', default=None,
                        help='dotenv file path (default: ./.env if exists)')
    parser.add_argument('--api-url', default=None,
                        help='FastAPI server URL (env: CONSUL_API_URL)')
    parser.add_argument('--api-key', default=None,
                        help='API key (env: CONSUL_API_KEY)')
    parser.add_argument('--prefix', default=None,
                        help='Key prefix (env: CONSUL_PREFIX)')
    parser.add_argument('--app', default=None,
                        help='Application name (env: CONSUL_APP)')
    parser.add_argument('--env', dest='env_name', default=None,
                        help='Environment name (env: CONSUL_ENV)')
    parser.add_argument('--all-env', action='store_true',
                        help='Include all environments (use with --app, dangerous!)')
    parser.add_argument('--quiet', action='store_true',
                        help='Minimize stderr output (warnings still shown)')
    parser.add_argument('--log-level', default=None,
                        choices=['DEBUG', 'INFO', 'WARNING', 'ERROR'],
                        help='Logging level (env: CONSUL_LOG_LEVEL)')
    parser.add_argument('--timeout', type=int, default=None,
                        help='HTTP request timeout in seconds (env: CONSUL_TIMEOUT)')
    parser.add_argument('--use-quotes', action='store_true',
                        help='Wrap values with double quotes in env format (env: CONSUL_USE_QUOTES=true)')
    parser.add_argument('--strict-mode', action='store_true',
                        help='Exit with error if app/env not found (env: CONSUL_STRICT_MODE=true)')
    parser.add_argument('-v', '--verbose', action='store_true',
                        help='Print resolved configuration and sources')

    # ==== 서브커맨드 ====
    subparsers = parser.add_subparsers(dest='command', help='Commands')

    # get
    sp_get = subparsers.add_parser('get', help='Get a configuration value')
    sp_get.add_argument('key', help='Configuration key')
    sp_get.add_argument('--no-decrypt', action='store_true',
                        help='Do not decrypt (return encrypted value)')
    sp_get.add_argument('--with-key', action='store_true',
                        help='Print "key: value" instead of just value')

    # list
    sp_list = subparsers.add_parser('list', help='List all configurations')
    sp_list.add_argument('--decrypt', action='store_true',
                         help='Decrypt secret values')
    sp_list.add_argument('--match', help='Show only keys containing this substring')

    # export
    sp_export = subparsers.add_parser('export', help='Export configurations to .env / shell / json')
    sp_export.add_argument('--no-decrypt', action='store_true',
                           help='Do not decrypt (return encrypted values)')
    sp_export.add_argument('--mask-secrets', action='store_true',
                           help='Mask secret values with ********')
    sp_export.add_argument('--strip-prefix', default='',
                           help='Strip prefix from environment variable names')
    sp_export.add_argument('--format', choices=['env', 'shell', 'json'], default='env',
                           help='Output format (default: env)')
    sp_export.add_argument('--no-uppercase', action='store_true',
                           help='Do not uppercase environment variable names')
    sp_export.add_argument('--no-sort', action='store_true',
                           help='Do not sort keys')
    sp_export.add_argument('--output', default=None,
                           help='Output file (default: stdout). Use "-" for explicit stdout')
    sp_export.add_argument('--overwrite', action='store_true',
                           help='Overwrite existing output file')
    sp_export.add_argument('--quiet', action='store_true',
                           help='Minimize stderr output (warnings still shown)')

    # set
    sp_set = subparsers.add_parser('set', help='Set a configuration value')
    sp_set.add_argument('key')
    sp_set.add_argument('value')
    sp_set.add_argument('--secret', action='store_true',
                        help='Mark as secret (will be encrypted on server)')

    # delete
    sp_del = subparsers.add_parser('delete', help='Delete a configuration')
    sp_del.add_argument('key')
    sp_del.add_argument('-y', '--yes', action='store_true',
                        help='Do not ask for confirmation')

    # count
    sp_count = subparsers.add_parser('count', help='Count configurations for the prefix')
    sp_count.add_argument('--decrypt', action='store_true',
                          help='Decrypt secret values (optional)')

    return parser


def extract_global_args(argv):
    """
    argv 어디에 있어도 전역 옵션을 뽑아서 앞으로 모으는 함수.
    (기존 스타일 유지)
    """
    spec = {
        '--env-file': 1,
        '--api-url': 1,
        '--api-key': 1,
        '--prefix': 1,
        '--app': 1,
        '--env': 1,
        '--log-level': 1,
        '--timeout': 1,
        '--use-quotes': 0,
        '--strict-mode': 0,
        '-v': 0,
        '--verbose': 0,
    }

    globals_part = []
    rest = []

    i = 0
    while i < len(argv):
        tok = argv[i]
        if tok in spec:
            globals_part.append(tok)
            nargs = spec[tok]
            for _ in range(nargs):
                i += 1
                if i < len(argv):
                    globals_part.append(argv[i])
                else:
                    break
        else:
            rest.append(tok)
        i += 1

    return globals_part, rest


def main():
    start_time = time.perf_counter()
    logger.debug(f"[TIMING] Script started at {start_time:.6f}")
    
    argv = sys.argv[1:]
    t1 = time.perf_counter()
    logger.debug(f"[TIMING] argv parsing: {(t1 - start_time)*1000:.2f}ms")
    
    global_part, rest_part = extract_global_args(argv)
    t2 = time.perf_counter()
    logger.debug(f"[TIMING] extract_global_args: {(t2 - t1)*1000:.2f}ms")

    # 1) env-file 경로 결정 (CLI > default ./.env)
    env_file = None
    if '--env-file' in global_part:
        idx = global_part.index('--env-file')
        if idx + 1 < len(global_part):
            env_file = global_part[idx + 1]
    else:
        # 기본은 현재 디렉토리에 .env가 있으면 사용
        if os.path.exists(".env"):
            env_file = ".env"
    
    t3 = time.perf_counter()
    logger.debug(f"[TIMING] env-file path resolution: {(t3 - t2)*1000:.2f}ms")

    dotenv = load_dotenv_file(env_file) if env_file else {}
    t4 = time.perf_counter()
    logger.debug(f"[TIMING] load_dotenv_file: {(t4 - t3)*1000:.2f}ms")

    # 2) 기본 명령어 처리 - argparse 실행 전에 처리
    if not rest_part or rest_part[0] not in ['get', 'list', 'export', 'set', 'delete', 'count']:
        # 기본 명령어 'export' 추가
        rest_part = ['export'] + rest_part
        logger.debug("Using default command: export")
    
    t5 = time.perf_counter()
    logger.debug(f"[TIMING] command validation: {(t5 - t4)*1000:.2f}ms")

    # 3) 파서 실행 (CLI 값 확보)
    parser = build_parser()
    t6 = time.perf_counter()
    logger.debug(f"[TIMING] build_parser: {(t6 - t5)*1000:.2f}ms")
    
    args = parser.parse_args(global_part + rest_part)
    t7 = time.perf_counter()
    logger.debug(f"[TIMING] parse_args: {(t7 - t6)*1000:.2f}ms")

    # 4) 전역 설정을 "CLI > .env > OS env > default"로 확정 + source 추적
    resolved: Dict[str, Tuple[str, str]] = {}

    api_url, api_url_src = resolve_value(
        "api-url", args.api_url, dotenv, "CONSUL_API_URL", default="http://localhost:8000"
    )
    api_key, api_key_src = resolve_value(
        "api-key", args.api_key, dotenv, "CONSUL_API_KEY", default=""
    )
    prefix, prefix_src = resolve_value(
        "prefix", args.prefix, dotenv, "CONSUL_PREFIX", default=""
    )
    app, app_src = resolve_value(
        "app", args.app, dotenv, "CONSUL_APP", default=""
    )
    env_name, env_src = resolve_value(
        "env", args.env_name, dotenv, "CONSUL_ENV", default=""
    )
    log_level, log_src = resolve_value(
        "log-level", args.log_level, dotenv, "CONSUL_LOG_LEVEL", default="INFO"
    )
    timeout, timeout_src = resolve_value(
        "timeout", str(args.timeout) if args.timeout else None, dotenv, "CONSUL_TIMEOUT", default="5"
    )
    
    t8 = time.perf_counter()
    logger.debug(f"[TIMING] resolve configuration values: {(t8 - t7)*1000:.2f}ms")

    # strict-mode: CLI 플래그가 True면 무조건 CLI 우선.
    # CLI에서 안 켰으면(.env/OS env에 CONSUL_STRICT_MODE=true가 있으면 켜기)
    if getattr(args, 'strict_mode', False):
        strict_mode, strict_src = True, "CLI(--strict-mode)"
    else:
        # .env / OS env에서만 읽음
        if "CONSUL_STRICT_MODE" in dotenv:
            strict_mode, strict_src = parse_bool(dotenv["CONSUL_STRICT_MODE"]), ".env(CONSUL_STRICT_MODE)"
        elif os.environ.get("CONSUL_STRICT_MODE") is not None:
            strict_mode, strict_src = parse_bool(os.environ.get("CONSUL_STRICT_MODE", "")), "OS_ENV(CONSUL_STRICT_MODE)"
        else:
            strict_mode, strict_src = False, "DEFAULT"

    # use-quotes: CLI 플래그가 True면 무조건 CLI 우선.
    # CLI에서 안 켰으면(.env/OS env에 CONSUL_USE_QUOTES=true가 있으면 켜기)
    if args.use_quotes:
        use_quotes, quotes_src = True, "CLI(--use-quotes)"
    else:
        # .env / OS env에서만 읽음
        if "CONSUL_USE_QUOTES" in dotenv:
            use_quotes, quotes_src = parse_bool(dotenv["CONSUL_USE_QUOTES"]), ".env(CONSUL_USE_QUOTES)"
        elif os.environ.get("CONSUL_USE_QUOTES") is not None:
            use_quotes, quotes_src = parse_bool(os.environ.get("CONSUL_USE_QUOTES", "")), "OS_ENV(CONSUL_USE_QUOTES)"
        else:
            use_quotes, quotes_src = False, "DEFAULT"

    # strict_mode 설정 추가
    strict_mode, strict_src = resolve_value(
        "strict-mode", None, dotenv, "CONSUL_STRICT_MODE", default="false", cast=parse_bool
    )

    resolved["ENV_FILE"] = (env_file or "", f"{'CLI/DEFAULT' if env_file else 'NONE'}")
    resolved["CONSUL_API_URL"] = (api_url, api_url_src)
    resolved["CONSUL_API_KEY"] = ("***" if api_key else None, api_key_src)
    resolved["CONSUL_PREFIX"] = (prefix, prefix_src)
    resolved["CONSUL_APP"] = (app, app_src)
    resolved["CONSUL_ENV"] = (env_name, env_src)
    resolved["CONSUL_LOG_LEVEL"] = (log_level, log_src)
    resolved["CONSUL_TIMEOUT"] = (timeout, timeout_src)
    resolved["CONSUL_USE_QUOTES"] = (use_quotes, quotes_src)
    resolved["CONSUL_STRICT_MODE"] = (strict_mode, strict_src)

    auto_prefix = None
    if (not prefix or prefix == "") and app and app != "" and env_name and env_name != "":
        auto_prefix = f"{app}/{env_name}".strip("/")
        prefix = auto_prefix
        prefix_src = "AUTO(app/env)"
        resolved["CONSUL_PREFIX"] = (prefix, prefix_src)

    if args.command == 'export' and app and app != "":
        if (not env_name or env_name == "") and not args.all_env:
            logger.error("Safety check: When --app is specified, you must specify either:")
            logger.error("  --env <environment>     (safe: specific environment only)")
            logger.error("  --all-env              (dangerous: all environments)")
            logger.error("")
            logger.error("This prevents accidentally exporting configurations from all environments.")
            sys.exit(1)
        
        if args.all_env:
            logger.warning(f"⚠️  Using --all-env: This will include ALL environments for app '{app}'")
            logger.warning("⚠️  Make sure this is what you intended!")
            # --all-env 사용 시 prefix를 app만으로 설정
            prefix = app
            prefix_src = "AUTO(app/all-env)"
            resolved["CONSUL_PREFIX"] = (prefix, prefix_src)

    # 5) verbose 출력
    if args.verbose:
        print("=== Effective Configuration (with sources) ===")
        if env_file:
            print(f"- ENV_FILE: {env_file} (loaded: YES)")
        else:
            print(f"- ENV_FILE: (none) (loaded: NO)")
        for k in [
            "CONSUL_API_URL",
            "CONSUL_API_KEY",
            "CONSUL_APP",
            "CONSUL_ENV",
            "CONSUL_PREFIX",
            "CONSUL_LOG_LEVEL",
            "CONSUL_TIMEOUT",
            "CONSUL_USE_QUOTES",
            "CONSUL_STRICT_MODE",
        ]:
            v, src = resolved[k]
            print(f"- {k}: {v}    <- {src}")
        print("")

    # 6) 로깅 레벨 적용
    if args.quiet:
        # --quiet 모드: WARNING 이상만 출력
        logger.setLevel(logging.WARNING)
    elif args.verbose:
        # --verbose 모드: DEBUG 레벨로 타이밍 로그 출력
        logger.setLevel(logging.DEBUG)
        urllib3_logger.setLevel(logging.DEBUG)
        
        # DNS 타이밍 추적 활성화
        global _dns_patched
        if not _dns_patched:
            socket.getaddrinfo = _timed_getaddrinfo
            _dns_patched = True
            logger.debug("[TIMING] DNS timing tracking enabled")
    else:
        logger.setLevel(getattr(logging, str(log_level).upper(), logging.INFO))

    if not api_key or api_key == "":
        logger.error("API key required. (CLI --api-key) or .env/OS env CONSUL_API_KEY")
        sys.exit(1)

    if not app or app == "":
        logger.error("App name required. (CLI --app) or .env/OS env CONSUL_APP")
        sys.exit(1)
        
    if not env_name or env_name == "":
        logger.error("Environment name required. (CLI --env) or .env/OS env CONSUL_ENV")
        sys.exit(1)

    t_config_end = time.perf_counter()
    logger.debug(f"[TIMING] Total configuration setup: {(t_config_end - start_time)*1000:.2f}ms")
    

    client = ConsulAPIClient(
        base_url=str(api_url),
        api_key=str(api_key),
        prefix=str(prefix) if prefix else '',
        timeout=int(timeout) if isinstance(timeout, (int, str)) else 5,
        quote_values=bool(use_quotes),
    )
    
    t_client = time.perf_counter()
    logger.debug(f"[TIMING] ConsulAPIClient initialization: {(t_client - t_config_end)*1000:.2f}ms")

    # App/Env 존재 여부 검증 (export 명령어에서만 수행)
    if args.command == 'export' and app and app != "":
        t_validation_start = time.perf_counter()
        
        # --all-env 사용 시에는 env 검증 생략
        validation_env = env_name if not args.all_env else ""
        
        exists, validation_msg = client.validate_app_env_existence(
            app=str(app), 
            env_name=str(validation_env), 
            strict_mode=bool(strict_mode)
        )
        
        t_validation_end = time.perf_counter()
        logger.debug(f"[TIMING] App/Env validation: {(t_validation_end - t_validation_start)*1000:.2f}ms")
        
        if not exists:
            if strict_mode:
                # Strict mode: 에러로 처리하고 종료
                logger.error(validation_msg)
                sys.exit(1)
            else:
                # Non-strict mode: 경고만 출력하고 계속 진행
                logger.warning(validation_msg)
                logger.warning("Continuing anyway... (set CONSUL_STRICT_MODE=true to make this an error)")
        else:
            # 성공 시에는 verbose 모드에서만 출력
            if args.verbose:
                logger.info(validation_msg)

    try:
        if args.command == 'get':
            t_cmd_start = time.perf_counter()
            decrypt = not args.no_decrypt
            value = client.get_config(args.key, decrypt=decrypt)
            t_cmd_end = time.perf_counter()
            logger.debug(f"[TIMING] Command 'get' execution: {(t_cmd_end - t_cmd_start)*1000:.2f}ms")
            
            if value is None:
                logger.error(f"Key not found: {args.key}")
                sys.exit(1)
            print(f"{args.key}: {value}" if args.with_key else value)

        elif args.command == 'list':
            t_cmd_start = time.perf_counter()
            cfgs = client.get_all_configs(decrypt=args.decrypt)
            t_fetch = time.perf_counter()
            logger.debug(f"[TIMING] Command 'list' - fetch: {(t_fetch - t_cmd_start)*1000:.2f}ms")
            
            if args.match:
                cfgs = {k: v for k, v in cfgs.items() if args.match in k}
            for k in sorted(cfgs.keys()):
                print(f"{k}: {cfgs[k]}")
            
            t_cmd_end = time.perf_counter()
            logger.debug(f"[TIMING] Command 'list' - total: {(t_cmd_end - t_cmd_start)*1000:.2f}ms")
            logger.info(f"Total: {len(cfgs)} configurations")

        elif args.command == 'export':
            t_cmd_start = time.perf_counter()
            
            # 실제 export 수행 (한 번의 HTTP 요청으로 처리)
            out = client.export_to_env(
                decrypt=not args.no_decrypt,
                mask_secrets=args.mask_secrets,
                strip_prefix=args.strip_prefix,
                format_type=args.format,
                uppercase=not args.no_uppercase,
                sort_keys=not args.no_sort,
            )
            
            t_export = time.perf_counter()
            logger.debug(f"[TIMING] Command 'export' - export_to_env: {(t_export - t_cmd_start)*1000:.2f}ms")
            
            # 출력 (stdout 또는 파일)
            write_output(out, args.output, args.overwrite)
            
            t_write = time.perf_counter()
            logger.debug(f"[TIMING] Command 'export' - write_output: {(t_write - t_export)*1000:.2f}ms")
            logger.debug(f"[TIMING] Command 'export' - total: {(t_write - t_cmd_start)*1000:.2f}ms")
            
            # 요약 정보 (stderr로 출력) - 출력 결과에서 라인 수 계산
            if not args.quiet:
                if args.output and args.output != '-':
                    # 파일 출력 시에는 write_output에서 이미 "✓ Wrote" 메시지 출력됨
                    pass
                else:
                    # stdout 출력 시에만 요약 출력
                    config_count = len([line for line in out.split('\n') if line.strip() and not line.strip().startswith('#')])
                    decrypt_status = "decrypted" if not args.no_decrypt else "encrypted"
                    mask_status = " (secrets masked)" if args.mask_secrets else ""
                    logger.info(f"Exported {config_count} configurations ({decrypt_status}){mask_status}")

        elif args.command == 'set':
            t_cmd_start = time.perf_counter()
            ok = client.set_config(args.key, args.value, is_secret=args.secret)
            t_cmd_end = time.perf_counter()
            logger.debug(f"[TIMING] Command 'set' execution: {(t_cmd_end - t_cmd_start)*1000:.2f}ms")
            
            if ok:
                logger.info(f"✓ Successfully set key: {args.key}")
                if args.secret:
                    logger.info("  (Value encrypted on server)")
            else:
                logger.error("Failed to set configuration")
                sys.exit(1)

        elif args.command == 'delete':
            t_cmd_start = time.perf_counter()
            if not args.yes:
                ans = input(f"Delete key '{args.key}'? [y/N]: ").strip().lower()
                if ans not in ('y', 'yes'):
                    logger.info("Cancelled")
                    sys.exit(0)
            ok = client.delete_config(args.key)
            t_cmd_end = time.perf_counter()
            logger.debug(f"[TIMING] Command 'delete' execution: {(t_cmd_end - t_cmd_start)*1000:.2f}ms")
            
            if ok:
                logger.info(f"✓ Successfully deleted key: {args.key}")
            else:
                logger.error("Failed to delete configuration")
                sys.exit(1)

        elif args.command == 'count':
            t_cmd_start = time.perf_counter()
            cfgs = client.get_all_configs(decrypt=args.decrypt)
            t_cmd_end = time.perf_counter()
            logger.debug(f"[TIMING] Command 'count' execution: {(t_cmd_end - t_cmd_start)*1000:.2f}ms")
            
            count = len(cfgs)
            print(count)
            logger.info(f"Total: {count} configurations")
        
        # 전체 실행 시간 출력
        total_time = time.perf_counter() - start_time
        logger.debug(f"[TIMING] ========================================")
        logger.debug(f"[TIMING] TOTAL SCRIPT EXECUTION: {total_time*1000:.2f}ms ({total_time:.3f}s)")
        logger.debug(f"[TIMING] ========================================")

    except KeyboardInterrupt:
        logger.info("Operation cancelled")
        sys.exit(1)
    except Exception as e:
        logger.error(f"Error: {e}")
        sys.exit(1)


if __name__ == '__main__':
    main()
