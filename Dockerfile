# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Marcus Quinn
#
# Warmbly for Cloudron. One container runs the whole self-host stack under
# supervisord: backend API, consumer, worker, tracking, hosted forms, the
# realtime gateway, an embedded NATS JetStream and nginx serving the dashboard
# and admin SPAs. PostgreSQL and Redis come from Cloudron addons.
#
# The Go services, the Rust tracking service and both SPAs are taken from the
# upstream release images, pinned by digest, so the package ships exactly what
# upstream released. Two exceptions are rebuilt from the release commit: the
# backend API, which carries the small patches in patches/, and the realtime
# gateway. The realtime gateway is rebuilt from the same release
# commit on the Cloudron base's Ubuntu release, because upstream's Alpine
# release links its Erlang runtime against musl. No BuildKit-only syntax, so
# Cloudron's on-server build works.

ARG WARMBLY_VERSION=v0.9.5
ARG WARMBLY_COMMIT=20a7bce2c03f06c5d20e250d0c64b4c1df3db3eb

# ── upstream release images (v0.9.5, multi-arch index digests) ──────────────
FROM ghcr.io/warmbly/warmbly/backend:v0.9.5@sha256:d3dfc1f4c9779b190854c705b74757649c2344ee0ccbfbc35290d4d8acc5a92a AS backend
FROM ghcr.io/warmbly/warmbly/consumer:v0.9.5@sha256:4f31f1e071f4ad361b80a3db7aa7a536f8c15fd6a7b8036265e705de48aeda34 AS consumer
FROM ghcr.io/warmbly/warmbly/worker:v0.9.5@sha256:1dfa501381035bf81f09fa0db6b9c1d7e53d60464244d2836425a9ba2b778997 AS worker
FROM ghcr.io/warmbly/warmbly/forms:v0.9.5@sha256:4af05e0570b6974a0ab561e43d8089f02855f2a0f2cb81d1cb2d34aae0ae44e2 AS forms
FROM ghcr.io/warmbly/warmbly/tracking:v0.9.5@sha256:d439150cea572eeb7a5c190e902ea506a6275e472e8c834230c358209c0219ed AS tracking
FROM ghcr.io/warmbly/warmbly/web:v0.9.5@sha256:eb90e811a23b5f43c819c74d9aa901bf4c24893e62322beb0366b733857d54c8 AS web
FROM ghcr.io/warmbly/warmbly/admin:v0.9.5@sha256:51d6395aae1a263e8a3e4329640417d4c00a8f3cc1c984f0171e4d5df338965f AS admin
# Same NATS series as upstream's compose file.
FROM nats:2.10-alpine@sha256:b83efabe3e7def1e0a4a31ec6e078999bb17c80363f881df35edc70fcb6bb927 AS nats

# ── realtime: the Phoenix gateway as a self-contained release (ERTS included) ─
# Built on the same Ubuntu release as cloudron/base:6.0.1 (26.04 "resolute"), so
# the crypto NIF links against the runtime's own libssl.
FROM hexpm/elixir:1.20.4-erlang-29.1.1-ubuntu-resolute-20260927@sha256:27891ab37c7677f921899bc2b9e8e2e47ac0cae17cae28bd5979839ba6b0a479 AS realtime
ARG WARMBLY_COMMIT
RUN apt-get update -y \
    && apt-get install -y --no-install-recommends build-essential ca-certificates git \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /src
RUN git init -q . \
    && git remote add origin https://github.com/warmbly/warmbly.git \
    && git fetch -q --depth 1 origin "${WARMBLY_COMMIT}" \
    && git checkout -q FETCH_HEAD \
    && test "$(git rev-parse HEAD)" = "${WARMBLY_COMMIT}"
ENV MIX_ENV=prod
WORKDIR /src/realtime
RUN mix local.hex --force && mix local.rebar --force \
    && mix deps.get --only prod \
    && mix deps.compile \
    && mix compile \
    && mix release --overwrite \
    && test -x _build/prod/rel/realtime/bin/realtime

# ── backend: the API rebuilt from the same release commit with the package
# patches applied (patches/0001: the first Cloudron OIDC sign-in on an empty
# instance becomes its owner). Same flags as upstream's backend image.
FROM golang:1.26-alpine@sha256:a2012b4a1d1f9f7e9f44e0d39b805a901e856b1dd80b4e6ee4338db547050308 AS backend-patched
ARG WARMBLY_VERSION
ARG WARMBLY_COMMIT
RUN apk add --no-cache ca-certificates git
WORKDIR /src
RUN git init -q . \
    && git remote add origin https://github.com/warmbly/warmbly.git \
    && git fetch -q --depth 1 origin "${WARMBLY_COMMIT}" \
    && git checkout -q FETCH_HEAD \
    && test "$(git rev-parse HEAD)" = "${WARMBLY_COMMIT}" \
    && go mod download
COPY patches/ /patches/
RUN git apply --verbose /patches/*.patch \
    && CGO_ENABLED=0 go build \
        -ldflags="-s -w -X github.com/warmbly/warmbly/internal/version.Version=${WARMBLY_VERSION} -X github.com/warmbly/warmbly/internal/version.Commit=${WARMBLY_COMMIT}" \
        -o /out/backend ./cmd/backend

# ── runtime ─────────────────────────────────────────────────────────────────
FROM cloudron/base:6.0.1@sha256:7b1e729960c3ca312d26e886917ba89483241bba0219ff292858e10d9d5768ee
ARG WARMBLY_VERSION
ARG WARMBLY_COMMIT
LABEL org.opencontainers.image.source="https://github.com/marcusquinn/cloudron-warmbly-app"

# musl: the tracking binary is upstream's musl build and needs only its loader.
# postgresql-client: `warmblyctl backup` and `restore` shell out to pg_dump/psql.
# libncurses6, libsctp1: the Erlang runtime in the realtime release.
RUN apt-get update \
    && apt-get install -y --no-install-recommends libncurses6 libsctp1 musl nginx openssl postgresql-client supervisor \
    && rm -rf /var/lib/apt/lists/* /etc/nginx/sites-enabled/default

ENV LANG=C.UTF-8 LC_ALL=C.UTF-8 \
    PATH=/app/code/bin:$PATH

WORKDIR /app/code
COPY --from=backend-patched /out/backend /app/code/services/backend
COPY --from=backend /usr/local/bin/warmblyctl /app/code/services/warmblyctl
COPY --from=consumer /app/consumer /app/code/services/consumer
COPY --from=worker /app/worker /app/code/services/worker
COPY --from=forms /app/forms /app/code/services/forms
COPY --from=forms /app/static/ /app/code/forms-static/
COPY --from=tracking /app/tracking /app/code/services/tracking
COPY --from=nats /usr/local/bin/nats-server /app/code/services/nats-server
COPY --from=realtime /src/realtime/_build/prod/rel/realtime/ /app/code/realtime/

# The SPAs and the upstream scripts that render their runtime config and CSP.
COPY --from=web /usr/share/nginx/html/ /app/code/web/
COPY --from=web /docker-entrypoint.d/40-warmbly-config.sh /app/code/upstream/web-config.sh
COPY --from=web /etc/nginx/warmbly-security-headers.conf /app/code/upstream/web-security-headers.conf
COPY --from=web /etc/nginx/warmbly-mail-preview-headers.conf /app/code/upstream/web-mail-preview-headers.conf
COPY --from=admin /usr/share/nginx/html/ /app/code/admin/
COPY --from=admin /docker-entrypoint.d/40-warmbly-config.sh /app/code/upstream/admin-config.sh
COPY --from=admin /etc/nginx/warmbly-security-headers.conf /app/code/upstream/admin-security-headers.conf

COPY start.sh nginx.conf.template nats.conf supervisord.conf env.template /app/code/
COPY bin/ /app/code/bin/
COPY web-extra/ /app/code/web-extra/
# The SPAs read /config.js; the real one is rendered into /run at start.
RUN rm -f /app/code/web/config.js /app/code/admin/config.js \
    && chmod -R a+rX /app/code/web /app/code/admin /app/code/forms-static /app/code/web-extra \
    && chmod 0755 /app/code/start.sh /app/code/bin/* /app/code/services/* /app/code/upstream/*.sh \
    && /app/code/services/nats-server --version \
    && printf '%s\n' "${WARMBLY_VERSION}" > /app/code/upstream-version \
    && printf '%s\n' "${WARMBLY_COMMIT}" > /app/code/upstream-commit

EXPOSE 8000 8001 8002 8003 8004
CMD ["/app/code/start.sh"]
