FROM golang:1.9-alpine as builder

COPY . /go/src/github.com/appscode/voyager/
WORKDIR /go/src/github.com/appscode/voyager
RUN apk add --update --no-cache curl
RUN curl -fsSL -o hack/docker/voyager/auth-request.lua https://raw.githubusercontent.com/appscode/haproxy-auth-request/v1.8.12/auth-request.lua

ARG CGO_ENV
ARG CGO
ARG linker_opts
ARG GOARCH
ARG GOARM

RUN set -x && env GOOS=linux GOARCH=${GOARCH} GOARM=${GOARM} "${CGO_ENV}" \
        go build -o dist/voyager/voyager-linux-${GOARCH}${GOARM} ${CGO} -ldflags "${linker_opts}" *.go

FROM haproxy:1.8.12-alpine

ARG GOARCH
ARG GOARM

RUN set -x \
  && apk add --update --no-cache ca-certificates lua5.3 lua-socket \
  && ln -sf /usr/share/lua/ /usr/local/share/ \
  && ln -sf /usr/lib/lua/ /usr/local/lib/

ARG REPO_ROOT=/go/src/github.com/appscode/voyager

COPY --from=builder $REPO_ROOT/hack/docker/voyager/auth-request.lua /etc/auth-request.lua
COPY --from=builder $REPO_ROOT/hack/docker/voyager/templates /srv/voyager/templates/
COPY --from=builder $REPO_ROOT/dist/voyager/voyager-linux-${GOARCH}${GOARM} /usr/bin/voyager

# https://github.com/appscode/voyager/pull/1038
COPY --from=builder $REPO_ROOT/hack/docker/voyager/test.pem /etc/ssl/private/haproxy/tls/test.pem
COPY --from=builder $REPO_ROOT/hack/docker/voyager/errorfiles /srv/voyager/errorfiles/

ENTRYPOINT ["voyager"]
