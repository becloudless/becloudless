FROM ubuntu:26.04

# the architecture of the image (amd64, arm64): the server of ffmpeg-over-ip is the one of the release for it
ARG TARGETARCH

# renovate: datasource=github-releases depName=steelbrain/ffmpeg-over-ip
ARG FFMPEG_OVER_IP_VERSION=v5.2.1

# The drivers come from Ubuntu: 26.04 ships recent ones (iHD 26.1.2), newer than the ones of the repository of Intel for 24.04 (24.3.4),
# and this repository has no suite for 26.04. The drivers of 24.04 did not know the Arrow Lake-H GPU (8086:7dd1).
# - intel-media-va-driver-non-free: VAAPI (iHD), hwaccel=vaapi
# - libmfx-gen1.2, libvpl2: oneVPL runtime and dispatcher, hwaccel=qsv ("Error creating a MFX session: -9" without)
# - intel-opencl-icd, ocl-icd-libopencl1: OpenCL, hwaccel=opencl (HDR tone mapping, CL_PLATFORM_NOT_FOUND_KHR without)
# - vainfo, clinfo: to check the GPU from a shell in the container
# The Intel packages exist for amd64 only: on arm64 the GPU is served by the drivers of Mesa (VAAPI).
RUN set -eux; \
    packages="ca-certificates unzip wget vainfo"; \
    if [ "${TARGETARCH}" = amd64 ]; then \
        packages="${packages} intel-media-va-driver-non-free libmfx-gen1.2 libvpl2 intel-opencl-icd ocl-icd-libopencl1 clinfo"; \
    else \
        packages="${packages} mesa-va-drivers"; \
    fi; \
    apt-get update; \
    apt-get install -y --no-install-recommends ${packages}; \
    wget -q -O /tmp/server.zip "https://github.com/steelbrain/ffmpeg-over-ip/releases/download/${FFMPEG_OVER_IP_VERSION}/linux-${TARGETARCH}-ffmpeg-over-ip-server.zip"; \
    unzip -q -o /tmp/server.zip -d /opt/ffmpeg-over-ip; \
    chmod +x /opt/ffmpeg-over-ip/*; \
    rm /tmp/server.zip; \
    apt-get purge -y --auto-remove unzip wget; \
    rm -rf /var/lib/apt/lists/*

# the render node `/dev/dri` is mounted by the pod, the container reads it as root
ENV FFMPEG_OVER_IP_SERVER_ADDRESS=0.0.0.0:5050
EXPOSE 5050

ENTRYPOINT ["/opt/ffmpeg-over-ip/ffmpeg-over-ip-server"]
