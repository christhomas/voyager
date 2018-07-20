# make build-local //build for local go env configs
# make build-local GOOS= GOARCH= GOARM= //override default values
# make build-docker //build inside docker, for local go env configs
# make build-docker GOOS= GOARCH= GOARM= //build inside docker, override local configs
# make build-local-all //build locally for all platform
# make build-docker-all //build inside docker, for all platform
# make docker-build //build docker image for local go env configs
# make docker-build GOOS= GOARCH= GOARM= IMAGE_NAME=(voyager if unspecified) IMAGE_TYPE=(debug if unspecified)
# make docker-build-all
# make docker-push
# make docker-push GOOS= GOARCH= GOARM=
# make docker-push-all
# make docker-release
# make docker-release GOOS= GOARCH= GOARM=
# make docker-release-all

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

IMAGE_NAME ?= $(BIN)
IMAGE_TYPE ?= debug

platforms := linux/amd64 linux/arm64 linux/arm/7 linux/arm/6 windows/amd64 darwin/amd64
docker_image_names := voyager haproxy

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
	@cowsay -f tux building binary $(BIN)-$(GOOS)-$(GOARCH)$(GOARM)
	GOOS=$(GOOS) GOARCH=$(GOARCH) GOARM=$(GOARM) $(CGO_ENV) \
		 go build -o dist/$(BIN)/$(BIN)-$(GOOS)-$(GOARCH)$(GOARM) $(CGO) $(ldflags) *.go

build-docker: build-prerequisite
	@cowsay -f tux building binary $(BIN)-$(GOOS)-$(GOARCH)$(GOARM) inside docker
	docker run --rm -u $(UID) -v /tmp:/.cache -v $$(pwd):/go/src/$(PKG) -w /go/src/$(PKG) \
		-e $(CGO_ENV) golang:1.9-alpine env GOOS=$(GOOS) GOARCH=$(GOARCH) GOARM=$(GOARM) \
		go build -o dist/$(BIN)/$(BIN)-$(GOOS)-$(GOARCH)$(GOARM)$(ext) $(CGO) $(ldflags) *.go

build-%-all:
	@for platform in $(platforms); do \
		IFS='/' read -r -a array <<< $$platform; \
		GOOS=$${array[0]}; GOARCH=$${array[1]}; GOARM=$${array[2]}; \
		$(MAKE) --no-print-directory GOOS=$$GOOS GOARCH=$$GOARCH GOARM=$$GOARM build-$*; \
	done

haproxy_dockerfile_dir=hack/docker/haproxy/$(haproxy_version)-alpine
haproxy_image_tag=$(haproxy_version)-$(version)-alpine
voyager_dockerfile_dir=hack/docker/voyager
voyager_image_tag=$(version)

docker-build:
	@cowsay -f tux building $(DOCKER_REGISTRY)/$(IMAGE_NAME):$($(IMAGE_NAME)_image_tag)-$(GOOS)-$(GOARCH)$(GOARM)-$(IMAGE_TYPE)
	cp $($(IMAGE_NAME)_dockerfile_dir)/Dockerfile Dockerfile.tmp
	if [ $(IMAGE_TYPE) = debug ]; then \
		echo 'USER nobody:nobody' >> Dockerfile.tmp; \
	else \
		echo 'USER root:root' >> hack/docker/$(IMAGE_NAME)/Dockerfile.tmp; \
	fi

	docker build \
		--build-arg CGO_ENV="$(CGO_ENV)" \
		--build-arg CGO="$(CGO)" \
		--build-arg linker_opts="$(linker_opts)" \
		--build-arg GOARCH="$(GOARCH)" \
		--build-arg GOARM="$(GOARM)" \
		-t $(DOCKER_REGISTRY)/$(IMAGE_NAME):$($(IMAGE_NAME)_image_tag)-$(GOOS)-$(GOARCH)$(GOARM)-$(IMAGE_TYPE) -f Dockerfile.tmp .

	@+rm Dockerfile.tmp

docker-push: docker-build
	@cowsay -f tux pushing $(DOCKER_REGISTRY)/$(IMAGE_NAME):$($(IMAGE_NAME)_image_tag)-$(GOOS)-$(GOARCH)$(GOARM)-$(IMAGE_TYPE)
	@if [ "$$APPSCODE_ENV" = "prod" ]; then\
		echo "Nothing to do in prod env. Are you trying to 'release' binaries to prod?";\
		exit 1;\
	fi
	@if [ "$(version_strategy)" = "git_tag" ]; then\
		echo "Are you trying to 'release' binaries to prod?";\
		exit 1;\
	fi

	docker push $(DOCKER_REGISTRY)/$(IMAGE_NAME):$($(IMAGE_NAME)_image_tag)-$(GOOS)-$(GOARCH)$(GOARM)-$(IMAGE_TYPE)

	@if [[ "$(version_strategy)" == "commit_hash" && "$(git_branch)" == "master" ]]; then\
		set -x;\
		docker tag $(DOCKER_REGISTRY)/$(image_name):$(image_tag) $(DOCKER_REGISTRY)/$(image_name):canary ;\
		docker push $(DOCKER_REGISTRY)/$(image_name):canary ;\
	fi

docker-release: docker-build
	@if [ "$$APPSCODE_ENV" != "prod" ]; then\
		echo "'release' only works in PROD env.";\
		exit 1;\
	fi

	@if [ "$(version_strategy)" != "git_tag" ]; then\
		echo "'apply_tag' to release binaries and/or docker images.";\
		exit 1;\
	fi

	docker push $(DOCKER_REGISTRY)/$(IMAGE_NAME):$($(IMAGE_NAME)_image_tag)-$(GOOS)-$(GOARCH)$(GOARM)-$(IMAGE_TYPE)

docker-%-all:
	@for platform in $(platforms); do \
		IFS='/' read -r -a array <<< $$platform; \
		GOOS=$${array[0]}; GOARCH=$${array[1]}; GOARM=$${array[2]}; \
		for image_name in $(docker_image_names); do \
			for image_type in debug prod; do \
				$(MAKE) --no-print-directory \
				GOOS=$$GOOS GOARCH=$$GOARCH GOARM=$$GOARM IMAGE_NAME=$$image_name IMAGE_TYPE=$$image_type docker-$*; \
			done; \
		done; \
	done


build-prerequisite: gen fmt
	mkdir -p dist/$(BIN)

gen:

fmt:
	gofmt -s -w *.go apis client pkg test third_party
	goimports -w *.go apis client pkg test third_party

# check if metadata is set correctly
metadata:
	@echo git tag $(git_tag)
	@echo version strategy $(version_strategy)
	@echo version $(version)
	@echo git branch $(git_branch)
