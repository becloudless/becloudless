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
	"path"
)

func EnsureEd25519KeyFile(keyFile string) error {
	// folder
	folder := path.Dir(keyFile)
	if stat, err := os.Stat(folder); os.IsNotExist(err) {
		if err := os.MkdirAll(folder, 0700); err != nil {
			return errs.WithEF(err, data.WithField("folder", folder), "Failed to create key folder")
		}
	} else if err != nil {
		return errs.WithEF(err, data.WithField("folder", folder), "Failed to read key folder")
	} else {
		if stat.Mode().Perm() != 0700 {
			if err := os.Chmod(folder, 0700); err != nil {
				return errs.WithE(err, "Key folder have wrong mode (0700) and cannot be changed")
			}
			logs.WithField("folder", folder).
				WithField("expected", "0700").
				WithField("current", stat.Mode().String()).
				Warn("Key folder had wrong mode. It's fixed")
		}
	}

	// file
	if stat, err := os.Stat(keyFile); os.IsNotExist(err) {
		logs.WithField("file", keyFile).Warn("Key is missing, creating...")
		return newPrivatePemEd25519KeyFile(keyFile)
	} else if err != nil {
		return errs.WithEF(err, data.WithField("file", keyFile), "Failed to read key file")
	} else {
		if stat.Mode().Perm() != 0600 {
			if err := os.Chmod(folder, 0600); err != nil {
				return errs.WithEF(err, data.WithField("file", keyFile), "Key file have wrong mode (0700) and cannot be changed")
			}
			logs.WithField("folder", folder).
				WithField("expected", "0700").
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

////////////////////////////////

func newPrivatePemEd25519KeyFile(keyFile string) error {
	_, key, err := NewPublicAndPrivatePenEd25519Key()
	if err != nil {
		return err
	}
	if err := os.WriteFile(keyFile, key, 0600); err != nil {
		return errs.WithEF(err, data.WithField("file", keyFile), "Failed to write key file")
	}
	return nil
}
