FROM --platform=$BUILDPLATFORM alpine:3.24.3 AS fetch

# the architecture of the image (amd64, arm64): the client of ffmpeg-over-ip is the one of the release for it
ARG TARGETARCH

# The SSO plugin is archived: the last release is pinned and checked by the checksum of
# https://raw.githubusercontent.com/9p4/jellyfin-plugin-sso/manifest-release/manifest.json
ARG SSO_PLUGIN_VERSION=4.0.0.4
ARG SSO_PLUGIN_MD5=1e7908585ebee256203a0869dcdfbaf8
# renovate: datasource=github-releases depName=steelbrain/ffmpeg-over-ip
ARG FFMPEG_OVER_IP_VERSION=v5.2.1

RUN set -eux; \
    wget -q -O /tmp/plugin.zip "https://github.com/9p4/jellyfin-plugin-sso/releases/download/v${SSO_PLUGIN_VERSION}/sso-authentication_${SSO_PLUGIN_VERSION}.zip"; \
    echo "${SSO_PLUGIN_MD5}  /tmp/plugin.zip" | md5sum -c -; \
    unzip -q /tmp/plugin.zip -d /sso-plugin; \
    wget -q -O /tmp/client.zip "https://github.com/steelbrain/ffmpeg-over-ip/releases/download/${FFMPEG_OVER_IP_VERSION}/linux-${TARGETARCH}-ffmpeg-over-ip-client.zip"; \
    unzip -q /tmp/client.zip -d /client; \
    chmod +x /client/ffmpeg-over-ip-client

FROM ghcr.io/jellyfin/jellyfin:12.4

ARG SSO_PLUGIN_VERSION=4.0.0.4
ENV SSO_PLUGIN_VERSION=${SSO_PLUGIN_VERSION}

# Hardware transcoding is done on the nodes of the GPU by the server of ffmpeg-over-ip (FFMPEG_OVER_IP_CLIENT_ADDRESS and
# FFMPEG_OVER_IP_CLIENT_AUTH_SECRET): the client takes the place of ffmpeg and ffprobe, which jellyfin runs.
COPY --from=fetch /client/ffmpeg-over-ip-client /usr/lib/jellyfin-ffmpeg/ffmpeg
COPY --from=fetch /client/ffmpeg-over-ip-client /usr/lib/jellyfin-ffmpeg/ffprobe

# The SSO plugin has to be in the volume `/config` (jellyfin loads the plugins from it at its start): `jellyfin-init` copies it there.
COPY --from=fetch /sso-plugin /opt/jellyfin-plugin-sso
COPY --chmod=755 jellyfin-init /usr/local/bin/jellyfin-init
