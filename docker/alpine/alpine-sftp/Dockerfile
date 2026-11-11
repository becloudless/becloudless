FROM rust:alpine AS pam-oauth2-device

RUN apk add --no-cache build-base linux-pam-dev openssl-dev pkgconf curl

# PAM module of the OAuth 2.0 device authorization grant: the user approves the login in a browser, on its identity provider
ARG PAM_OAUTH2_DEVICE_VERSION=0.4.3
WORKDIR /src
RUN curl -fsSL "https://github.com/Nithe14/pam_oauth2_device/archive/refs/tags/${PAM_OAUTH2_DEVICE_VERSION}.tar.gz" | tar -xz --strip-components=1
# musl links the C runtime statically by default, which a shared library can not do
RUN RUSTFLAGS="-C target-feature=-crt-static" cargo build --release

FROM alpine:3.24.4

# sshd with PAM, only for the sftp subsystem: the configuration is made by the pod at its start
RUN apk add --no-cache openssh-server-pam openssh-sftp-server linux-pam libgcc openssl ca-certificates
COPY --from=pam-oauth2-device /src/target/release/libpam_oauth2_device.so /usr/lib/security/pam_oauth2_device.so
