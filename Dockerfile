FROM golang:1.9-alpine as builder

COPY . /go/src/github.com/appscode/voyager/
WORKDIR /go/src/github.com/appscode/voyager
RUN apk add --update --no-cache curl
RUN curl -fsSL -o hack/docker/voyager/auth-request.lua https://raw.githubusercontent.com/appscode/haproxy-auth-request/v1.8.12/auth-request.lua

ARG CGO_ENV
ARG CGO
ARG GitTag
ARG CommitHash
ARG CommitTimestamp
ARG VersionStrategy
ARG Version
ARG GitBranch
ARG BuildHost
ARG BuildHostOS
ARG BuildHostArch
ARG BuildTimestamp

RUN set -x && env CGO_ENABLED=0 go build -o dist/voyager/voyager-linux-amd64 ${CGO} -ldflags \
        '-X main.BuildHost='${BuildHost}' \
        -X main.GitTag='${GitTag}' \
        -X main.CommitHash='${CommitHash}' \
        -X main.CommitTimestamp='${CommitTimestamp}' \
        -X main.VersionStrategy='${VersionStrategy}' \
        -X main.Version='${Version}' \
        -X main.GitBranch='${GitBranch}' \
        -X main.BuildHost='${BuildHost}' \
        -X main.BuildHostOS='${BuildHostOS}' \
        -X main.BuildHostArch='${BuildHostArch}' \
        -X main.BuildTimestamp='${BuildTimestamp}' \
        -X main.Os=linux \
        -X main.Arch=amd64' \
        *.go

RUN ./dist/voyager/voyager-linux-amd64 version

FROM haproxy:1.8.12-alpine

RUN set -x \
  && apk add --update --no-cache ca-certificates lua5.3 lua-socket \
  && ln -sf /usr/share/lua/ /usr/local/share/ \
  && ln -sf /usr/lib/lua/ /usr/local/lib/

ARG REPO_ROOT=/go/src/github.com/appscode/voyager

COPY --from=builder $REPO_ROOT/hack/docker/voyager/auth-request.lua /etc/auth-request.lua
COPY --from=builder $REPO_ROOT/hack/docker/voyager/templates /srv/voyager/templates/
COPY --from=builder $REPO_ROOT/dist/voyager/voyager-linux-amd64 /usr/bin/voyager

# https://github.com/appscode/voyager/pull/1038
COPY --from=builder $REPO_ROOT/hack/docker/voyager/test.pem /etc/ssl/private/haproxy/tls/test.pem
COPY --from=builder $REPO_ROOT/hack/docker/voyager/errorfiles /srv/voyager/errorfiles/

ENTRYPOINT ["voyager"]
