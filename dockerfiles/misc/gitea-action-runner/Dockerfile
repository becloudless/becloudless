FROM gitea/act_runner:0.4.0

RUN apk add --no-cache nodejs docker

ENV DOCKER_HOST=tcp://localhost:2376/
ENV DOCKER_TLS_CERTDIR="/certs"
ENV DOCKER_TLS_VERIFY=1
ENV DOCKER_CERT_PATH="/certs/client"

ADD start.sh /
ENTRYPOINT ["/start.sh"]
