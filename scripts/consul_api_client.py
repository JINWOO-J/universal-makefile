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
from typing import Optional, Dict, Tuple


# 로깅 기본 설정
logging.basicConfig(
    level=logging.INFO,
    format='%(levelname)s: %(message)s'
)
logger = logging.getLogger(__name__)


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
) -> Tuple[object, str]:
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
        self.base_url = base_url.rstrip('/')
        self.api_key = api_key
        self.prefix = prefix.strip('/')
        self.timeout = timeout
        self.quote_values = quote_values

        self.session = requests.Session()
        self.session.headers.update({'X-API-Key': api_key})

    def get_config(self, key: str, decrypt: bool = True) -> Optional[str]:
        """단일 설정 조회"""
        resp = self.session.get(
            f"{self.base_url}/api/v1/config/{key}",
            params={'prefix': self.prefix, 'decrypt': decrypt},
            timeout=self.timeout,
        )
        if resp.status_code == 404:
            return None
        resp.raise_for_status()
        data = resp.json()
        return data['value']

    def get_all_configs(self, decrypt: bool = False, mask_secrets: bool = True) -> Dict[str, str]:
        """prefix 아래 모든 설정 조회 (일괄)"""
        if decrypt:
            # 복호화된 값을 빠르게 가져오기
            resp = self.session.get(
                f"{self.base_url}/api/v1/export/json",
                params={'prefix': self.prefix, 'decrypt': 'true'},
                timeout=self.timeout,
            )
            resp.raise_for_status()
            data = resp.json()
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
        items = self.get_all_configs(decrypt=decrypt, mask_secrets=mask_secrets)

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

        return '\n'.join(lines)

    def set_config(self, key: str, value: str, is_secret: bool = False) -> bool:
        """설정 저장"""
        try:
            resp = self.session.post(
                f"{self.base_url}/api/v1/config",
                params={'prefix': self.prefix},
                json={'key': key, 'value': value, 'is_secret': is_secret},
                timeout=self.timeout,
            )
            resp.raise_for_status()
            return True
        except Exception as e:
            logger.error(f"Failed to set config: {e}")
            return False

    def delete_config(self, key: str) -> bool:
        """설정 삭제"""
        try:
            resp = self.session.delete(
                f"{self.base_url}/api/v1/config/{key}",
                params={'prefix': self.prefix},
                timeout=self.timeout,
            )
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
    parser.add_argument('--log-level', default=None,
                        choices=['DEBUG', 'INFO', 'WARNING', 'ERROR'],
                        help='Logging level (env: CONSUL_LOG_LEVEL)')
    parser.add_argument('--timeout', type=int, default=None,
                        help='HTTP request timeout in seconds (env: CONSUL_TIMEOUT)')
    parser.add_argument('--use-quotes', action='store_true',
                        help='Wrap values with double quotes in env format (env: CONSUL_USE_QUOTES=true)')
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
    sp_export.add_argument('--output', help='Output file')

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
    argv = sys.argv[1:]
    global_part, rest_part = extract_global_args(argv)

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

    dotenv = load_dotenv_file(env_file) if env_file else {}

    # 2) 파서 실행 (CLI 값 확보)
    parser = build_parser()
    args = parser.parse_args(global_part + rest_part)

    if not args.command:
        parser.print_help()
        sys.exit(1)

    # 3) 전역 설정을 "CLI > .env > OS env > default"로 확정 + source 추적
    resolved: Dict[str, Tuple[object, str]] = {}

    api_url, api_url_src = resolve_value(
        "api-url", args.api_url, dotenv, "CONSUL_API_URL", default="http://localhost:8000"
    )
    api_key, api_key_src = resolve_value(
        "api-key", args.api_key, dotenv, "CONSUL_API_KEY", default=None
    )
    prefix, prefix_src = resolve_value(
        "prefix", args.prefix, dotenv, "CONSUL_PREFIX", default=None
    )
    app, app_src = resolve_value(
        "app", args.app, dotenv, "CONSUL_APP", default=None
    )
    env_name, env_src = resolve_value(
        "env", args.env_name, dotenv, "CONSUL_ENV", default=None
    )
    log_level, log_src = resolve_value(
        "log-level", args.log_level, dotenv, "CONSUL_LOG_LEVEL", default="INFO"
    )
    timeout, timeout_src = resolve_value(
        "timeout", args.timeout, dotenv, "CONSUL_TIMEOUT", default=5, cast=int
    )

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

    resolved["ENV_FILE"] = (env_file or "", f"{'CLI/DEFAULT' if env_file else 'NONE'}")
    resolved["CONSUL_API_URL"] = (api_url, api_url_src)
    resolved["CONSUL_API_KEY"] = ("***" if api_key else None, api_key_src)
    resolved["CONSUL_PREFIX"] = (prefix, prefix_src)
    resolved["CONSUL_APP"] = (app, app_src)
    resolved["CONSUL_ENV"] = (env_name, env_src)
    resolved["CONSUL_LOG_LEVEL"] = (log_level, log_src)
    resolved["CONSUL_TIMEOUT"] = (timeout, timeout_src)
    resolved["CONSUL_USE_QUOTES"] = (use_quotes, quotes_src)

    # 4) prefix 자동 구성( prefix 없고 app/env 있으면 )
    auto_prefix = None
    if not prefix and app and env_name:
        auto_prefix = f"{app}/{env_name}".strip("/")
        prefix = auto_prefix
        prefix_src = "AUTO(app/env)"
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
        ]:
            v, src = resolved[k]
            print(f"- {k}: {v}    <- {src}")
        print("")

    # 6) 로깅 레벨 적용
    logger.setLevel(getattr(logging, str(log_level).upper(), logging.INFO))

    if not api_key:
        logger.error("API key required. (CLI --api-key) or .env/OS env CONSUL_API_KEY")
        sys.exit(1)

    client = ConsulAPIClient(
        base_url=str(api_url),
        api_key=str(api_key),
        prefix=prefix or '',
        timeout=int(timeout),
        quote_values=bool(use_quotes),
    )

    try:
        if args.command == 'get':
            decrypt = not args.no_decrypt
            value = client.get_config(args.key, decrypt=decrypt)
            if value is None:
                logger.error(f"Key not found: {args.key}")
                sys.exit(1)
            print(f"{args.key}: {value}" if args.with_key else value)

        elif args.command == 'list':
            cfgs = client.get_all_configs(decrypt=args.decrypt)
            if args.match:
                cfgs = {k: v for k, v in cfgs.items() if args.match in k}
            for k in sorted(cfgs.keys()):
                print(f"{k}: {cfgs[k]}")
            logger.info(f"Total: {len(cfgs)} configurations")

        elif args.command == 'export':
            out = client.export_to_env(
                decrypt=not args.no_decrypt,
                mask_secrets=args.mask_secrets,
                strip_prefix=args.strip_prefix,
                format_type=args.format,
                uppercase=not args.no_uppercase,
                sort_keys=not args.no_sort,
            )
            if args.output:
                with open(args.output, 'w', encoding="utf-8") as f:
                    f.write(out)
                    f.write('\n')
                logger.info(f"✓ Wrote {args.output}")
            else:
                print(out)

        elif args.command == 'set':
            ok = client.set_config(args.key, args.value, is_secret=args.secret)
            if ok:
                logger.info(f"✓ Successfully set key: {args.key}")
                if args.secret:
                    logger.info("  (Value encrypted on server)")
            else:
                logger.error("Failed to set configuration")
                sys.exit(1)

        elif args.command == 'delete':
            if not args.yes:
                ans = input(f"Delete key '{args.key}'? [y/N]: ").strip().lower()
                if ans not in ('y', 'yes'):
                    logger.info("Cancelled")
                    sys.exit(0)
            ok = client.delete_config(args.key)
            if ok:
                logger.info(f"✓ Successfully deleted key: {args.key}")
            else:
                logger.error("Failed to delete configuration")
                sys.exit(1)

        elif args.command == 'count':
            cfgs = client.get_all_configs(decrypt=args.decrypt)
            count = len(cfgs)
            print(count)
            logger.info(f"Total: {count} configurations")

    except KeyboardInterrupt:
        logger.info("Operation cancelled")
        sys.exit(1)
    except Exception as e:
        logger.error(f"Error: {e}")
        sys.exit(1)


if __name__ == '__main__':
    main()
