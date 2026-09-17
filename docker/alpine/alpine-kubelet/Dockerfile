FROM alpine:3.24

RUN apk add --no-cache \
    ca-certificates \
    conntrack-tools \
    iptables \
    containerd \
    kubelet \
    kubeadm \
    cni-plugins \
    open-iscsi \
    s6-overlay

COPY rootfs/ /

ENTRYPOINT ["/init"]
