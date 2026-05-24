#!/usr/bin/env sh

while ! nc -z localhost 2376 </dev/null; do
	echo 'waiting for docker daemon...'
	sleep 5
done

/usr/bin/docker context create mybuildx
/usr/bin/docker buildx create --name mybuilder --driver docker-container --buildkitd-flags '--allow-insecure-entitlement security.insecure --allow-insecure-entitlement network.host' --use mybuildx


# maybe to get around sudo issue
#docker run --privileged multiarch/qemu-user-static:latest --reset -p yes --credential yes

exec /sbin/tini -- /opt/act/run.sh
