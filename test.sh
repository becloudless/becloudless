#!/usr/bin/env bash
set -e
set -x

DEBUG="${DEBUG:=false}"

echo_stderr() { echo -e "$*" 1>&2;}
echo_green() { echo_stderr "\033[0;32m$*\033[0m";}
echo_red() { echo_stderr "\033[0;31m$*\033[0m";}
echo_brightred() { echo_stderr "\033[0;91m$*\033[0m";}
echo_yellow() { echo_stderr "\033[0;33m$*\033[0m";}
echo_purple() { echo_stderr "\033[0;35m$*\033[0m";}
echo_blue() { echo_stderr "\033[0;34m$*\033[0m";}


nix run --refresh github:n0rad/nixos-anywhere || true

echo_brightred "## Building bcl"
./gomake build


echo_brightred "## Prepare host"
./dist/bcl-*/bcl -H ./tests/basic nixos prepare

[ -f ./tests/basic/repository/nixos/result/iso/bcl.iso ] || {
	echo_brightred "## Building iso image"
	(cd tests/basic/repository/nixos && nix flake update && nix build .#isoConfigurations.iso)
}

echo_brightred "## Creating test-tv disk image"
mkdir -p ./tests/work
qemu-img create -f qcow2 ./tests/work/test-tv.cow 8G

echo_brightred "## Starting VM"
display="-display none"
$DEBUG && display=""
qemu-system-x86_64 \
	-boot order=cd \
	-uuid 7d5e9855-0cba-4c41-b45e-cdff7a9514d9 \
	-m 3G \
	-smp 2 \
	-enable-kvm \
	-net nic \
	-net user,hostfwd=tcp::10022-:22 \
	-cdrom ./tests/basic/repository/nixos/result/iso/bcl.iso \
	-pidfile ./tests/work/test-tv.pid \
	-daemonize \
	$display \
	./tests/work/test-tv.cow
#	-drive file=./tests/work/test-tv.cow,if=virtio,format=raw,cache=none,aio=native \

clean_up () {
	pkill -F ./tests/work/test-tv.pid
}
trap clean_up EXIT

echo_brightred "## Install VM"
sleep 20
bclDebug=""
$DEBUG && bclDebug="-L debug"
./dist/bcl-*/bcl $bclDebug -H ./tests/basic nix install -L trace -p 10022 -i tests/basic/secrets/ed25519 127.0.0.1

echo_brightred "## Checking result"
sleep 60
ssh -o StrictHostKeyChecking=no -i tests/basic/secrets/ed25519 -p 10022 toto@127.0.0.1 pidof jellyfinmediaplayer

echo_green "## EVERYTHING IS OK"

# kill in advance https://unix.stackexchange.com/questions/668024/run-foreground-process-until-background-process-exited-in-shell
$DEBUG && sleep infinity
