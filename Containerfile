ARG BASE_IMAGE
FROM --platform=$BUILDPLATFORM ${BASE_IMAGE} AS download

ARG APP_VERSION
ARG TARGETARCH
ARG UPSTREAM_PRERELEASE
ARG UPSTREAM_URL_AMD64
ARG UPSTREAM_SHA256_AMD64
ARG UPSTREAM_URL_ARM64
ARG UPSTREAM_SHA256_ARM64

RUN set -eux; \
    : "${APP_VERSION:?APP_VERSION must be set}"; \
    apk add --no-cache ca-certificates curl; \
    case "$UPSTREAM_PRERELEASE" in \
        true) branch=develop ;; false) branch=master ;; \
        *) echo "UPSTREAM_PRERELEASE must be true or false" >&2; exit 1 ;; \
    esac; \
    case "$TARGETARCH" in \
        amd64) download_url="$UPSTREAM_URL_AMD64"; checksum="$UPSTREAM_SHA256_AMD64" ;; \
        arm64) download_url="$UPSTREAM_URL_ARM64"; checksum="$UPSTREAM_SHA256_ARM64" ;; \
        *) echo "Unsupported architecture: $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    : "${download_url:?upstream asset URL must be set}" "${checksum:?upstream SHA-256 must be set}"; \
    curl --fail --location --retry 3 --proto '=https' --proto-redir '=https' \
        "$download_url" --output /tmp/radarr.tar.gz; \
    printf '%s  /tmp/radarr.tar.gz\n' "$checksum" | sha256sum -c -; \
    mkdir /radarr /notices; \
    tar -xzf /tmp/radarr.tar.gz --directory /radarr --strip-components=1; \
    test -s /radarr/LICENSE; \
    printf 'Radarr is distributed under GPL-3.0. See /opt/radarr/LICENSE.\nUpstream release: https://github.com/Radarr/Radarr/releases/tag/v%s\nCorresponding source: https://github.com/Radarr/Radarr/tree/v%s\nSource archive: https://github.com/Radarr/Radarr/archive/refs/tags/v%s.tar.gz\n' \
        "$APP_VERSION" "$APP_VERSION" "$APP_VERSION" > /notices/SOURCE; \
    rm -rf /radarr/Radarr.Update; \
    printf 'UpdateMethod=docker\nBranch=%s\nPackageAuthor=[Tuxcrate](https://tuxcrate.com)\n' "$branch" > /package_info

FROM ${BASE_IMAGE}

ARG APP_VERSION

ENV HOME=/config \
    XDG_CONFIG_HOME=/config/xdg \
    COMPlus_EnableDiagnostics=0

RUN set -eux; \
    apk upgrade --no-cache; \
    apk add --no-cache ca-certificates icu-data-full icu-libs libgcc libstdc++ libssl3 sqlite-libs tzdata zlib; \
    addgroup -g 1000 radarr; \
    adduser -D -u 1000 -G radarr -h /config -s /sbin/nologin radarr; \
    mkdir -p /config /data; \
    chown 1000:1000 /config /data

COPY --from=download /radarr /opt/radarr
COPY --from=download /package_info /opt/package_info
COPY --from=download /notices /usr/share/doc/radarr
COPY tests/smoke.sh /usr/local/bin/radarr-smoke-test

USER 1000:1000
WORKDIR /config

RUN sh /usr/local/bin/radarr-smoke-test "${APP_VERSION}"

EXPOSE 7878
ENTRYPOINT ["/opt/radarr/Radarr", "-nobrowser", "-data=/config"]
