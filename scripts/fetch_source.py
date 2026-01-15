#!/usr/bin/env python3
"""
소스 코드 fetch 스크립트 (Python 버전)

사용법:
    python fetch_source.py <COMMAND> [OPTIONS]

COMMANDS (필수):
    clone  : 기존 삭제 후 새로 clone
    reset  : git fetch + reset --hard (로컬 변경사항 무시, remote 우선)
    pull   : git pull (로컬 변경사항 병합 시도)
    keep   : fetch만 실행 (로컬 상태 유지)

OPTIONS:
    --dir, -d : 소스 디렉토리 (기본값: 현재 디렉토리)
    --ref, -b : 체크아웃할 브랜치/태그 (생략 시 자동 감지)
    --repo, -r: 저장소 URL (생략 시 자동 감지)
    --fetch-all, -a: 모든 remote fetch
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Optional


class Color:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[0;33m'
    BLUE = '\033[0;34m'
    NC = '\033[0m'

def supports_color() -> bool:
    return hasattr(sys.stdout, 'isatty') and sys.stdout.isatty()

def colorize(text: str, color: str) -> str:
    if supports_color():
        return f"{color}{text}{Color.NC}"
    return text

def log_info(msg: str):
    print(colorize(f"[INFO]", Color.BLUE) + f" {msg}")

def log_warn(msg: str):
    print(colorize(f"[WARN]", Color.YELLOW) + f" {msg}")

def log_error(msg: str):
    print(colorize(f"[ERROR]", Color.RED) + f" {msg}")

def log_ok(msg: str):
    print(colorize(f"[OK]", Color.GREEN) + f" {msg}")

class FetchError(Exception):
    pass


class SyncMode(Enum):
    CLONE = "clone"
    RESET = "reset"
    PULL = "pull"
    KEEP = "keep"

@dataclass
class FetchConfig:
    source_dir: Path
    source_repo: Optional[str]
    ref: Optional[str]
    sync_mode: Optional[SyncMode]
    fetch_all: bool = False


def run_git(args: list[str], cwd: Optional[Path] = None, check: bool = True,
            capture: bool = False) -> subprocess.CompletedProcess:
    cmd = ["git"] + args
    try:
        result = subprocess.run(
            cmd,
            cwd=cwd,
            check=check,
            capture_output=capture,
            text=True,
        )
        return result
    except subprocess.CalledProcessError as e:
        if check:
            raise FetchError(f"git 명령 실패: {' '.join(cmd)}\n{e.stderr or ''}")
        return e

def get_current_branch(cwd: Path) -> str:
    try:
        result = run_git(["branch", "--show-current"], cwd=cwd, capture=True)
        return result.stdout.strip() or "detached"
    except FetchError:
        return "detached"

def get_commit_hash(cwd: Path, short: bool = True) -> str:
    args = ["rev-parse", "--short", "HEAD"] if short else ["rev-parse", "HEAD"]
    result = run_git(args, cwd=cwd, capture=True)
    return result.stdout.strip()

def is_git_repo(path: Path) -> bool:
    return (path / ".git").is_dir()

def get_remote_url(cwd: Path, remote: str = "origin") -> Optional[str]:
    try:
        result = run_git(["remote", "get-url", remote], cwd=cwd, capture=True)
        return result.stdout.strip()
    except FetchError:
        return None

def extract_repo_from_url(url: str) -> str:
    patterns = [
        r"github\.com[:/]([^/]+/[^/]+?)(?:\.git)?$",
        r"github\.com[:/]([^/]+/[^/]+)$",
    ]
    for pattern in patterns:
        match = re.search(pattern, url)
        if match:
            return match.group(1).rstrip('.git')
    return url

def build_git_url(repo: str) -> str:
    if repo.startswith(("https://", "git@")):
        return repo
    gh_token = os.environ.get("GH_TOKEN", "")
    if gh_token:
        return f"https://{gh_token}@github.com/{repo}.git"
    return f"https://github.com/{repo}.git"

def mask_token_url(url: str) -> str:
    gh_token = os.environ.get("GH_TOKEN", "")
    if gh_token:
        return url.replace(gh_token, "***TOKEN***")
    return url


def do_clone(git_url: str, target_dir: Path):
    target_dir.mkdir(parents=True, exist_ok=True)
    log_info(f"저장소 클론: {mask_token_url(git_url)}")
    if target_dir.exists() and any(target_dir.iterdir()):
        shutil.rmtree(target_dir)
    run_git(["clone", git_url, str(target_dir)])

def do_fetch(cwd: Path, fetch_all: bool = False):
    if fetch_all:
        log_info("모든 remote 가져오는 중...")
        run_git(["fetch", "--all", "--prune"], cwd=cwd)
    else:
        log_info("기존 저장소 업데이트 중...")
        run_git(["fetch", "origin", "--prune"], cwd=cwd)

def checkout_pr_ref(cwd: Path, ref: str, force: bool = False):
    match = re.search(r"refs/pull/(\d+)/", ref)
    if not match:
        raise FetchError(f"잘못된 PR 참조: {ref}")

    pr_number = match.group(1)
    branch_name = f"pr-{pr_number}"

    log_info(f"PR 참조 감지: #{pr_number} → {branch_name}")
    
    current_branch = get_current_branch(cwd)
    if current_branch == branch_name:
        run_git(["checkout", "--detach", "HEAD"], cwd=cwd, check=False)

    run_git(["branch", "-D", branch_name], cwd=cwd, check=False)
    run_git(["fetch", "origin", f"{ref}:{branch_name}"], cwd=cwd)

    checkout_args = ["checkout", "-f", branch_name] if force else ["checkout", branch_name]
    run_git(checkout_args, cwd=cwd)

def checkout_branch_ref(cwd: Path, ref: str, force: bool = False):
    if force:
        try:
            run_git(["checkout", "-f", "-B", ref, f"origin/{ref}"], cwd=cwd)
        except FetchError:
            run_git(["checkout", "-f", ref], cwd=cwd)
    else:
        run_git(["checkout", ref], cwd=cwd)

def checkout_ref(cwd: Path, ref: str, force: bool = False):
    if ref.startswith("refs/pull/"):
        checkout_pr_ref(cwd, ref, force)
    else:
        checkout_branch_ref(cwd, ref, force)

def do_reset(cwd: Path, ref: str):
    log_warn("remote로 강제 리셋 중...")
    reset_target = "HEAD" if ref.startswith("refs/pull/") else f"origin/{ref}"
    try:
        run_git(["reset", "--hard", reset_target], cwd=cwd)
    except FetchError:
        log_warn("reset 타겟을 찾을 수 없어 HEAD로 리셋합니다.")
        run_git(["reset", "--hard", "HEAD"], cwd=cwd)

def do_pull(cwd: Path):
    current_branch = get_current_branch(cwd)
    log_info("로컬 변경사항 병합 시도 (pull)")
    try:
        run_git(["pull", "origin", current_branch], cwd=cwd)
    except FetchError:
        raise FetchError("병합 충돌 발생. 수동으로 해결이 필요합니다.")

def print_summary(cwd: Path):
    branch = get_current_branch(cwd)
    commit_hash = get_commit_hash(cwd)
    print("-" * 50)
    log_ok(f"완료: (브랜치: {branch}, 커밋: {commit_hash})")
    print("-" * 50)


def fetch_source(config: FetchConfig):
    if config.sync_mode is None:
        log_error("실행 모드(command)가 지정되지 않았습니다.")
        print(colorize("사용 가능한 명령: clone, reset, pull, keep", Color.YELLOW))
        print(f"예시: python {sys.argv[0]} reset --ref main")
        sys.exit(1)

    source_dir = config.source_dir.resolve()
    target_ref = config.ref

    log_info(f"작업 시작: {config.sync_mode.value.upper()}")
    
    if target_ref:
        print(f"  TARGET REF:  {target_ref}")
    else:
        print(f"  TARGET REF:  (Auto Detect)")
    
    need_clone = False
    force_reset = False
    do_pull_flag = False

    if source_dir.exists():
        if config.sync_mode == SyncMode.CLONE:
            log_info("모드(clone): 기존 디렉토리 삭제 후 재설치")
            need_clone = True
        elif config.sync_mode == SyncMode.RESET:
            if not is_git_repo(source_dir):
                raise FetchError(f"{source_dir} 는 git 저장소가 아닙니다 (reset 불가)")
            force_reset = True
        elif config.sync_mode == SyncMode.PULL:
            if not is_git_repo(source_dir):
                raise FetchError(f"{source_dir} 는 git 저장소가 아닙니다 (pull 불가)")
            do_pull_flag = True
        elif config.sync_mode == SyncMode.KEEP:
            if not is_git_repo(source_dir):
                raise FetchError(f"{source_dir} 는 git 저장소가 아닙니다")
    else:
        if config.sync_mode in [SyncMode.RESET, SyncMode.PULL, SyncMode.KEEP]:
             log_warn(f"디렉토리가 없어 {config.sync_mode.value} 대신 clone을 수행합니다.")
        need_clone = True

    if need_clone:
        if not config.source_repo:
             raise FetchError("Clone을 수행하려면 Repository 정보가 필요합니다 (--repo 또는 자동감지 실패)")
        git_url = build_git_url(config.source_repo)
        do_clone(git_url, source_dir)
        
        if target_ref is None:
            target_ref = get_current_branch(source_dir)
            log_info(f"Ref 미지정. Clone된 기본 브랜치 사용: {target_ref}")

    else:
        do_fetch(source_dir, config.fetch_all)
        
        if target_ref is None:
            target_ref = get_current_branch(source_dir)
            log_info(f"Ref 미지정. 현재 브랜치 유지: {target_ref}")

        if do_pull_flag:
            do_pull(source_dir)

    if target_ref != "detached":
        checkout_ref(source_dir, target_ref, force_reset)

        if force_reset:
            do_reset(source_dir, target_ref)
    else:
        log_warn("현재 Detached HEAD 상태입니다. 체크아웃/리셋을 건너뜁니다.")

    print_summary(source_dir)


def detect_repo_from_cwd() -> Optional[str]:
    cwd = Path.cwd()
    if not is_git_repo(cwd): return None
    url = get_remote_url(cwd)
    return extract_repo_from_url(url) if url else None

def detect_repo_from_source_dir(source_dir: Path) -> Optional[str]:
    if not source_dir.exists() or not is_git_repo(source_dir): return None
    url = get_remote_url(source_dir)
    return extract_repo_from_url(url) if url else None

def parse_args() -> FetchConfig:
    parser = argparse.ArgumentParser(
        description="소스 코드 fetch 스크립트",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )

    parser.add_argument(
        "mode",
        nargs="?",     # 0개 또는 1개 인자 허용
        choices=["clone", "reset", "pull", "keep"],
        help="동기화 모드 (필수 지정)"
    )

    parser.add_argument(
        "--dir", "-d",
        dest="source_dir",
        type=Path,
        default=Path("."),
        help="소스 디렉토리 (기본값: 현재 디렉토리)"
    )
    
    parser.add_argument(
        "--ref", "-b",
        dest="ref",
        required=False,
        default=None,
        help="체크아웃할 참조. 생략 시 현재/기본 브랜치 사용"
    )

    parser.add_argument(
        "--repo", "-r",
        dest="source_repo",
        default=None,
        help="GitHub 저장소. 생략시 자동 감지"
    )

    parser.add_argument(
        "--fetch-all", "-a",
        action="store_true",
        help="모든 remote fetch"
    )

    args = parser.parse_args()

    sync_mode = SyncMode(args.mode) if args.mode else None

    source_repo = args.source_repo
    if source_repo is None:
        source_dir_resolved = args.source_dir.resolve()
        source_repo = detect_repo_from_source_dir(source_dir_resolved)
        if not source_repo:
            source_repo = detect_repo_from_cwd()

        if source_repo:
            log_info(f"Repository 감지됨: {source_repo}")

    return FetchConfig(
        source_dir=args.source_dir,
        source_repo=source_repo,
        ref=args.ref,
        sync_mode=sync_mode,
        fetch_all=args.fetch_all,
    )

def main():
    try:
        config = parse_args()
        fetch_source(config)
    except FetchError as e:
        log_error(str(e))
        sys.exit(1)
    except KeyboardInterrupt:
        print()
        log_warn("중단됨")
        sys.exit(130)


if __name__ == "__main__":
    main()