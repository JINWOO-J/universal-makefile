#!/bin/bash

# ================================================================
# Custom Cleanup Script Template
# 프로젝트별 정리 로직을 여기에 추가하세요
# ================================================================

set -euo pipefail

# 색상 정의
GREEN=$(tput setaf 2 2>/dev/null || echo "")
YELLOW=$(tput setaf 3 2>/dev/null || echo "")
BLUE=$(tput setaf 4 2>/dev/null || echo "")
RESET=$(tput sgr0 2>/dev/null || echo "")

log_info() {
    echo "${BLUE}ℹ️  $1${RESET}"
}

log_success() {
    echo "${GREEN}✅ $1${RESET}"
}

log_warn() {
    echo "${YELLOW}⚠️  $1${RESET}"
}

# ================================================================
# 프로젝트별 커스텀 정리 로직을 여기에 추가
# ================================================================

log_info "Running custom cleanup for your project..."

# 예시: 프로젝트별 임시 파일 정리
# rm -rf custom-temp-dir/
# rm -f *.custom-temp

# 예시: 특정 서비스 정리
# docker stop my-custom-service 2>/dev/null || true
# docker rm my-custom-service 2>/dev/null || true

# 예시: 프로젝트별 로그 정리
# rm -rf logs/old-logs/
# find logs/ -name "*.log" -mtime +7 -delete

# 예시: 데이터베이스 정리 (주의!)
# mysql -u user -p -e "DROP DATABASE temp_db;" 2>/dev/null || true

log_success "Custom cleanup completed"

# ================================================================
# 사용법:
# 1. 이 파일을 프로젝트에 맞게 수정
# 2. chmod +x scripts/custom-clean.sh
# 3. make clean-custom으로 실행
# ================================================================