package nix

import (
	"bytes"
	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
	"golang.org/x/crypto/ssh"
	"strconv"
)

func Install(client *ssh.Client) error {
	res, err := RunGetStdout(client, `
	echo "s_uuid=$(sudo cat /sys/devices/virtual/dmi/id/product_uuid 2> /dev/null)" > /tmp/info
	echo "s_cpu=$(grep "Serial" /proc/cpuinfo | cut -f2 -d: | sed -e 's/^[[:space:]]*//')" >> /tmp/info
	echo "s_macs=\"$(find /sys/class/net/*/ -maxdepth 1 -type l -name device -exec sh -c "grep -q up \$(dirname {})/operstate && cat \$(dirname {})/address | tr '\n' ' '" \;)\"" >> /tmp/info
	echo "s_ips=\"$(ip -o addr show scope global | grep -E ": (wl|en|br)" | awk '{gsub(/\/.*/, " ",$4); print $4}' | tr '\n' ' ')\"" >> /tmp/info
	echo "s_disks=\"$(find /dev/disk/by-id/ -lname '*sd*' -o  -lname '*nvme*' -o -lname '*vd*' -o -lname '*scsi*' | grep -E -v -- "-part?" | grep '/ata\|/nvme\|usb\|/scsi'| tr '\n' ' ')\"" >> /tmp/info
	cat /tmp/info
	rm /tmp/info 
`)
	if err != nil {
		return errs.WithE(err, "Failed")
	}
	println("yopla" + strconv.Itoa(len(res)))

	println(res)
	return nil
}

func RunGetStdout(client *ssh.Client, cmd string) (string, error) {
	session, err := client.NewSession()
	var stdout bytes.Buffer
	var stderr bytes.Buffer
	session.Stdout = &stdout
	session.Stderr = &stderr

	if err != nil {
		return "", errs.WithE(err, "Failed to open ssh session")
	}
	defer session.Close()

	if err := session.Run(cmd); err != nil {
		return "", errs.WithEF(err, data.WithField("stderr", stderr.String()), "Failed to info")
	}
	return stdout.String(), nil
}
