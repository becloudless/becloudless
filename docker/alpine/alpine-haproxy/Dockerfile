FROM alpine:3.23.4

RUN apk add --no-cache haproxy upx && upx  /usr/sbin/haproxy && apk del upx

USER 100:101

CMD [ "haproxy" ]

