package main

import (
	"context"
	"embed"
	"fmt"
	"io/fs"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
)

//go:embed assets
var Assets embed.FS

// RestoreCollection restores a specific collection (one entry of the go:embed statement) into dir
func RestoreCollection(ctx context.Context, dir, collection string) (err error) {
	return fs.WalkDir(Assets, collection, func(path string, d fs.DirEntry, err error) error {
		if err = ctx.Err(); err != nil {
			return err
		}

		if d == nil {
			return nil
		}

		dest := filepath.Join(dir, path)
		slog := slog.With("dst", dest)

		if d.IsDir() {
			slog.Debug("restoring asset", "type", "dir")
			return os.MkdirAll(dest, 0755)
		} else {
			if d.Type().IsRegular() {
				var (
					src     = filepath.Join(path)
					content []byte
					output  *os.File
					err     error
					perm    os.FileMode = 0644
				)

				// Note: embed does not store file permissions, so it's up to us to restore them.
				// We'll assume that collections named "bin"-something contain commands, and that
				// all "*.sh" files should also have the execution bit set; however an alternative
				// strategy would be to embed a tar archive, which would then contain the permission flags.
				if strings.HasPrefix(collection, "bin") || strings.HasSuffix(src, ".sh") {
					perm = 0755
				}
				slog.Debug("restoring asset", "type", "file", "src", src, "perm", perm)

				if content, err = Assets.ReadFile(src); err != nil {
					return fmt.Errorf("error reading embedded asset %s: %w", src, err)
				}

				if output, err = os.OpenFile(dest, os.O_CREATE|os.O_WRONLY, perm); err != nil {
					return err
				}

				defer output.Close()
				_, err = output.Write(content)
				return err
			}
		}

		return nil
	})
}

// Restore restores all embedded assets into dir
func Restore(ctx context.Context, dir string) (err error) {
	slog.Debug("restoring assets", "dest", dir)
	for _, collection := range []string{"bin", "bin-beta", "share"} {
		if err = ctx.Err(); err != nil {
			return
		}

		if err = RestoreCollection(ctx, dir, collection); err != nil {
			break
		}
	}
	slog.Debug("assets restoration complete", "err", err)
	return err
}
