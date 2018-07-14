SHELL := /bin/bash
BIN := voyager
haproxy_version ?= 1.8.12
CGO_ENV ?= CGO_ENABLED=0
PKG := github.com/appscode/$(BIN)
DOCKER_REGISTRY ?= tahsin
UID := $(shell id -u $$USER)
GOOS ?= $(shell go env GOOS)
GOARCH ?= $(shell go env GOARCH)
GOARM ?= $(shell go env GOARM)
BUILD_ENV := local
ALL_OS := linux windows darwin arm64 arm7 arm6

# metadata
commit_hash := $(shell git rev-parse --verify HEAD)
git_branch := $(shell git rev-parse --abbrev-ref HEAD)
git_tag := $(shell git describe --exact-match --abbrev=0 2>/dev/null || echo "")
commit_timestamp := $(shell date -d $(git show -s --format=%ci) --utc +%FT-%T)
build_timestamp := $(shell date --utc +%FT-%T)
build_host:= $(shell hostname)
build_host_os:= $(shell go env GOHOSTOS)
build_host_arch:= $(shell go env GOHOSTARCH)
version_strategy := commit_hash
version := $(shell git describe --tags --always --dirty)

# compiler flags
linker_opts := -X main.GitTag=$(git_tag) -X main.CommitHash=$(commit_hash) -X main.CommitTimestamp=$(commit_timestamp) \
	-X main.VersionStrategy=$(version_strategy) -X main.Version=$(version) -X main.GitBranch=$(git_branch) \
	-X main.Os=$(GOOS) -X main.Arch=$(GOARCH)

ifeq ($(CGO_ENV),CGO_ENABLED=1)
	CGO := -a -installsuffix cgo
	linker_opts += -linkmode external -extldflags -static -w
endif

ifdef git_tag
	version := $(git_tag)
	version_strategy := tag
else
	ifneq ($(git_branch),$(or master, HEAD))
		ifeq (,$(findstring release-,$(git_branch)))
			version := $(git_branch)
			version_strategy := branch
			linker_opts += -X main.BuildTimestamp=$(build_timestamp) -X main.BuildHost=$(build_host) \
						   -X main.BuildHostOS=$(build_host_os) -X main.BuildHostArch=$(build_host_arch)
		endif
	endif
endif
ldflags :=-ldflags '$(linker_opts)'

build: build-prerequisite
	GOOS=$(GOOS) GOARCH=$(GOARCH) GOARM=$(GOARM) $(CGO_ENV) go build -o dist/$(BIN)/$(BIN)-$(GOOS)-$(GOARCH)$(ext) $(CGO) $(ldflags) *.go

install:
	go install ./...

build-local: build-prerequisite
	GOOS=$(GOOS) GOARCH=$(GOARCH) GOARM=$(GOARM) $(CGO_ENV) go build -o dist/$(BIN)/$(BIN)-$(GOOS)-$(GOARCH)$(GOARM)$(ext) $(CGO) $(ldflags) *.go

build-docker: build-prerequisite
	docker run --rm -u $(UID) -v /tmp:/.cache -v $$(pwd):/go/src/$(PKG) -w /go/src/$(PKG) \
		-e $(CGO_ENV) golang:1.9-alpine env GOOS=$(GOOS) GOARCH=$(GOARCH) GOARM=$(GOARM) \
		go build -o dist/$(BIN)/$(BIN)-$(GOOS)-$(GOARCH)$(GOARM)$(ext) $(CGO) $(ldflags) *.go

build-local-%:
	@if [ -z $(findstring arm,$*) ]; then\
		echo building $(BIN)-$*-amd64;\
		$(MAKE) --no-print-directory GOOS=$* GOARCH=amd64 build-local;\
	else \
		echo building $(BIN)-linux-$*;\
		if [ $* = arm64 ]; then \
			$(MAKE) --no-print-directory GOOS=linux GOARCH=arm64 build-local;\
		elif [ $* = arm7 ]; then \
			$(MAKE) --no-print-directory GOOS=linux GOARCH=arm GOARM=7 build-local;\
		else \
			$(MAKE) --no-print-directory GOOS=linux GOARCH=arm GOARM=6 build-local;\
		fi;\
	fi

build-docker-%:
	@if [ -z $(findstring arm,$*) ]; then\
		echo building $(BIN)-$*-amd64;\
		$(MAKE) --no-print-directory GOOS=$* GOARCH=amd64 build-docker;\
	else \
		echo building $(BIN)-linux-$*;\
		if [ $* = arm64 ]; then \
			$(MAKE) --no-print-directory GOOS=linux GOARCH=arm64 build-docker;\
		elif [ $* = arm7 ]; then \
			$(MAKE) --no-print-directory GOOS=linux GOARCH=arm GOARM=7 build-docker;\
		else \
			$(MAKE) --no-print-directory GOOS=linux GOARCH=arm GOARM=6 build-docker;\
		fi;\
	fi


build-all-local: $(addprefix build-local-,$(ALL_OS))
build-all-docker: $(addprefix build-docker-,$(ALL_OS))

#docker-%-haproxy: dockerfile_dir=hack/docker/haproxy/$(haproxy_version)-alpine
#docker-%-haproxy: image_name=haproxy
#docker-%-haproxy: image_tag=$(haproxy_version)-$(version)-alpine
#docker-%-voyager: dockerfile_dir=hack/docker/voyager
#docker-%-voyager: image_name=voyager
#docker-%-voyager: image_tag=$(version)

voyager_dockerfile_dir := hack/docker/voyager
voyager_image_tag := $(version)

haproxy_dockerfile_dir := hack/docker/haproxy/$(haproxy_version)-alpine
haproxy_image_tag := $(haproxy_version)-$(version)-alpine

docker-build-%-debug:
	@$(MAKE) --no-print-directory image_name=$* image_tag=$($*_image_tag)-debug \
		dockerfile_dir=$($*_dockerfile_dir) image_type=debug docker_build_image
docker-build-%-prod:
	@$(MAKE) --no-print-directory image_name=$* image_tag=$($*_image_tag) \
		dockerfile_dir=$($*_dockerfile_dir) image_type=prod docker_build_image

docker-build-voyager: docker-build-voyager-debug docker-build-voyager-prod
docker-build-haproxy: docker-build-haproxy-debug docker-build-haproxy-prod
docker-build: docker-build-voyager docker-build-haproxy

docker_build_image: #build-docker-linux
	docker build \
		--build-arg CGO_ENV="$(CGO_ENV)" \
		--build-arg CGO="$(CGO)" \
		--build-arg GitTag="$(git_tag)" \
		--build-arg CommitHash="$(commit_hash)" \
		--build-arg CommitTimestamp="$(commit_timestamp)" \
		--build-arg VersionStrategy="$(version_strategy)" \
		--build-arg Version="$(version)" \
		--build-arg GitBranch="$(git_branch)" \
		--build-arg BuildHost="$(build_host)" \
		--build-arg BuildHostOS="$(build_host_os)" \
		--build-arg BuildHostArch="$(build_host_arch)" \
		--build-arg BuildTimestamp="$(build_timestamp)" \
		-t $(DOCKER_REGISTRY)/$(image_name):$(image_tag) .

#	cp dist/$(BIN)/$(BIN)-linux-amd64 $(dockerfile_dir)/$(BIN); \
#	cd $(dockerfile_dir); \
#	chmod 755 $(BIN); \
#	curl -fsSL -o auth-request.lua https://raw.githubusercontent.com/appscode/haproxy-auth-request/v1.8.12/auth-request.lua; \
#	docker build -t $(DOCKER_REGISTRY)/$(image_name):$(image_tag) -f Dockerfile-$(image_type) .; \
#	rm voyager auth-request.lua;


###docker-build-%: #build-docker-linux
###	cp dist/$(BIN)/$(BIN)-linux-amd64 $(dockerfile_dir)/$(BIN); \
###	cd $(dockerfile_dir); \
###	chmod 755 $(BIN); \
###	curl -fsSL -o auth-request.lua https://raw.githubusercontent.com/appscode/haproxy-auth-request/v1.8.12/auth-request.lua; \
###	docker build -t $(DOCKER_REGISTRY)/$(image_name):$(image_tag) . ; \
###	rm voyager auth-request.lua;
###
###docker-push-%: docker-build-%
###	@if [ "$$APPSCODE_ENV" = "prod" ]; then\
###		echo "Nothing to do in prod env. Are you trying to 'release' binaries to prod?";\
###		exit 1;\
###	fi
###	@if [ "$(version_strategy)" = "git_tag" ]; then\
###		echo "Are you trying to 'release' binaries to prod?";\
###		exit 1;\
###	fi
###
###	docker push $(DOCKER_REGISTRY)/$(image_name):$(image_tag)
###
###	@if [[ "$(version_strategy)" == "commit_hash" && "$(git_branch)" == "master" ]]; then\
###		set -x;\
###		docker tag $(DOCKER_REGISTRY)/$(image_name):$(image_tag) $(DOCKER_REGISTRY)/$(image_name):canary ;\
###		docker push $(DOCKER_REGISTRY)/$(image_name):canary ;\
###	fi
###
###docker-build: docker-build-voyager docker-build-haproxy
###docker-push: docker-push-voyager docker-push-haproxy

#docker-release: docker-build
#	@if [ "$$APPSCODE_ENV" != "prod" ]; then\
#		echo "'release' only works in PROD env.";\
#		exit 1;\
#	fi
#
#	@if [ "$(version_strategy)" != "git_tag" ]; then\
#		echo "'apply_tag' to release binaries and/or docker images.";\
#		exit 1;\
#	fi
#
#	docker push $(DOCKER_REGISTRY):$(BIN):$(version)

#build-all-arm: build-arm64-docker build-arm-docker
#
#build-local-%:
#	@$(MAKE) --no-print-directory GOOS=$* GOARCH=amd64 build-local
#
#build-docker-%:
#	@$(MAKE) --no-print-directory GOOS=$* GOARCH=amd64 build-docker
#
#build-local-arm64:
#	@$(MAKE) --no-print-directory GOOS=linux GOARCH=arm64 build-local
#
#build-local-arm7:
#	@$(MAKE) --no-print-directory GOOS=linux GOARCH=arm GOARM=7 build-local
#
#build-local-arm6:
#	@$(MAKE) --no-print-directory GOOS=linux GOARCH=arm GOARM=6 build-local
#
#build-docker-arm64:
#	@$(MAKE) --no-print-directory GOOS=linux GOARCH=arm64 build-docker
#
#build-docker-arm7:
#	@$(MAKE) --no-print-directory GOOS=linux GOARCH=arm GOARM=7 build-docker
#
#build-docker-arm6:
#	@$(MAKE) --no-print-directory GOOS=linux GOARCH=arm GOARM=6 build-docker
#
#build-arm64-%:
#	@$(MAKE) --no-print-directory GOOS=linux GOARCH=arm64 build-$*
#
#build-arm-%:
#	@$(MAKE) --no-print-directory GOOS=linux GOARCH=arm build-$*

build-prerequisite: gen fmt
	mkdir -p dist/$(BIN)

gen:

fmt:
	gofmt -s -w *.go apis client pkg test third_party
	goimports -w *.go apis client pkg test third_party

build/$(GOOS)/$(GOARCH)/$(GOARM):
	echo "here"

# check if metadata is set correctly
metadata:
	@echo git tag $(git_tag)
	@echo version strategy $(version_strategy)
	@echo version $(version)
	@echo git branch $(git_branch)
