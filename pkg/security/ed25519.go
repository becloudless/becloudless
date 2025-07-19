package security

import (
	"crypto"
	"crypto/rand"
	"encoding/base64"
	"encoding/pem"
	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/go-erlog/logs"
	"golang.org/x/crypto/ed25519"
	"golang.org/x/crypto/ssh"
	"os"
)

func EnsureEd25519KeyFile(keyFile string) error {
	if stat, err := os.Stat(keyFile); os.IsNotExist(err) {
		logs.WithField("file", keyFile).Warn("Key is missing, creating...")
		pub, priv, err := NewPublicAndPrivatePenEd25519Key()
		if err != nil {
			return err
		}
		if err := os.WriteFile(keyFile, priv, 0600); err != nil {
			return errs.WithEF(err, data.WithField("file", keyFile), "Failed to write key file")
		}
		if err := os.WriteFile(keyFile+".pub", []byte(pub), 0644); err != nil {
			return errs.WithEF(err, data.WithField("file", keyFile), "Failed to write public key file")
		}
	} else if err != nil {
		return errs.WithEF(err, data.WithField("file", keyFile), "Failed to read key file")
	} else {
		if stat.Mode().Perm() != 0600 {
			if err := os.Chmod(keyFile, 0600); err != nil {
				return errs.WithEF(err, data.WithField("file", keyFile), "Key file have wrong mode (0700) and cannot be changed")
			}
			logs.WithField("file", keyFile).
				WithField("expected", "0600").
				WithField("current", stat.Mode().String()).
				Warn("Key file had wrong mode. It's fixed")
		}
	}
	return nil
}

func NewPublicAndPrivatePenEd25519Key() (string, []byte, error) {
	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		return "", []byte{}, errs.WithE(err, "Failed to generate new ed25519 key")
	}
	privatePemBlock, err := ssh.MarshalPrivateKey(crypto.PrivateKey(priv), "")
	if err != nil {
		return "", []byte{}, err
	}
	privatePemBytes := pem.EncodeToMemory(privatePemBlock)

	publicKey, err := ssh.NewPublicKey(pub)
	if err != nil {
		return "", []byte{}, err
	}
	publicKeyString := "ssh-ed25519" + " " + base64.StdEncoding.EncodeToString(publicKey.Marshal())
	return publicKeyString, privatePemBytes, nil
}
