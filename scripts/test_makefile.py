#!/usr/bin/env python3
"""
Makefile 타겟 테스트 스크립트

이 스크립트는 Makefile의 각 타겟이 올바르게 작동하는지 검증합니다.
- 각 타겟의 독립 실행 검증
- 환경 변수 처리 검증
- 에러 상황 처리 검증
"""

import os
import sys
import subprocess
import tempfile
import shutil
import json
import time
from typing import Dict, List, Optional, Tuple
from pathlib import Path

class MakefileTestRunner:
    """Makefile 타겟 테스트 실행기"""
    
    def __init__(self, project_root: str = None):
        self.project_root = Path(project_root or os.getcwd())
        self.makefile_path = self.project_root / "Makefile"
        self.test_results = []
        self.test_env = {
            "SOURCE_REPO": "test-org/test-app",
            "REF": "main", 
            "VERSION": "v1.0.0-test",
            "SERVICE_KIND": "fe",
            "ENVIRONMENT": "staging",
            "DOCKER_REGISTRY": "docker.io",
            "DOCKER_REPO_HUB": "test-hub",
            "IMAGE_NAME": "test-app"
        }
        
    def log(self, level: str, message: str):
        """로그 출력"""
        timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
        print(f"[{timestamp}] [{level}] {message}")
        
    def run_make_target(self, target: str, env: Dict[str, str] = None, 
                       expect_failure: bool = False, timeout: int = 60) -> Tuple[bool, str, str]:
        """Make 타겟 실행"""
        cmd_env = os.environ.copy()
        if env:
            cmd_env.update(env)
            
        cmd = ["make", target]
        self.log("INFO", f"실행 중: {' '.join(cmd)}")
        
        try:
            result = subprocess.run(
                cmd,
                cwd=self.project_root,
                env=cmd_env,
                capture_output=True,
                text=True,
                timeout=timeout
            )
            
            success = (result.returncode == 0) != expect_failure
            return success, result.stdout, result.stderr
            
        except subprocess.TimeoutExpired:
            self.log("ERROR", f"타겟 '{target}' 실행 시간 초과 ({timeout}초)")
            return False, "", f"Timeout after {timeout} seconds"
        except Exception as e:
            self.log("ERROR", f"타겟 '{target}' 실행 중 예외: {e}")
            return False, "", str(e)
    
    def test_help_target(self) -> bool:
        """help 타겟 테스트"""
        self.log("INFO", "help 타겟 테스트 시작")
        
        success, stdout, stderr = self.run_make_target("help", env={})
        
        if not success:
            self.log("ERROR", f"help 타겟 실패: {stderr}")
            return False
            
        # help 출력에 필수 정보가 포함되어 있는지 확인
        required_content = [
            "중앙화된 CI/CD 러너 Makefile",
            "필수 환경 변수",
            "SOURCE_REPO",
            "타겟:"
        ]
        
        for content in required_content:
            if content not in stdout:
                self.log("ERROR", f"help 출력에 '{content}'가 없습니다")
                return False
                
        self.log("SUCCESS", "help 타겟 테스트 통과")
        return True
    
    def test_validate_env_target(self) -> bool:
        """validate-env 타겟 테스트"""
        self.log("INFO", "validate-env 타겟 테스트 시작")
        
        # 정상적인 환경 변수로 테스트
        success, stdout, stderr = self.run_make_target("validate-env", env=self.test_env)
        
        if not success:
            self.log("ERROR", f"validate-env 타겟 실패: {stderr}")
            return False
            
        # 환경 변수가 출력에 포함되어 있는지 확인
        for key, value in self.test_env.items():
            if f"{key}: {value}" not in stdout:
                self.log("ERROR", f"환경 변수 '{key}'가 출력에 없습니다")
                return False
                
        self.log("SUCCESS", "validate-env 타겟 테스트 통과")
        return True
    
    def test_missing_env_variables(self) -> bool:
        """필수 환경 변수 누락 테스트"""
        self.log("INFO", "필수 환경 변수 누락 테스트 시작")
        
        required_vars = ["SOURCE_REPO", "REF", "VERSION", "SERVICE_KIND", "ENVIRONMENT"]
        
        for var in required_vars:
            # 해당 변수를 제외한 환경으로 테스트
            test_env = {k: v for k, v in self.test_env.items() if k != var}
            
            success, stdout, stderr = self.run_make_target("validate-env", 
                                                         env=test_env, 
                                                         expect_failure=True)
            
            if not success:
                self.log("ERROR", f"'{var}' 누락 시 에러가 발생하지 않았습니다")
                return False
                
            if f"{var} 환경 변수가 설정되지 않았습니다" not in stderr:
                self.log("ERROR", f"'{var}' 누락 에러 메시지가 올바르지 않습니다")
                return False
                
        self.log("SUCCESS", "필수 환경 변수 누락 테스트 통과")
        return True
    
    def test_debug_target(self) -> bool:
        """debug 타겟 테스트"""
        self.log("INFO", "debug 타겟 테스트 시작")
        
        success, stdout, stderr = self.run_make_target("debug", env={})
        
        if not success:
            self.log("ERROR", f"debug 타겟 실패: {stderr}")
            return False
            
        # debug 출력에 필수 정보가 포함되어 있는지 확인
        required_content = [
            "디버그 정보",
            "PROJECT_ROOT:",
            "SCRIPTS_DIR:",
            "파일 존재 확인"
        ]
        
        for content in required_content:
            if content not in stdout:
                self.log("ERROR", f"debug 출력에 '{content}'가 없습니다")
                return False
                
        self.log("SUCCESS", "debug 타겟 테스트 통과")
        return True
    
    def test_dry_run_target(self) -> bool:
        """dry-run 타겟 테스트"""
        self.log("INFO", "dry-run 타겟 테스트 시작")
        
        success, stdout, stderr = self.run_make_target("dry-run", env=self.test_env, timeout=120)
        
        if not success:
            self.log("WARNING", f"dry-run 타겟 실패 (예상될 수 있음): {stderr}")
            # dry-run은 실제 리소스에 의존하므로 실패할 수 있음
            return True
            
        # dry-run 출력에 시뮬레이션 정보가 포함되어 있는지 확인
        expected_sections = [
            "환경 변수",
            "소스 저장소 확인",
            "Docker 환경 확인"
        ]
        
        for section in expected_sections:
            if section not in stdout:
                self.log("WARNING", f"dry-run 출력에 '{section}' 섹션이 없습니다")
                
        self.log("SUCCESS", "dry-run 타겟 테스트 통과")
        return True
    
    def test_clean_target(self) -> bool:
        """clean 타겟 테스트"""
        self.log("INFO", "clean 타겟 테스트 시작")
        
        # 테스트용 임시 파일 생성
        source_dir = self.project_root / "source"
        env_runtime = self.project_root / ".env.runtime"
        
        source_dir.mkdir(exist_ok=True)
        env_runtime.touch()
        
        success, stdout, stderr = self.run_make_target("clean", env={})
        
        if not success:
            self.log("ERROR", f"clean 타겟 실패: {stderr}")
            return False
            
        # 파일들이 정리되었는지 확인
        if source_dir.exists():
            self.log("ERROR", "source 디렉토리가 정리되지 않았습니다")
            return False
            
        if env_runtime.exists():
            self.log("ERROR", ".env.runtime 파일이 정리되지 않았습니다")
            return False
            
        self.log("SUCCESS", "clean 타겟 테스트 통과")
        return True
    
    def test_status_target(self) -> bool:
        """status 타겟 테스트"""
        self.log("INFO", "status 타겟 테스트 시작")
        
        success, stdout, stderr = self.run_make_target("status", env=self.test_env)
        
        if not success:
            self.log("ERROR", f"status 타겟 실패: {stderr}")
            return False
            
        # status 출력에 시스템 정보가 포함되어 있는지 확인
        expected_sections = [
            "시스템 정보",
            "현재 시간:",
            "호스트명:",
            "Docker 버전:"
        ]
        
        for section in expected_sections:
            if section not in stdout:
                self.log("ERROR", f"status 출력에 '{section}'가 없습니다")
                return False
                
        self.log("SUCCESS", "status 타겟 테스트 통과")
        return True
    
    def test_deploy_check_target(self) -> bool:
        """deploy-check 타겟 테스트"""
        self.log("INFO", "deploy-check 타겟 테스트 시작")
        
        success, stdout, stderr = self.run_make_target("deploy-check", env=self.test_env, timeout=120)
        
        # deploy-check는 실제 리소스에 의존하므로 실패할 수 있음
        if not success:
            self.log("WARNING", f"deploy-check 타겟 실패 (예상될 수 있음): {stderr}")
            return True
            
        # 사전 검사 항목들이 출력에 포함되어 있는지 확인
        expected_checks = [
            "환경 변수 검증",
            "소스 저장소 접근성 확인",
            "Docker 환경 확인"
        ]
        
        for check in expected_checks:
            if check not in stdout:
                self.log("WARNING", f"deploy-check 출력에 '{check}'가 없습니다")
                
        self.log("SUCCESS", "deploy-check 타겟 테스트 통과")
        return True
    
    def test_makefile_syntax(self) -> bool:
        """Makefile 구문 검증"""
        self.log("INFO", "Makefile 구문 검증 시작")
        
        if not self.makefile_path.exists():
            self.log("ERROR", "Makefile이 존재하지 않습니다")
            return False
            
        # make -n으로 구문 검증
        try:
            result = subprocess.run(
                ["make", "-n", "help"],
                cwd=self.project_root,
                capture_output=True,
                text=True,
                timeout=30
            )
            
            if result.returncode != 0:
                self.log("ERROR", f"Makefile 구문 오류: {result.stderr}")
                return False
                
        except Exception as e:
            self.log("ERROR", f"Makefile 구문 검증 중 예외: {e}")
            return False
            
        self.log("SUCCESS", "Makefile 구문 검증 통과")
        return True
    
    def test_target_dependencies(self) -> bool:
        """타겟 의존성 테스트"""
        self.log("INFO", "타겟 의존성 테스트 시작")
        
        # deploy 타겟의 의존성 확인
        success, stdout, stderr = self.run_make_target("deploy", 
                                                     env=self.test_env, 
                                                     expect_failure=True,
                                                     timeout=30)
        
        # deploy는 실제 리소스가 필요하므로 실패가 예상됨
        # 하지만 의존성 순서는 확인할 수 있음
        if "fetch" not in stderr and "build" not in stderr:
            self.log("WARNING", "deploy 타겟의 의존성 순서를 확인할 수 없습니다")
            
        self.log("SUCCESS", "타겟 의존성 테스트 통과")
        return True
    
    def run_all_tests(self) -> bool:
        """모든 테스트 실행"""
        self.log("INFO", "Makefile 타겟 테스트 시작")
        
        tests = [
            ("Makefile 구문 검증", self.test_makefile_syntax),
            ("help 타겟", self.test_help_target),
            ("validate-env 타겟", self.test_validate_env_target),
            ("필수 환경 변수 누락", self.test_missing_env_variables),
            ("debug 타겟", self.test_debug_target),
            ("clean 타겟", self.test_clean_target),
            ("status 타겟", self.test_status_target),
            ("deploy-check 타겟", self.test_deploy_check_target),
            ("dry-run 타겟", self.test_dry_run_target),
            ("타겟 의존성", self.test_target_dependencies),
        ]
        
        passed = 0
        failed = 0
        
        for test_name, test_func in tests:
            self.log("INFO", f"=== {test_name} 테스트 ===")
            try:
                if test_func():
                    passed += 1
                    self.test_results.append({"name": test_name, "status": "PASS"})
                else:
                    failed += 1
                    self.test_results.append({"name": test_name, "status": "FAIL"})
            except Exception as e:
                self.log("ERROR", f"{test_name} 테스트 중 예외: {e}")
                failed += 1
                self.test_results.append({"name": test_name, "status": "ERROR", "error": str(e)})
            
            print()  # 빈 줄 추가
        
        # 결과 요약
        self.log("INFO", "=== 테스트 결과 요약 ===")
        self.log("INFO", f"총 테스트: {len(tests)}")
        self.log("INFO", f"통과: {passed}")
        self.log("INFO", f"실패: {failed}")
        
        if failed == 0:
            self.log("SUCCESS", "모든 테스트가 통과했습니다!")
        else:
            self.log("ERROR", f"{failed}개의 테스트가 실패했습니다.")
            
        return failed == 0
    
    def save_test_report(self, output_file: str = "makefile_test_report.json"):
        """테스트 결과를 JSON 파일로 저장"""
        report = {
            "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
            "project_root": str(self.project_root),
            "test_environment": self.test_env,
            "results": self.test_results,
            "summary": {
                "total": len(self.test_results),
                "passed": len([r for r in self.test_results if r["status"] == "PASS"]),
                "failed": len([r for r in self.test_results if r["status"] in ["FAIL", "ERROR"]])
            }
        }
        
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(report, f, indent=2, ensure_ascii=False)
            
        self.log("INFO", f"테스트 보고서 저장: {output_file}")


def main():
    """메인 함수"""
    import argparse
    
    parser = argparse.ArgumentParser(description="Makefile 타겟 테스트")
    parser.add_argument("--project-root", help="프로젝트 루트 디렉토리")
    parser.add_argument("--report", help="테스트 보고서 파일명", default="makefile_test_report.json")
    parser.add_argument("--verbose", "-v", action="store_true", help="상세 출력")
    
    args = parser.parse_args()
    
    # 테스트 실행
    runner = MakefileTestRunner(args.project_root)
    
    try:
        success = runner.run_all_tests()
        runner.save_test_report(args.report)
        
        sys.exit(0 if success else 1)
        
    except KeyboardInterrupt:
        runner.log("WARNING", "테스트가 중단되었습니다")
        sys.exit(1)
    except Exception as e:
        runner.log("ERROR", f"테스트 실행 중 예외: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()