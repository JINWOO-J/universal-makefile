#!/usr/bin/env python3
"""
SSM 연동 기능 단위 테스트
"""

import os
import sys
import unittest
import tempfile
import shutil
from unittest.mock import Mock, patch, MagicMock
from typing import Dict

# 현재 스크립트 디렉토리를 Python 경로에 추가
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from utils import SSMClient, Logger, load_env_file
from fetch_secrets import SecretsFetcher


class TestSSMClient(unittest.TestCase):
    """SSMClient 테스트"""
    
    def setUp(self):
        """테스트 설정"""
        self.mock_client = Mock()
        
    @patch('boto3.client')
    def test_ssm_client_initialization(self, mock_boto_client):
        """SSM 클라이언트 초기화 테스트"""
        mock_boto_client.return_value = self.mock_client
        
        ssm_client = SSMClient(region='us-east-1')
        
        mock_boto_client.assert_called_once_with('ssm', region_name='us-east-1')
        self.assertIsNotNone(ssm_client.client)
    
    @patch('boto3.client')
    def test_get_parameter_success(self, mock_boto_client):
        """단일 파라미터 조회 성공 테스트"""
        mock_boto_client.return_value = self.mock_client
        self.mock_client.get_parameter.return_value = {
            'Parameter': {
                'Value': 'test_value'
            }
        }
        
        ssm_client = SSMClient()
        result = ssm_client.get_parameter('/app/test/TEST_KEY')
        
        self.assertEqual(result, 'test_value')
        self.mock_client.get_parameter.assert_called_once_with(
            Name='/app/test/TEST_KEY',
            WithDecryption=True
        )
    
    @patch('boto3.client')
    def test_get_parameter_not_found(self, mock_boto_client):
        """파라미터 없음 테스트"""
        from botocore.exceptions import ClientError
        
        mock_boto_client.return_value = self.mock_client
        self.mock_client.get_parameter.side_effect = ClientError(
            {'Error': {'Code': 'ParameterNotFound'}},
            'GetParameter'
        )
        
        ssm_client = SSMClient()
        result = ssm_client.get_parameter('/app/test/NONEXISTENT_KEY')
        
        self.assertIsNone(result)
    
    @patch('boto3.client')
    def test_get_parameters_by_path(self, mock_boto_client):
        """경로별 파라미터 조회 테스트"""
        mock_boto_client.return_value = self.mock_client
        self.mock_client.get_parameters_by_path.return_value = {
            'Parameters': [
                {'Name': '/app/test/DB_PASSWORD', 'Value': 'secret123'},
                {'Name': '/app/test/API_KEY', 'Value': 'key456'},
            ]
        }
        
        ssm_client = SSMClient()
        result = ssm_client.get_parameters_by_path('/app/test')
        
        expected = {
            'DB_PASSWORD': 'secret123',
            'API_KEY': 'key456'
        }
        self.assertEqual(result, expected)
    
    @patch('boto3.client')
    def test_get_environment_secrets(self, mock_boto_client):
        """환경별 비밀 조회 테스트"""
        mock_boto_client.return_value = self.mock_client
        self.mock_client.get_parameters_by_path.return_value = {
            'Parameters': [
                {'Name': '/app/prod/DB_PASSWORD', 'Value': 'prod_secret'},
                {'Name': '/app/prod/SLACK_WEBHOOK', 'Value': 'prod_webhook'},
            ]
        }
        
        ssm_client = SSMClient()
        result = ssm_client.get_environment_secrets('prod')
        
        expected = {
            'DB_PASSWORD': 'prod_secret',
            'SLACK_WEBHOOK': 'prod_webhook'
        }
        self.assertEqual(result, expected)


class TestLoadEnvFile(unittest.TestCase):
    """환경 파일 로드 테스트"""
    
    def setUp(self):
        """테스트 설정"""
        self.temp_dir = tempfile.mkdtemp()
    
    def tearDown(self):
        """테스트 정리"""
        shutil.rmtree(self.temp_dir)
    
    def test_load_env_file_success(self):
        """환경 파일 로드 성공 테스트"""
        env_content = """
# 테스트 환경 파일
NODE_ENV=test
API_URL=https://api.test.com
DEBUG=true
EMPTY_VALUE=
        """.strip()
        
        env_file_path = os.path.join(self.temp_dir, '.env.test')
        with open(env_file_path, 'w') as f:
            f.write(env_content)
        
        result = load_env_file(env_file_path)
        
        expected = {
            'NODE_ENV': 'test',
            'API_URL': 'https://api.test.com',
            'DEBUG': 'true',
            'EMPTY_VALUE': ''
        }
        self.assertEqual(result, expected)
    
    def test_load_env_file_not_exists(self):
        """존재하지 않는 파일 테스트"""
        result = load_env_file('/nonexistent/path/.env')
        self.assertEqual(result, {})
    
    def test_load_env_file_with_quotes(self):
        """따옴표가 있는 값 테스트"""
        env_content = '''
QUOTED_SINGLE='single quoted value'
QUOTED_DOUBLE="double quoted value"
MIXED_QUOTES="value with 'inner' quotes"
        '''.strip()
        
        env_file_path = os.path.join(self.temp_dir, '.env.quotes')
        with open(env_file_path, 'w') as f:
            f.write(env_content)
        
        result = load_env_file(env_file_path)
        
        expected = {
            'QUOTED_SINGLE': 'single quoted value',
            'QUOTED_DOUBLE': 'double quoted value',
            'MIXED_QUOTES': "value with 'inner' quotes"
        }
        self.assertEqual(result, expected)


class TestSecretsFetcher(unittest.TestCase):
    """SecretsFetcher 테스트"""
    
    def setUp(self):
        """테스트 설정"""
        self.temp_dir = tempfile.mkdtemp()
        self.original_cwd = os.getcwd()
        
        # 임시 프로젝트 구조 생성
        os.makedirs(os.path.join(self.temp_dir, 'config', 'test'))
        os.makedirs(os.path.join(self.temp_dir, 'scripts'))
        
        # 기본 .env 파일 생성
        base_env_content = """
COMPOSE_PROJECT_NAME=app
DOCKER_REGISTRY=docker.io/test
        """.strip()
        
        with open(os.path.join(self.temp_dir, '.env'), 'w') as f:
            f.write(base_env_content)
        
        # 환경별 공개 구성 파일 생성
        env_config_content = """
NODE_ENV=test
API_URL=https://api.test.com
LOG_LEVEL=debug
        """.strip()
        
        with open(os.path.join(self.temp_dir, 'config', 'test', 'app.env.public'), 'w') as f:
            f.write(env_config_content)
    
    def tearDown(self):
        """테스트 정리"""
        os.chdir(self.original_cwd)
        shutil.rmtree(self.temp_dir)
    
    @patch('fetch_secrets.SSMClient')
    def test_secrets_fetcher_initialization(self, mock_ssm_client_class):
        """SecretsFetcher 초기화 테스트"""
        mock_ssm_client = Mock()
        mock_ssm_client_class.return_value = mock_ssm_client
        
        # 임시 디렉토리로 이동
        os.chdir(self.temp_dir)
        
        fetcher = SecretsFetcher('test')
        
        self.assertEqual(fetcher.environment, 'test')
        self.assertIsNotNone(fetcher.ssm_client)
        mock_ssm_client_class.assert_called_once()
    
    @patch('fetch_secrets.SSMClient')
    def test_load_public_config(self, mock_ssm_client_class):
        """공개 구성 로드 테스트"""
        mock_ssm_client = Mock()
        mock_ssm_client_class.return_value = mock_ssm_client
        
        # 임시 디렉토리로 이동하고 프로젝트 루트 설정
        os.chdir(self.temp_dir)
        
        fetcher = SecretsFetcher('test')
        # 프로젝트 루트를 임시 디렉토리로 강제 설정
        fetcher.project_root = self.temp_dir
        
        config = fetcher.load_public_config()
        
        expected = {
            'COMPOSE_PROJECT_NAME': 'app',
            'DOCKER_REGISTRY': 'docker.io/test',
            'NODE_ENV': 'test',
            'API_URL': 'https://api.test.com',
            'LOG_LEVEL': 'debug'
        }
        self.assertEqual(config, expected)
    
    @patch('fetch_secrets.SSMClient')
    def test_merge_configs(self, mock_ssm_client_class):
        """구성 병합 테스트"""
        mock_ssm_client = Mock()
        mock_ssm_client_class.return_value = mock_ssm_client
        
        fetcher = SecretsFetcher('test')
        
        public_config = {
            'NODE_ENV': 'test',
            'API_URL': 'https://api.test.com',
            'DEBUG': 'false'
        }
        
        ssm_secrets = {
            'DB_PASSWORD': 'secret123',
            'API_KEY': 'key456',
            'DEBUG': 'true'  # 이 값이 public_config의 DEBUG를 덮어씀
        }
        
        merged = fetcher.merge_configs(public_config, ssm_secrets)
        
        expected = {
            'NODE_ENV': 'test',
            'API_URL': 'https://api.test.com',
            'DEBUG': 'true',  # SSM 값으로 덮어써짐
            'DB_PASSWORD': 'secret123',
            'API_KEY': 'key456'
        }
        self.assertEqual(merged, expected)
    
    @patch('fetch_secrets.SSMClient')
    def test_write_env_runtime(self, mock_ssm_client_class):
        """환경 파일 쓰기 테스트"""
        mock_ssm_client = Mock()
        mock_ssm_client_class.return_value = mock_ssm_client
        
        # 임시 디렉토리로 이동
        os.chdir(self.temp_dir)
        
        fetcher = SecretsFetcher('test')
        # 프로젝트 루트를 임시 디렉토리로 강제 설정
        fetcher.project_root = self.temp_dir
        
        config = {
            'NODE_ENV': 'test',
            'DB_PASSWORD': 'secret123',
            'API_URL': 'https://api.test.com'
        }
        
        output_path = fetcher.write_env_runtime(config)
        
        # 파일이 생성되었는지 확인
        self.assertTrue(os.path.exists(output_path))
        
        # 파일 권한 확인 (600)
        file_stat = os.stat(output_path)
        file_permissions = oct(file_stat.st_mode)[-3:]
        self.assertEqual(file_permissions, '600')
        
        # 파일 내용 확인
        with open(output_path, 'r') as f:
            content = f.read()
        
        self.assertIn('NODE_ENV=test', content)
        self.assertIn('DB_PASSWORD=secret123', content)
        self.assertIn('API_URL=https://api.test.com', content)
        self.assertIn('# Runtime Environment Variables', content)
    
    @patch('fetch_secrets.SSMClient')
    def test_validate_required_secrets(self, mock_ssm_client_class):
        """필수 비밀 검증 테스트"""
        mock_ssm_client = Mock()
        mock_ssm_client_class.return_value = mock_ssm_client
        
        fetcher = SecretsFetcher('test')
        
        # 필수 비밀이 모두 있는 경우
        config_with_secrets = {
            'NODE_ENV': 'test',
            'SLACK_WEBHOOK_URL': 'https://hooks.slack.com/test',
            'DB_PASSWORD': 'secret123'
        }
        
        result = fetcher.validate_required_secrets(config_with_secrets)
        self.assertTrue(result)
        
        # 필수 비밀이 누락된 경우
        config_without_secrets = {
            'NODE_ENV': 'test',
            'DB_PASSWORD': 'secret123'
        }
        
        result = fetcher.validate_required_secrets(config_without_secrets)
        self.assertFalse(result)
        
        # 커스텀 필수 비밀 목록 테스트
        custom_required = ['DB_PASSWORD', 'API_KEY']
        
        config_custom = {
            'NODE_ENV': 'test',
            'DB_PASSWORD': 'secret123',
            'API_KEY': 'key456'
        }
        
        result = fetcher.validate_required_secrets(config_custom, custom_required)
        self.assertTrue(result)


def run_tests():
    """테스트 실행"""
    # 테스트 스위트 생성
    test_suite = unittest.TestSuite()
    
    # 테스트 클래스들 추가
    test_classes = [
        TestSSMClient,
        TestLoadEnvFile,
        TestSecretsFetcher
    ]
    
    for test_class in test_classes:
        tests = unittest.TestLoader().loadTestsFromTestCase(test_class)
        test_suite.addTests(tests)
    
    # 테스트 실행
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(test_suite)
    
    return result.wasSuccessful()


if __name__ == "__main__":
    print("SSM 연동 단위 테스트 실행")
    print("=" * 50)
    
    success = run_tests()
    
    if success:
        print("\n✅ 모든 테스트가 성공했습니다!")
        sys.exit(0)
    else:
        print("\n❌ 일부 테스트가 실패했습니다.")
        sys.exit(1)