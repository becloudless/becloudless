FROM alpine:3.24.2

RUN apk add --no-cache haproxy upx && upx  /usr/sbin/haproxy && apk del upx

USER 100:101

CMD [ "haproxy" ]

