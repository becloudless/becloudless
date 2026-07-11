package nixos

import (
	"bytes"
	"crypto/sha512"
	"encoding/hex"
	"io"
	"os"
	"strings"

	"github.com/becloudless/becloudless/pkg/system/runner"
	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/go-erlog/logs"
)

type BackupPeriod string

func FromBackupPeriodString(s string) (BackupPeriod, error) {
	switch s {
	case "hourly", "h":
		return BackupPeriodHourly, nil
	case "daily", "d":
		return BackupPeriodDaily, nil
	case "weekly", "w":
		return BackupPeriodWeekly, nil
	case "monthly", "m":
		return BackupPeriodMonthly, nil
	case "semesterly", "s":
		return BackupPeriodSemesterly, nil
	case "yearly", "y":
		return BackupPeriodYearly, nil
	default:
		return "", errs.WithF(data.WithField("string", s), "Invalid backup period")
	}
}

func (p BackupPeriod) String() string {
	return string(p)
}

const (
	BackupPeriodHourly     BackupPeriod = "hourly"
	BackupPeriodDaily      BackupPeriod = "daily"
	BackupPeriodWeekly     BackupPeriod = "weekly"
	BackupPeriodMonthly    BackupPeriod = "monthly"
	BackupPeriodSemesterly BackupPeriod = "semesterly"
	BackupPeriodYearly     BackupPeriod = "yearly"
)

// DefaultBackupIdentityFile is the ssh identity file bcl.backups uses on the
// host that produced the backup, used as the default source of identity
// material when none is provided via a secured reader.
const DefaultBackupIdentityFile = "/nix/etc/ssh/ssh_host_ed25519_key"

// rawMountDir returns the local mountpoint for the raw (still encrypted) sshfs
// mount backing a decrypted backup mountpoint.
func rawMountDir(mountpoint string) string {
	return mountpoint + ".raw-sshfs"
}

// MountBackup mounts a remote backup (created by the bcl.backups nixos module)
// at mountpoint, read-only unless rw is true. It first mounts the remote
// encrypted directory via sshfs, then decrypts it with gocryptfs using a
// passphrase derived from the ssh identity read from identity, exactly as
// bcl.backups does when producing the backup. This must run on the same host
// that produced the backup.
//
// target is in "host:/path" or "user@host:/path" format. If sshUser is not
// empty and target doesn't already carry a user, sshUser is prepended.
//
// identity is read fully in memory (e.g. it can be a memguarded.Service.Reader()
// so the key material never has to live unprotected on disk) and is then
// written to a private (0600) temporary file, since sshfs/ssh require an
// actual file for -o IdentityFile. The temporary file is removed as soon as
// the sshfs mount is established.
func MountBackup(target string, mountpoint string, identity io.Reader, sshUser string, rw bool) error {
	raw := rawMountDir(mountpoint)

	if sshUser != "" && !strings.Contains(target, "@") {
		target = sshUser + "@" + target
	}

	if err := os.MkdirAll(mountpoint, 0755); err != nil {
		return errs.WithE(err, "Failed to create mountpoint directory")
	}
	if err := os.MkdirAll(raw, 0755); err != nil {
		return errs.WithE(err, "Failed to create raw sshfs mount directory")
	}

	identityBytes, err := io.ReadAll(identity)
	if err != nil {
		return errs.WithE(err, "Failed to read ssh identity")
	}
	defer wipeBytes(identityBytes)

	// Strip leading whitespace from each line first: pasting a key out of an
	// indented sops/YAML block scalar carries that indentation along, which
	// is not part of the actual key content (the YAML parser would strip it
	// when sops-nix renders the real file), so it must be removed before
	// deriving anything from these bytes, not just for the ssh copy.
	dedented := trimLeadingLineWhitespace(identityBytes)
	defer wipeBytes(dedented)

	// The gocryptfs passphrase is a sha512sum of the fully-trimmed identity
	// content. bcl.backups applies the same trimming to the key file on the
	// source host before hashing it, so both sides must stay in sync.
	passphraseBytes := bytes.TrimSpace(dedented)

	// The copy written out for ssh/sshfs keeps its internal newlines as-is
	// (only dedented above), since ssh doesn't care about surrounding blank
	// lines the way a byte-exact hash does.
	sshKeyBytes := dedented

	identityFile, err := os.CreateTemp("", "bcl-backup-identity-")
	if err != nil {
		return errs.WithE(err, "Failed to create temporary identity file")
	}
	identityFilePath := identityFile.Name()
	defer os.Remove(identityFilePath)

	if err := identityFile.Chmod(0600); err != nil {
		_ = identityFile.Close()
		return errs.WithE(err, "Failed to chmod temporary identity file")
	}
	if _, err := identityFile.Write(sshKeyBytes); err != nil {
		_ = identityFile.Close()
		return errs.WithE(err, "Failed to write temporary identity file")
	}
	if err := identityFile.Close(); err != nil {
		return errs.WithE(err, "Failed to close temporary identity file")
	}

	localRunner := runner.NewLocalRunner()

	sshfsMode := "ro"
	if rw {
		sshfsMode = "rw"
	}

	logs.WithField("target", target).WithField("dir", raw).Info("Mounting remote backup (encrypted) via sshfs")
	if err := localRunner.ExecCmd("sshfs",
		"-o", sshfsMode,
		"-o", "follow_symlinks",
		"-o", "IdentityFile="+identityFilePath,
		"-o", "StrictHostKeyChecking=no",
		target, raw,
	); err != nil {
		return errs.WithE(err, "Failed to sshfs mount remote backup")
	}

	passphrase := backupPassphraseFromBytes(passphraseBytes)

	passFile, err := os.CreateTemp("", "bcl-backup-pass-")
	if err != nil {
		_ = localRunner.ExecCmd("fusermount", "-u", raw)
		return errs.WithE(err, "Failed to create temporary passphrase file")
	}
	defer os.Remove(passFile.Name())

	if err := os.WriteFile(passFile.Name(), []byte(passphrase), 0600); err != nil {
		_ = localRunner.ExecCmd("fusermount", "-u", raw)
		return errs.WithE(err, "Failed to write temporary passphrase file")
	}

	gocryptfsArgs := []string{"-nosyslog", "-sharedstorage", "-passfile", passFile.Name()}
	if !rw {
		gocryptfsArgs = append(gocryptfsArgs, "-ro")
	}
	gocryptfsArgs = append(gocryptfsArgs, raw, mountpoint)

	logs.WithField("mountpoint", mountpoint).Info("Mounting decrypted view of the backup")
	if err := localRunner.ExecCmd("gocryptfs", gocryptfsArgs...); err != nil {
		_ = localRunner.ExecCmd("fusermount", "-u", raw)
		return errs.WithE(err, "Failed to gocryptfs mount decrypted backup")
	}

	if rw {
		logs.WithField("mountpoint", mountpoint).Info("Backup mounted read-write")
	} else {
		logs.WithField("mountpoint", mountpoint).Info("Backup mounted read-only")
	}
	return nil
}

// UmountBackup unmounts a backup previously mounted with MountBackup.
func UmountBackup(mountpoint string) error {
	raw := rawMountDir(mountpoint)
	localRunner := runner.NewLocalRunner()

	logs.WithField("mountpoint", mountpoint).Info("Unmounting decrypted backup view")
	if err := localRunner.ExecCmd("fusermount", "-u", mountpoint); err != nil {
		return errs.WithE(err, "Failed to unmount decrypted backup view")
	}

	logs.WithField("dir", raw).Info("Unmounting raw sshfs backup mount")
	if err := localRunner.ExecCmd("fusermount", "-u", raw); err != nil {
		return errs.WithE(err, "Failed to unmount raw sshfs backup mount")
	}

	if err := os.Remove(raw); err != nil && !os.IsNotExist(err) {
		logs.WithE(err).Warn("Failed to remove raw sshfs mount directory")
	}
	return nil
}

// backupPassphraseFromBytes derives the gocryptfs passphrase the same way
// bcl.backups does: the hex-encoded sha512sum of the ssh identity content.
func backupPassphraseFromBytes(identityBytes []byte) string {
	sum := sha512.Sum512(identityBytes)
	return hex.EncodeToString(sum[:])
}

// trimLeadingLineWhitespace strips leading spaces/tabs from every line of b.
// This is only used for the copy of the identity written out for ssh/sshfs,
// so that pasting a key out of an indented YAML block scalar (e.g. a sops
// secrets file) works without requiring the paste to be dedented by hand.
func trimLeadingLineWhitespace(b []byte) []byte {
	lines := bytes.Split(b, []byte("\n"))
	for i, line := range lines {
		lines[i] = bytes.TrimLeft(line, " \t")
	}
	return bytes.Join(lines, []byte("\n"))
}

// wipeBytes zeroes out a byte slice in place, best-effort, once the identity
// content is no longer needed in memory.
func wipeBytes(b []byte) {
	for i := range b {
		b[i] = 0
	}
}
