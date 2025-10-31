#!/usr/bin/env python3
"""
Makefile 통합 테스트 실행기

모든 Makefile 관련 테스트를 실행하고 통합 보고서를 생성합니다.
"""

import os
import sys
import subprocess
import json
import time
from typing import Dict, List, Any
from pathlib import Path

class MakefileTestSuite:
    """Makefile 테스트 스위트"""
    
    def __init__(self, project_root: str = None):
        self.project_root = Path(project_root or os.getcwd())
        self.scripts_dir = self.project_root / "scripts"
        self.test_results = {}
        self.overall_results = []
        
    def log(self, level: str, message: str):
        """로그 출력"""
        timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
        print(f"[{timestamp}] [{level}] {message}")
        
    def run_test_script(self, script_name: str, report_name: str) -> bool:
        """개별 테스트 스크립트 실행"""
        script_path = self.scripts_dir / script_name
        
        if not script_path.exists():
            self.log("ERROR", f"테스트 스크립트를 찾을 수 없습니다: {script_path}")
            return False
            
        self.log("INFO", f"테스트 스크립트 실행: {script_name}")
        
        try:
            result = subprocess.run(
                [sys.executable, str(script_path), "--report", report_name],
                cwd=self.project_root,
                capture_output=True,
                text=True,
                timeout=300  # 5분 타임아웃
            )
            
            success = result.returncode == 0
            
            if success:
                self.log("SUCCESS", f"{script_name} 테스트 완료")
            else:
                self.log("ERROR", f"{script_name} 테스트 실패")
                self.log("ERROR", f"에러 출력: {result.stderr}")
                
            # 테스트 결과 로드
            report_path = self.project_root / report_name
            if report_path.exists():
                try:
                    with open(report_path, 'r', encoding='utf-8') as f:
                        self.test_results[script_name] = json.load(f)
                except Exception as e:
                    self.log("WARNING", f"테스트 보고서 로드 실패 ({script_name}): {e}")
                    
            return success
            
        except subprocess.TimeoutExpired:
            self.log("ERROR", f"{script_name} 테스트 시간 초과")
            return False
        except Exception as e:
            self.log("ERROR", f"{script_name} 테스트 실행 중 예외: {e}")
            return False
    
    def run_basic_makefile_tests(self) -> bool:
        """기본 Makefile 타겟 테스트"""
        self.log("INFO", "=== 기본 Makefile 타겟 테스트 ===")
        return self.run_test_script("test_makefile.py", "makefile_test_report.json")
    
    def run_env_validation_tests(self) -> bool:
        """환경 변수 검증 테스트"""
        self.log("INFO", "=== 환경 변수 검증 테스트 ===")
        return self.run_test_script("test_env_validation.py", "env_validation_test_report.json")
    
    def run_error_handling_tests(self) -> bool:
        """에러 처리 테스트"""
        self.log("INFO", "=== 에러 처리 테스트 ===")
        return self.run_test_script("test_error_handling.py", "error_handling_test_report.json")
    
    def run_integration_tests(self) -> bool:
        """통합 테스트"""
        self.log("INFO", "=== 통합 테스트 ===")
        
        # 기본 시스템 요구사항 확인
        checks = [
            ("Make 설치 확인", ["make", "--version"]),
            ("Python 설치 확인", [sys.executable, "--version"]),
            ("Git 설치 확인", ["git", "--version"]),
        ]
        
        all_passed = True
        
        for check_name, cmd in checks:
            try:
                result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
                if result.returncode == 0:
                    self.log("SUCCESS", f"{check_name}: {result.stdout.strip()}")
                else:
                    self.log("ERROR", f"{check_name} 실패")
                    all_passed = False
            except Exception as e:
                self.log("ERROR", f"{check_name} 실행 실패: {e}")
                all_passed = False
        
        # Makefile 존재 확인
        makefile_path = self.project_root / "Makefile"
        if makefile_path.exists():
            self.log("SUCCESS", "Makefile 존재 확인")
        else:
            self.log("ERROR", "Makefile이 존재하지 않습니다")
            all_passed = False
            
        # 필수 스크립트 존재 확인
        required_scripts = [
            "docker_manager.py",
            "fetch_secrets.py", 
            "pre_deploy.py",
            "post_deploy.py",
            "rollback.py",
            "release_manager.py",
            "utils.py"
        ]
        
        for script in required_scripts:
            script_path = self.scripts_dir / script
            if script_path.exists():
                self.log("SUCCESS", f"스크립트 존재 확인: {script}")
            else:
                self.log("ERROR", f"필수 스크립트 누락: {script}")
                all_passed = False
        
        return all_passed
    
    def run_all_tests(self) -> bool:
        """모든 테스트 실행"""
        self.log("INFO", "Makefile 통합 테스트 시작")
        start_time = time.time()
        
        test_suites = [
            ("통합 테스트", self.run_integration_tests),
            ("기본 Makefile 타겟 테스트", self.run_basic_makefile_tests),
            ("환경 변수 검증 테스트", self.run_env_validation_tests),
            ("에러 처리 테스트", self.run_error_handling_tests),
        ]
        
        passed_suites = 0
        failed_suites = 0
        
        for suite_name, test_func in test_suites:
            self.log("INFO", f"\n{'='*60}")
            self.log("INFO", f"테스트 스위트: {suite_name}")
            self.log("INFO", f"{'='*60}")
            
            try:
                if test_func():
                    passed_suites += 1
                    self.overall_results.append({"suite": suite_name, "status": "PASS"})
                    self.log("SUCCESS", f"{suite_name} 완료")
                else:
                    failed_suites += 1
                    self.overall_results.append({"suite": suite_name, "status": "FAIL"})
                    self.log("ERROR", f"{suite_name} 실패")
            except Exception as e:
                failed_suites += 1
                self.overall_results.append({"suite": suite_name, "status": "ERROR", "error": str(e)})
                self.log("ERROR", f"{suite_name} 실행 중 예외: {e}")
            
            print()  # 빈 줄 추가
        
        end_time = time.time()
        duration = end_time - start_time
        
        # 최종 결과 요약
        self.log("INFO", f"\n{'='*60}")
        self.log("INFO", "최종 테스트 결과 요약")
        self.log("INFO", f"{'='*60}")
        self.log("INFO", f"총 테스트 스위트: {len(test_suites)}")
        self.log("INFO", f"통과한 스위트: {passed_suites}")
        self.log("INFO", f"실패한 스위트: {failed_suites}")
        self.log("INFO", f"총 소요 시간: {duration:.2f}초")
        
        if failed_suites == 0:
            self.log("SUCCESS", "모든 테스트 스위트가 통과했습니다!")
        else:
            self.log("ERROR", f"{failed_suites}개의 테스트 스위트가 실패했습니다.")
            
        return failed_suites == 0
    
    def generate_comprehensive_report(self, output_file: str = "comprehensive_makefile_test_report.json"):
        """종합 테스트 보고서 생성"""
        self.log("INFO", "종합 테스트 보고서 생성 중...")
        
        # 개별 테스트 결과 통계 계산
        total_tests = 0
        total_passed = 0
        total_failed = 0
        
        for script_name, result_data in self.test_results.items():
            if "summary" in result_data:
                summary = result_data["summary"]
                total_tests += summary.get("total", 0)
                total_passed += summary.get("passed", 0)
                total_failed += summary.get("failed", 0)
        
        comprehensive_report = {
            "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
            "project_root": str(self.project_root),
            "test_suites": self.overall_results,
            "detailed_results": self.test_results,
            "overall_summary": {
                "total_test_suites": len(self.overall_results),
                "passed_suites": len([r for r in self.overall_results if r["status"] == "PASS"]),
                "failed_suites": len([r for r in self.overall_results if r["status"] in ["FAIL", "ERROR"]]),
                "total_individual_tests": total_tests,
                "total_passed_tests": total_passed,
                "total_failed_tests": total_failed
            },
            "recommendations": self.generate_recommendations()
        }
        
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(comprehensive_report, f, indent=2, ensure_ascii=False)
            
        self.log("INFO", f"종합 테스트 보고서 저장: {output_file}")
        
        # 간단한 텍스트 요약도 생성
        summary_file = output_file.replace('.json', '_summary.txt')
        self.generate_text_summary(comprehensive_report, summary_file)
    
    def generate_recommendations(self) -> List[str]:
        """테스트 결과 기반 권장사항 생성"""
        recommendations = []
        
        # 실패한 테스트가 있는 경우
        failed_suites = [r for r in self.overall_results if r["status"] in ["FAIL", "ERROR"]]
        if failed_suites:
            recommendations.append("실패한 테스트 스위트를 검토하고 문제를 해결하세요.")
            
        # 개별 테스트 결과 분석
        for script_name, result_data in self.test_results.items():
            if "results" in result_data:
                failed_tests = [r for r in result_data["results"] if r["status"] in ["FAIL", "ERROR"]]
                if failed_tests:
                    recommendations.append(f"{script_name}에서 {len(failed_tests)}개의 테스트가 실패했습니다.")
        
        # 일반적인 권장사항
        recommendations.extend([
            "정기적으로 테스트를 실행하여 Makefile의 품질을 유지하세요.",
            "새로운 타겟을 추가할 때마다 해당 테스트를 추가하세요.",
            "실제 배포 환경에서도 테스트를 실행해보세요."
        ])
        
        return recommendations
    
    def generate_text_summary(self, report: Dict[str, Any], output_file: str):
        """텍스트 형태의 요약 보고서 생성"""
        with open(output_file, 'w', encoding='utf-8') as f:
            f.write("Makefile 테스트 결과 요약\n")
            f.write("=" * 50 + "\n\n")
            
            f.write(f"테스트 실행 시간: {report['timestamp']}\n")
            f.write(f"프로젝트 루트: {report['project_root']}\n\n")
            
            # 전체 요약
            summary = report['overall_summary']
            f.write("전체 요약:\n")
            f.write(f"  - 테스트 스위트: {summary['total_test_suites']}개\n")
            f.write(f"  - 통과한 스위트: {summary['passed_suites']}개\n")
            f.write(f"  - 실패한 스위트: {summary['failed_suites']}개\n")
            f.write(f"  - 개별 테스트: {summary['total_individual_tests']}개\n")
            f.write(f"  - 통과한 테스트: {summary['total_passed_tests']}개\n")
            f.write(f"  - 실패한 테스트: {summary['total_failed_tests']}개\n\n")
            
            # 스위트별 결과
            f.write("스위트별 결과:\n")
            for suite in report['test_suites']:
                status_icon = "✓" if suite['status'] == "PASS" else "✗"
                f.write(f"  {status_icon} {suite['suite']}: {suite['status']}\n")
            f.write("\n")
            
            # 권장사항
            f.write("권장사항:\n")
            for i, rec in enumerate(report['recommendations'], 1):
                f.write(f"  {i}. {rec}\n")
        
        self.log("INFO", f"텍스트 요약 보고서 저장: {output_file}")


def main():
    """메인 함수"""
    import argparse
    
    parser = argparse.ArgumentParser(description="Makefile 통합 테스트 실행")
    parser.add_argument("--project-root", help="프로젝트 루트 디렉토리")
    parser.add_argument("--report", help="종합 보고서 파일명", 
                       default="comprehensive_makefile_test_report.json")
    parser.add_argument("--quick", action="store_true", 
                       help="빠른 테스트만 실행 (에러 처리 테스트 제외)")
    
    args = parser.parse_args()
    
    # 테스트 스위트 실행
    test_suite = MakefileTestSuite(args.project_root)
    
    try:
        success = test_suite.run_all_tests()
        test_suite.generate_comprehensive_report(args.report)
        
        sys.exit(0 if success else 1)
        
    except KeyboardInterrupt:
        test_suite.log("WARNING", "테스트가 중단되었습니다")
        sys.exit(1)
    except Exception as e:
        test_suite.log("ERROR", f"테스트 실행 중 예외: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()