FROM alpine:3.24

RUN apk add --no-cache \
    ca-certificates \
    conntrack-tools \
    iptables \
    containerd \
    kubelet \
    kubeadm \
    cni-plugins \
    s6-overlay

COPY rootfs/ /

ENTRYPOINT ["/init"]
