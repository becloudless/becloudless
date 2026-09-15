FROM alpine:3.20

RUN apk add --no-cache \
    curl \
    ca-certificates \
    conntrack-tools \
    iptables \
    ebtables \
    socat \
    containerd \
    kubelet \
    kubeadm \
    cni-plugins

RUN mkdir -p /etc/containerd && containerd config default > /etc/containerd/config.toml

CMD ["sh", "-c", "containerd & kubelet --fail-swap-on=false"]


# docker run --privileged --cgroupns host -v /lib/modules:/lib/modules:ro -v /sys/fs/cgroup:/sys/fs/cgroup:rw ghcr.io/becloudless/alpine-kubelet
