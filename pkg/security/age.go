package security

import (
	"github.com/Mic92/ssh-to-age"
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/go-erlog/logs"
	"os"
)

func Ed25519PrivateKeyFileToPublicAndPrivateAgeKeys(file string) (string, string, error) {
	readFile, err := os.ReadFile(file)
	if err != nil {
		return "", "", errs.WithE(err, "Failed to read ed25519 private key file")
	}
	return Ed25519ToPublicAndPrivateAgeKeys(readFile)
}

func Ed25519ToPublicAndPrivateAgeKeys(privateKey []byte) (string, string, error) {
	priv, pub, err := agessh.SSHPrivateKeyToAge(privateKey, []byte{})
	if err != nil {
		return "", "", errs.WithE(err, "Failed to convert ed25519 private key to age")
	}

	logs.WithField("public", *pub).Debug("public age key of ed25519 private key")
	return *pub, *priv, nil
}
