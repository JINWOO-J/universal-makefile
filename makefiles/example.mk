# 예제 변수 (필요에 맞게 덮어써도 됨)
DOCKER_BUILDKIT    ?= 1
DOCKERFILE_PATH    ?= Dockerfile
DOCKER_BUILD_OPTION?= --progress=plain
REPO_HUB           ?= mycompany
NAME               ?= nginx-box-test3
VERSION            ?= v1.0.0
TAGNAME            ?= $(VERSION)
BUILD_REVISION     ?= detached--dirty
ENV                ?= development

FULL_TAG           ?= $(REPO_HUB)/$(NAME):$(TAGNAME)

# docker build --build-arg 조립
BUILD_ARGS_CONTENT := \
  --build-arg REPO_HUB='$(REPO_HUB)' \
  --build-arg NAME='$(NAME)' \
  --build-arg VERSION='$(VERSION)' \
  --build-arg TAGNAME='$(TAGNAME)' \
  --build-arg BUILD_REVISION='$(BUILD_REVISION)' \
  --build-arg ENV='$(ENV)'

# -----------------------------
# 데모 타깃들
# -----------------------------

# 1) 정상 빌드 (파이프 모드, 왼쪽 '│' 프리픽스 기대)
demo_build_ok:
	$(call run_pipe, Image Build $(FULL_TAG), \
		DOCKER_BUILDKIT=$(DOCKER_BUILDKIT) docker build \
			$(DOCKER_BUILD_OPTION) \
			$(BUILD_ARGS_CONTENT) \
			-f $(DOCKERFILE_PATH) \
			-t $(FULL_TAG) \
			. \
	)

# 2) 실패 예시 (의도적으로 잘못된 옵션 -tsdsd)
demo_build_error:
	$(call run_pipe, Image Build (error) $(FULL_TAG), \
		DOCKER_BUILDKIT=$(DOCKER_BUILDKIT) docker build \
			$(DOCKER_BUILD_OPTION) \
			$(BUILD_ARGS_CONTENT) \
			-f $(DOCKERFILE_PATH) \
			-tsdsd $(FULL_TAG) \
			. \
	)

# 3) 래퍼 직접 호출 (스크립트만 단독 사용, 모드는 pipe로 강제)
demo_build_direct:
	@TIMED_TASK_NAME="Image Build (direct) $(FULL_TAG)" \
	TIMED_DEBUG="$(DEBUG)" \
	TIMED_MODE="pipe" \
	$(TIMER_SCRIPT) DOCKER_BUILDKIT=$(DOCKER_BUILDKIT) docker build \
		$(DOCKER_BUILD_OPTION) \
		$(BUILD_ARGS_CONTENT) \
		-f $(DOCKERFILE_PATH) \
		-t $(FULL_TAG) \
		.

demo_ls:
	@$(TIMER_SCRIPT) lsxxxx -alsdsdsd

# .PHONY: demo_build_ok demo_build_error demo_build_direct demo_ls
