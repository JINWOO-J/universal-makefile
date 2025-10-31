#!/bin/bash
# GitHub Actions 워크플로우 설치 스크립트
# 사용법: ./scripts/install_workflows.sh

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# 스크립트 디렉토리
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UMF_DIR="$(dirname "$SCRIPT_DIR")"
WORKFLOWS_SOURCE="$UMF_DIR/github/workflows"
WORKFLOWS_TARGET=".github/workflows"

# 워크플로우 메타데이터 (파일명:설명:카테고리)
declare -A WORKFLOW_META
WORKFLOW_META=(
    ["dispatch-deploy.yml"]="중앙화된 배포 러너 (repository_dispatch)|deploy"
    ["build-dev.yml"]="개발 환경 빌드 및 테스트|ci"
    ["ci.yml"]="CI 테스트 및 린트|ci"
    ["release.yml"]="자동 릴리스 생성|release"
    ["docker-build.yml"]="Docker 이미지 빌드 및 푸시|docker"
)

# 선택된 워크플로우 배열
declare -a SELECTED_WORKFLOWS=()

# 현재 선택 인덱스
CURRENT_INDEX=0

# 사용 가능한 워크플로우 목록 가져오기
get_available_workflows() {
    local workflows=()
    if [ -d "$WORKFLOWS_SOURCE" ]; then
        while IFS= read -r file; do
            workflows+=("$(basename "$file")")
        done < <(find "$WORKFLOWS_SOURCE" -maxdepth 1 -name "*.yml" -o -name "*.yaml" | sort)
    fi
    echo "${workflows[@]}"
}

# 워크플로우 설명 가져오기
get_workflow_description() {
    local workflow="$1"
    local meta="${WORKFLOW_META[$workflow]}"
    if [ -n "$meta" ]; then
        echo "$meta" | cut -d'|' -f1
    else
        # 파일에서 name 필드 추출
        local name=$(grep -m1 "^name:" "$WORKFLOWS_SOURCE/$workflow" 2>/dev/null | sed 's/name:[[:space:]]*//')
        echo "${name:-워크플로우}"
    fi
}

# 워크플로우 카테고리 가져오기
get_workflow_category() {
    local workflow="$1"
    local meta="${WORKFLOW_META[$workflow]}"
    if [ -n "$meta" ]; then
        echo "$meta" | cut -d'|' -f2
    else
        echo "other"
    fi
}

# 워크플로우가 이미 설치되어 있는지 확인
is_installed() {
    local workflow="$1"
    [ -f "$WORKFLOWS_TARGET/$workflow" ]
}

# 워크플로우가 선택되어 있는지 확인
is_selected() {
    local workflow="$1"
    for selected in "${SELECTED_WORKFLOWS[@]}"; do
        if [ "$selected" = "$workflow" ]; then
            return 0
        fi
    done
    return 1
}

# 선택 토글
toggle_selection() {
    local workflow="$1"
    if is_selected "$workflow"; then
        # 선택 해제
        SELECTED_WORKFLOWS=("${SELECTED_WORKFLOWS[@]/$workflow}")
    else
        # 선택 추가
        SELECTED_WORKFLOWS+=("$workflow")
    fi
}

# 화면 그리기
draw_screen() {
    clear
    echo -e "${BOLD}${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${BLUE}║${NC}  ${BOLD}GitHub Actions 워크플로우 설치${NC}                              ${BOLD}${BLUE}║${NC}"
    echo -e "${BOLD}${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}📋 사용 가능한 워크플로우:${NC}"
    echo -e "${CYAN}   [Space] 선택/해제  [Enter] 설치  [q] 종료${NC}"
    echo ""
    
    local workflows=($(get_available_workflows))
    local index=0
    
    for workflow in "${workflows[@]}"; do
        local description=$(get_workflow_description "$workflow")
        local category=$(get_workflow_category "$workflow")
        local installed=""
        local selected=""
        local cursor=" "
        
        # 설치 여부
        if is_installed "$workflow"; then
            installed="${GREEN}[설치됨]${NC}"
        else
            installed="${GRAY}[미설치]${NC}"
        fi
        
        # 선택 여부
        if is_selected "$workflow"; then
            selected="${CYAN}[✓]${NC}"
        else
            selected="[ ]"
        fi
        
        # 커서
        if [ $index -eq $CURRENT_INDEX ]; then
            cursor="${YELLOW}▶${NC}"
        fi
        
        # 카테고리 아이콘
        local icon=""
        case "$category" in
            deploy) icon="🚀" ;;
            ci) icon="🔧" ;;
            release) icon="📦" ;;
            docker) icon="🐳" ;;
            *) icon="📄" ;;
        esac
        
        echo -e " $cursor $selected $icon ${BOLD}$workflow${NC}"
        echo -e "     $description $installed"
        echo ""
        
        ((index++))
    done
    
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${MAGENTA}선택된 워크플로우: ${#SELECTED_WORKFLOWS[@]}개${NC}"
}

# 대화형 선택 UI
interactive_select() {
    local workflows=($(get_available_workflows))
    local total=${#workflows[@]}
    
    if [ $total -eq 0 ]; then
        echo -e "${RED}❌ 사용 가능한 워크플로우가 없습니다.${NC}"
        exit 1
    fi
    
    # 터미널 설정 저장
    local old_tty_settings=$(stty -g)
    
    # 화면 그리기
    draw_screen
    
    # 키 입력 처리
    while true; do
        # 한 글자씩 읽기
        read -rsn1 key
        
        case "$key" in
            $'\x1b')  # ESC 시퀀스
                read -rsn2 key  # 나머지 읽기
                case "$key" in
                    '[A')  # 위 화살표
                        if [ $CURRENT_INDEX -gt 0 ]; then
                            ((CURRENT_INDEX--))
                            draw_screen
                        fi
                        ;;
                    '[B')  # 아래 화살표
                        if [ $CURRENT_INDEX -lt $((total - 1)) ]; then
                            ((CURRENT_INDEX++))
                            draw_screen
                        fi
                        ;;
                esac
                ;;
            ' ')  # 스페이스바
                toggle_selection "${workflows[$CURRENT_INDEX]}"
                draw_screen
                ;;
            '')  # 엔터
                break
                ;;
            'q'|'Q')  # 종료
                stty "$old_tty_settings"
                echo ""
                echo -e "${YELLOW}설치를 취소했습니다.${NC}"
                exit 0
                ;;
        esac
    done
    
    # 터미널 설정 복원
    stty "$old_tty_settings"
}

# 워크플로우 설치
install_workflows() {
    if [ ${#SELECTED_WORKFLOWS[@]} -eq 0 ]; then
        echo ""
        echo -e "${YELLOW}⚠️  선택된 워크플로우가 없습니다.${NC}"
        exit 0
    fi
    
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}📦 워크플로우 설치 시작...${NC}"
    echo ""
    
    # 대상 디렉토리 생성
    mkdir -p "$WORKFLOWS_TARGET"
    
    local installed_count=0
    local skipped_count=0
    
    for workflow in "${SELECTED_WORKFLOWS[@]}"; do
        if [ -z "$workflow" ]; then
            continue
        fi
        
        local source="$WORKFLOWS_SOURCE/$workflow"
        local target="$WORKFLOWS_TARGET/$workflow"
        
        if [ ! -f "$source" ]; then
            echo -e "${RED}❌ 소스 파일을 찾을 수 없습니다: $workflow${NC}"
            continue
        fi
        
        if [ -f "$target" ]; then
            echo -e "${YELLOW}⚠️  이미 존재합니다: $workflow${NC}"
            read -p "   덮어쓰시겠습니까? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo -e "${CYAN}   → 건너뜀${NC}"
                ((skipped_count++))
                continue
            fi
        fi
        
        cp "$source" "$target"
        echo -e "${GREEN}✓ 설치 완료: $workflow${NC}"
        ((installed_count++))
    done
    
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}✅ 설치 완료!${NC}"
    echo -e "   설치됨: ${installed_count}개"
    echo -e "   건너뜀: ${skipped_count}개"
    echo ""
    echo -e "${CYAN}💡 다음 단계:${NC}"
    echo -e "   1. GitHub Secrets 및 Variables 설정"
    echo -e "   2. 워크플로우 파일 검토 및 수정"
    echo -e "   3. Git에 커밋 및 푸시"
    echo ""
}

# 메인 실행
main() {
    echo -e "${BOLD}${MAGENTA}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║                                                               ║"
    echo "║   GitHub Actions 워크플로우 설치 마법사                      ║"
    echo "║                                                               ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
    
    # 워크플로우 소스 디렉토리 확인
    if [ ! -d "$WORKFLOWS_SOURCE" ]; then
        echo -e "${RED}❌ 워크플로우 소스 디렉토리를 찾을 수 없습니다: $WORKFLOWS_SOURCE${NC}"
        exit 1
    fi
    
    # 대화형 선택
    interactive_select
    
    # 설치 실행
    install_workflows
}

# 스크립트 실행
main
