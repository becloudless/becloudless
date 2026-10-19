FROM --platform=$BUILDPLATFORM golang:1.27.2 AS builder

# upstream only publishes amd64 images: its Dockerfile hardcodes GOARCH=amd64
ARG TARGETOS
ARG TARGETARCH
# renovate: datasource=github-tags depName=mittwald/kubernetes-secret-generator
ARG SECRET_GENERATOR_VERSION=v3.5.0

RUN git clone --depth 1 --branch ${SECRET_GENERATOR_VERSION} https://github.com/mittwald/kubernetes-secret-generator /workdir
WORKDIR /workdir

RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build -a -o /workspace/manager ./cmd/manager/main.go

FROM gcr.io/distroless/static:nonroot

WORKDIR /
COPY --from=builder /workspace/manager .
USER 65532:65532

ENTRYPOINT ["/manager"]
