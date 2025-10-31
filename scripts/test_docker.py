#!/usr/bin/env python3
"""
Docker 관련 기능 단위 테스트
"""

import os
import sys
import unittest
import tempfile
import shutil
import json
from unittest.mock import Mock, patch, MagicMock
from datetime import datetime

# 현재 스크립트 디렉토리를 Python 경로에 추가
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from docker_manager import DockerImageManager
from release_manager import ReleaseManager


class TestDockerImageManager(unittest.TestCase):
    """DockerImageManager 테스트"""
    
    def setUp(self):
        """테스트 설정"""
        self.manager = DockerImageManager(registry='test.registry.com', repo_hub='test-hub')
    
    def test_generate_image_tag(self):
        """이미지 태그 생성 테스트"""
        with patch('docker_manager.datetime') as mock_datetime:
            mock_datetime.now.return_value.strftime.return_value = '20250128'
            
            tag = self.manager.generate_image_tag(
                image_name='test-app',
                service_kind='fe',
                version='v1.0.0',
                branch='main',
                commit_sha='abcd1234567890'
            )
            
            expected = 'test.registry.com/test-hub/test-app:fe-v1.0.0-main-20250128-abcd1234'
            self.assertEqual(tag, expected)
    
    def test_clean_branch_name(self):
        """브랜치명 정리 테스트"""
        # 슬래시가 있는 브랜치
        result = self.manager._clean_branch_name('feature/user-auth')
        self.assertEqual(result, 'feature-user-auth')
        
        # 특수문자가 있는 브랜치
        result = self.manager._clean_branch_name('hotfix/bug#123')
        self.assertEqual(result, 'hotfix-bug123')
        
        # 연속된 하이픈
        result = self.manager._clean_branch_name('feature--test')
        self.assertEqual(result, 'feature-test')
        
        # 앞뒤 하이픈
        result = self.manager._clean_branch_name('-feature-')
        self.assertEqual(result, 'feature')
    
    @patch('subprocess.run')
    def test_get_current_git_sha_success(self, mock_run):
        """Git SHA 조회 성공 테스트"""
        mock_run.return_value.returncode = 0
        mock_run.return_value.stdout = 'abcd1234567890abcd1234567890abcd12345678\n'
        
        sha = self.manager._get_current_git_sha()
        self.assertEqual(sha, 'abcd1234567890abcd1234567890abcd12345678')
        
        mock_run.assert_called_once_with(
            ['git', 'rev-parse', 'HEAD'],
            capture_output=True,
            text=True,
            cwd=self.manager.project_root
        )
    
    @patch('subprocess.run')
    def test_get_current_git_sha_failure(self, mock_run):
        """Git SHA 조회 실패 테스트"""
        mock_run.return_value.returncode = 1
        
        sha = self.manager._get_current_git_sha()
        self.assertIsNone(sha)
    
    @patch('subprocess.run')
    def test_build_image_success(self, mock_run):
        """이미지 빌드 성공 테스트"""
        mock_run.return_value.returncode = 0
        mock_run.return_value.stderr = ''
        
        result = self.manager.build_image(
            dockerfile_path='Dockerfile',
            context_path='.',
            image_tag='test:latest'
        )
        
        self.assertTrue(result)
        mock_run.assert_called_once()
        
        # 호출된 명령어 확인
        called_args = mock_run.call_args[0][0]
        self.assertIn('docker', called_args)
        self.assertIn('build', called_args)
        self.assertIn('test:latest', called_args)
    
    @patch('subprocess.run')
    def test_build_image_failure(self, mock_run):
        """이미지 빌드 실패 테스트"""
        mock_run.return_value.returncode = 1
        mock_run.return_value.stderr = 'Build failed'
        
        result = self.manager.build_image(
            dockerfile_path='Dockerfile',
            context_path='.',
            image_tag='test:latest'
        )
        
        self.assertFalse(result)
    
    @patch('subprocess.run')
    def test_build_image_with_build_args(self, mock_run):
        """빌드 인수가 있는 이미지 빌드 테스트"""
        mock_run.return_value.returncode = 0
        
        build_args = {
            'NODE_ENV': 'production',
            'API_URL': 'https://api.example.com'
        }
        
        result = self.manager.build_image(
            dockerfile_path='Dockerfile',
            context_path='.',
            image_tag='test:latest',
            build_args=build_args
        )
        
        self.assertTrue(result)
        
        # 빌드 인수가 명령어에 포함되었는지 확인
        called_args = mock_run.call_args[0][0]
        self.assertIn('--build-arg', called_args)
        self.assertIn('NODE_ENV=production', called_args)
        self.assertIn('API_URL=https://api.example.com', called_args)
    
    @patch('docker_manager.DockerImageManager._get_image_digest')
    @patch('subprocess.run')
    def test_push_image_success(self, mock_run, mock_get_digest):
        """이미지 푸시 성공 테스트"""
        mock_run.return_value.returncode = 0
        mock_get_digest.return_value = 'sha256:abcd1234567890'
        
        digest = self.manager.push_image('test:latest')
        
        self.assertEqual(digest, 'sha256:abcd1234567890')
        mock_run.assert_called_once_with(
            ['docker', 'push', 'test:latest'],
            capture_output=True,
            text=True
        )
    
    @patch('subprocess.run')
    def test_push_image_failure(self, mock_run):
        """이미지 푸시 실패 테스트"""
        mock_run.return_value.returncode = 1
        mock_run.return_value.stderr = 'Push failed'
        
        digest = self.manager.push_image('test:latest')
        
        self.assertIsNone(digest)
    
    @patch('subprocess.run')
    def test_get_image_digest(self, mock_run):
        """이미지 다이제스트 조회 테스트"""
        mock_run.return_value.returncode = 0
        mock_run.return_value.stdout = 'test.registry.com/test-hub/test:latest@sha256:abcd1234567890\n'
        
        digest = self.manager._get_image_digest('test:latest')
        
        self.assertEqual(digest, 'sha256:abcd1234567890')
        mock_run.assert_called_once_with(
            ['docker', 'inspect', '--format={{index .RepoDigests 0}}', 'test:latest'],
            capture_output=True,
            text=True
        )
    
    def test_validate_dockerfile_success(self):
        """Dockerfile 유효성 검사 성공 테스트"""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.dockerfile', delete=False) as f:
            f.write('FROM node:16\nRUN npm install\nCMD ["npm", "start"]')
            dockerfile_path = f.name
        
        try:
            result = self.manager.validate_dockerfile(dockerfile_path)
            self.assertTrue(result)
        finally:
            os.unlink(dockerfile_path)
    
    def test_validate_dockerfile_no_from(self):
        """FROM 명령어가 없는 Dockerfile 테스트"""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.dockerfile', delete=False) as f:
            f.write('RUN npm install\nCMD ["npm", "start"]')
            dockerfile_path = f.name
        
        try:
            result = self.manager.validate_dockerfile(dockerfile_path)
            self.assertFalse(result)
        finally:
            os.unlink(dockerfile_path)
    
    def test_validate_dockerfile_not_exists(self):
        """존재하지 않는 Dockerfile 테스트"""
        result = self.manager.validate_dockerfile('/nonexistent/Dockerfile')
        self.assertFalse(result)


class TestReleaseManager(unittest.TestCase):
    """ReleaseManager 테스트"""
    
    def setUp(self):
        """테스트 설정"""
        self.temp_dir = tempfile.mkdtemp()
        self.manager = ReleaseManager()
        # 테스트용 RELEASES 디렉토리 설정
        self.manager.releases_dir = os.path.join(self.temp_dir, 'RELEASES')
        os.makedirs(self.manager.releases_dir, exist_ok=True)
    
    def tearDown(self):
        """테스트 정리"""
        shutil.rmtree(self.temp_dir)
    
    def test_create_deployment_record(self):
        """배포 기록 생성 테스트"""
        with patch('release_manager.get_current_timestamp') as mock_timestamp:
            mock_timestamp.return_value = '20250128-143000'
            
            deployment_id = self.manager.create_deployment_record(
                source_repo='test/app',
                ref='main',
                version='v1.0.0',
                service_kind='fe',
                environment='prod',
                image_tag='test:latest',
                image_digest='sha256:abcd1234567890'
            )
            
            expected_id = '20250128-143000-fe-prod'
            self.assertEqual(deployment_id, expected_id)
            
            # 파일이 생성되었는지 확인
            record_file = os.path.join(self.manager.releases_dir, f'{expected_id}.json')
            self.assertTrue(os.path.exists(record_file))
            
            # 파일 내용 확인
            with open(record_file, 'r') as f:
                record = json.load(f)
            
            self.assertEqual(record['deployment_id'], expected_id)
            self.assertEqual(record['source_repo'], 'test/app')
            self.assertEqual(record['service_kind'], 'fe')
            self.assertEqual(record['environment'], 'prod')
            self.assertEqual(record['status'], 'in_progress')
    
    def test_update_deployment_status(self):
        """배포 상태 업데이트 테스트"""
        # 먼저 배포 기록 생성
        with patch('release_manager.get_current_timestamp') as mock_timestamp:
            mock_timestamp.return_value = '20250128-143000'
            
            deployment_id = self.manager.create_deployment_record(
                source_repo='test/app',
                ref='main',
                version='v1.0.0',
                service_kind='fe',
                environment='prod',
                image_tag='test:latest',
                image_digest='sha256:abcd1234567890'
            )
        
        # 상태 업데이트
        result = self.manager.update_deployment_status(deployment_id, 'success')
        self.assertTrue(result)
        
        # 업데이트된 내용 확인
        record = self.manager.get_deployment_record(deployment_id)
        self.assertEqual(record['status'], 'success')
    
    def test_get_deployment_record(self):
        """배포 기록 조회 테스트"""
        # 배포 기록 생성
        with patch('release_manager.get_current_timestamp') as mock_timestamp:
            mock_timestamp.return_value = '20250128-143000'
            
            deployment_id = self.manager.create_deployment_record(
                source_repo='test/app',
                ref='main',
                version='v1.0.0',
                service_kind='fe',
                environment='prod',
                image_tag='test:latest',
                image_digest='sha256:abcd1234567890'
            )
        
        # 기록 조회
        record = self.manager.get_deployment_record(deployment_id)
        self.assertIsNotNone(record)
        self.assertEqual(record['deployment_id'], deployment_id)
        
        # 존재하지 않는 기록 조회
        non_existent = self.manager.get_deployment_record('nonexistent-id')
        self.assertIsNone(non_existent)
    
    def test_list_deployments(self):
        """배포 기록 목록 조회 테스트"""
        # 여러 배포 기록 생성
        deployments_data = [
            ('20250128-143000', 'fe', 'prod', 'success'),
            ('20250128-143100', 'be', 'prod', 'success'),
            ('20250128-143200', 'fe', 'staging', 'failed'),
        ]
        
        for timestamp, service_kind, environment, status in deployments_data:
            with patch('release_manager.get_current_timestamp') as mock_timestamp:
                mock_timestamp.return_value = timestamp
                
                deployment_id = self.manager.create_deployment_record(
                    source_repo='test/app',
                    ref='main',
                    version='v1.0.0',
                    service_kind=service_kind,
                    environment=environment,
                    image_tag='test:latest',
                    image_digest='sha256:abcd1234567890'
                )
                
                # 상태 업데이트
                self.manager.update_deployment_status(deployment_id, status)
        
        # 전체 목록 조회
        all_deployments = self.manager.list_deployments()
        self.assertEqual(len(all_deployments), 3)
        
        # 서비스 종류별 필터링
        fe_deployments = self.manager.list_deployments(service_kind='fe')
        self.assertEqual(len(fe_deployments), 2)
        
        # 환경별 필터링
        prod_deployments = self.manager.list_deployments(environment='prod')
        self.assertEqual(len(prod_deployments), 2)
        
        # 상태별 필터링
        success_deployments = self.manager.list_deployments(status='success')
        self.assertEqual(len(success_deployments), 2)
        
        # 제한 개수 적용
        limited_deployments = self.manager.list_deployments(limit=2)
        self.assertEqual(len(limited_deployments), 2)
    
    def test_get_latest_successful_deployment(self):
        """최신 성공 배포 조회 테스트"""
        # 성공한 배포 기록들 생성
        with patch('release_manager.get_current_timestamp') as mock_timestamp:
            # 첫 번째 성공 배포
            mock_timestamp.return_value = '20250128-143000'
            deployment_id1 = self.manager.create_deployment_record(
                source_repo='test/app', ref='main', version='v1.0.0',
                service_kind='fe', environment='prod',
                image_tag='test:v1.0.0', image_digest='sha256:abcd1234567890'
            )
            self.manager.update_deployment_status(deployment_id1, 'success')
            
            # 두 번째 성공 배포 (더 최신)
            mock_timestamp.return_value = '20250128-143100'
            deployment_id2 = self.manager.create_deployment_record(
                source_repo='test/app', ref='main', version='v1.0.1',
                service_kind='fe', environment='prod',
                image_tag='test:v1.0.1', image_digest='sha256:efgh1234567890'
            )
            self.manager.update_deployment_status(deployment_id2, 'success')
        
        # 최신 성공 배포 조회
        latest = self.manager.get_latest_successful_deployment('fe', 'prod')
        self.assertIsNotNone(latest)
        self.assertEqual(latest['deployment_id'], deployment_id2)
        self.assertEqual(latest['version'], 'v1.0.1')
    
    def test_get_rollback_target(self):
        """롤백 대상 조회 테스트"""
        # 성공한 배포들 생성
        with patch('release_manager.get_current_timestamp') as mock_timestamp:
            # 첫 번째 성공 배포
            mock_timestamp.return_value = '20250128-143000'
            deployment_id1 = self.manager.create_deployment_record(
                source_repo='test/app', ref='main', version='v1.0.0',
                service_kind='fe', environment='prod',
                image_tag='test:v1.0.0', image_digest='sha256:abcd1234567890'
            )
            self.manager.update_deployment_status(deployment_id1, 'success')
            
            # 두 번째 성공 배포 (현재 배포)
            mock_timestamp.return_value = '20250128-143100'
            deployment_id2 = self.manager.create_deployment_record(
                source_repo='test/app', ref='main', version='v1.0.1',
                service_kind='fe', environment='prod',
                image_tag='test:v1.0.1', image_digest='sha256:efgh1234567890'
            )
            self.manager.update_deployment_status(deployment_id2, 'success')
        
        # 롤백 대상 조회 (현재 배포 제외)
        rollback_target = self.manager.get_rollback_target('fe', 'prod', deployment_id2)
        self.assertIsNotNone(rollback_target)
        self.assertEqual(rollback_target['deployment_id'], deployment_id1)
        self.assertEqual(rollback_target['version'], 'v1.0.0')
    
    def test_validate_digest(self):
        """다이제스트 검증 테스트"""
        # 유효한 다이제스트
        valid_digest = 'sha256:abcd1234567890abcd1234567890abcd1234567890abcd1234567890abcd1234'
        self.assertTrue(self.manager.validate_digest(valid_digest))
        
        # 잘못된 접두사
        invalid_prefix = 'sha1:abcd1234567890abcd1234567890abcd1234567890abcd1234567890abcd1234'
        self.assertFalse(self.manager.validate_digest(invalid_prefix))
        
        # 잘못된 길이
        invalid_length = 'sha256:abcd1234'
        self.assertFalse(self.manager.validate_digest(invalid_length))
        
        # 잘못된 문자
        invalid_chars = 'sha256:ghij1234567890abcd1234567890abcd1234567890abcd1234567890abcd1234'
        self.assertFalse(self.manager.validate_digest(invalid_chars))
    
    def test_cleanup_old_records(self):
        """오래된 기록 정리 테스트"""
        # 여러 배포 기록 생성
        deployment_ids = []
        for i in range(10):
            with patch('release_manager.get_current_timestamp') as mock_timestamp:
                mock_timestamp.return_value = f'20250128-14{i:02d}00'
                
                deployment_id = self.manager.create_deployment_record(
                    source_repo='test/app',
                    ref='main',
                    version=f'v1.0.{i}',
                    service_kind='fe',
                    environment='prod',
                    image_tag=f'test:v1.0.{i}',
                    image_digest=f'sha256:abcd123456789{i:01d}'
                )
                deployment_ids.append(deployment_id)
        
        # 5개만 유지하도록 정리
        deleted_count = self.manager.cleanup_old_records(keep_count=5)
        self.assertEqual(deleted_count, 5)
        
        # 남은 기록 확인
        remaining_deployments = self.manager.list_deployments()
        self.assertEqual(len(remaining_deployments), 5)


def run_tests():
    """테스트 실행"""
    # 테스트 스위트 생성
    test_suite = unittest.TestSuite()
    
    # 테스트 클래스들 추가
    test_classes = [
        TestDockerImageManager,
        TestReleaseManager
    ]
    
    for test_class in test_classes:
        tests = unittest.TestLoader().loadTestsFromTestCase(test_class)
        test_suite.addTests(tests)
    
    # 테스트 실행
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(test_suite)
    
    return result.wasSuccessful()


if __name__ == "__main__":
    print("Docker 관련 기능 단위 테스트 실행")
    print("=" * 50)
    
    success = run_tests()
    
    if success:
        print("\n✅ 모든 테스트가 성공했습니다!")
        sys.exit(0)
    else:
        print("\n❌ 일부 테스트가 실패했습니다.")
        sys.exit(1)