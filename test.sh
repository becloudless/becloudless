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


clean_up () {
	[ -z "$(find ./tests/work -type f -name '*.pid')" ] || pkill -F ./tests/work/*.pid
}
trap clean_up EXIT

installHost() {
	host="$1"
	uuid="$2"
	diskSize="$3"
	memory="$4"
	validation=$5

	echo_brightred "## Creating $host disk image"
	mkdir -p ../../work
	qemu-img create -f qcow2 "../..//work/$host.cow" $diskSize

	echo_brightred "## Starting VM"
	display="-display none"
	$DEBUG && display=""
	qemu-system-x86_64 \
		-boot order=cd \
		-uuid "$uuid" \
		-m $memory \
		-smp 2 \
		-enable-kvm \
		-net nic \
		-net user,hostfwd=tcp::10022-:22 \
		-cdrom ./nixos/result/iso/bcl.iso \
		-pidfile ../../work/$host.pid \
		-daemonize \
		$display \
		../../work/$host.cow
	#	-drive file=../..//work/test-tv.cow,if=virtio,format=raw,cache=none,aio=native \

	$DEBUG && {
		read -p "Waiting after cd boot in debug. Enter to continue"
	}

	echo_brightred "## Install VM"
	sleep 20
	bclDebug=""
	$DEBUG && bclDebug="-L trace"
	pwd
	$BCL_BIN $bclDebug -H ../ nix install --user=nixos --disk-password=qw -p 10022 -i ../secrets/ed25519 -h 127.0.0.1

	$DEBUG && {
		read -p "Waiting after install in debug. Enter to continue"
	}

	echo_brightred "## Checking result"
	sleep 30
	($5)

	return 0
}

###########

if compgen -G "./cli/dist/bcl-*/bcl" > /dev/null 2>&1; then
	echo_brightred "## Using local bcl build"
	BCL_BIN="$(compgen -G "./cli/dist/bcl-*/bcl" | head -1)"
else
	echo_brightred "## Downloading bcl from GitHub release"
	VERSION="$(grep -E '^\s+version = ' nixos/packages/bcl/default.nix | sed 's/.*"\(.*\)".*/\1/')"
	mkdir -p ./work
	curl -fsSL "https://github.com/becloudless/becloudless/releases/download/cli-v${VERSION}/bcl-linux-amd64.tar.gz" \
		| tar -xz -C ./work
	BCL_BIN="./work/bcl-linux-amd64/bcl"
fi

echo_brightred "## Check flake"
(cd tests/basic/repository/nixos && nix flake update && nix flake check)

echo_brightred "## Prepare host"
$BCL_BIN -H ./tests/basic nixos prepare

[ -f ./tests/basic/repository/nixos/result/iso/bcl.iso ] || {
	echo_brightred "## Building iso image"
	# TODO replace with bcl command
	tmpKeyFile=/tmp/install-ssh_host_ed25519_key
	export SOPS_AGE_KEY_FILE=./tests/basic/secrets/age
	nix-shell -p sops -p yq --run "sops -d ./tests/basic/repository/nixos/modules/nixos/groups/install/default.secrets.yaml | yq -r .ssh_host_ed25519_key" > $tmpKeyFile
	(cd tests/basic/repository/nixos && nix build .#isoConfigurations.iso --impure)
}

###
#rm -Rf ./tests/new && mkdir -p ./tests/new

#nix-shell -p expect --run expect <<EOF
#	spawn ./dist/bcl-linux-amd64/bcl -H ./tests/new nixos global edit
#
#	expect "locale"
#	send "mylocale\r\r" # locale
#	send "mytimezone\r\r" # timezone
#	interact
#
#	# Use the correct prompt
#  #set prompt ":|#|\\\$|>"
#  #interact -o -nobuffer -re $prompt return
#  #interact -o -nobuffer -re $prompt return
#EOF

#./dist/bcl-*/bcl -H ./tests/new nixos prepare
#./dist/bcl-*/bcl -H ./tests/new nixos groups create something

#exit 0

###
#validate-test-workstation() {
#	echo "hello" | ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -i tests/basic/secrets/ed25519 -p 10022 toto@127.0.0.1 sudo ls -la
#}
#installHost "test-workstation" \
# 	"c9b0fb14-1949-6949-9711-63409d2f9cfe" \
# 	14G \
# 	3G \
# 	validate-test-workstation

###
validate-test-tv() {
	ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -i ../secrets/ed25519 -p 10022 toto@127.0.0.1 pidof jellyfin-desktop
}

(cd ./tests/basic/repository && installHost "test-tv" \
	"7d5e9855-0cba-4c41-b45e-cdff7a9514d9" \
	13G \
	3G \
	validate-test-tv)



# kill in advance https://unix.stackexchange.com/questions/668024/run-foreground-process-until-background-process-exited-in-shell

echo_green "## EVERYTHING IS OK"
exit 0
