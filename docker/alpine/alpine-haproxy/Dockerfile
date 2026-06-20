FROM alpine:3.24.1

RUN apk add --no-cache haproxy upx && upx  /usr/sbin/haproxy && apk del upx

USER 100:101

CMD [ "haproxy" ]

