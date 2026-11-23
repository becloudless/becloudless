package runner

import (
	"io"
	"net"

	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/go-erlog/logs"
)

// ForwardLocal listens on a free port of the loopback interface and forwards every connection to remoteAddr, as seen from
// the remote host. It returns the local address and a function stopping the forward.
func (r *SshRunner) ForwardLocal(remoteAddr string) (string, func(), error) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return "", nil, errs.WithE(err, "Failed to listen on a local port")
	}

	go func() {
		for {
			local, err := listener.Accept()
			if err != nil {
				return // closed
			}
			go r.forwardConn(local, remoteAddr)
		}
	}()

	return listener.Addr().String(), func() { _ = listener.Close() }, nil
}

func (r *SshRunner) forwardConn(local net.Conn, remoteAddr string) {
	defer local.Close()
	remote, err := r.client.Dial("tcp", remoteAddr)
	if err != nil {
		logs.WithEF(err, data.WithField("remote", remoteAddr)).Warn("Failed to open the ssh tunnel connection")
		return
	}
	defer remote.Close()

	done := make(chan struct{}, 2)
	go func() { _, _ = io.Copy(remote, local); done <- struct{}{} }()
	go func() { _, _ = io.Copy(local, remote); done <- struct{}{} }()
	<-done
}
