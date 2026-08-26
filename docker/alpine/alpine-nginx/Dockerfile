FROM alpine:3.24.1

RUN apk add --no-cache nginx nginx-mod-stream

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Runs nginx in the foreground plus a poll loop that reloads it (nginx -s reload,
# graceful: existing connections are kept until they finish) whenever any file
# under /etc/nginx changes, checked every NGINX_RELOAD_INTERVAL seconds (5 by
# default). This lets config changes be picked up without restarting the
# container or overriding its cmd.
ENTRYPOINT ["/entrypoint.sh"]
