package nixos

import (
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
	"github.com/spf13/cobra"
)

func nixosIsoCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "iso",
		Short: "Handle iso images for system installations",
	}

	cmd.AddCommand(
		nixosIsoSystemsCmd(),
		nixosIsoBuildCmd(),
	)

	return cmd
}

// findAvailableSystems scans the systems/ directory for snowfall-lib arch-format folders
// (e.g. "x86_64-iso", "aarch64-raw-efi") and returns their contents as "kind/system" strings.
// Folders whose format part is "linux" or "darwin" are skipped (those are nixosConfigurations).
func findAvailableSystems(nixosDir string) ([]string, error) {
	systemsDir := filepath.Join(nixosDir, "systems")
	archEntries, err := os.ReadDir(systemsDir)
	if err != nil {
		return nil, errs.WithEF(err, data.WithField("dir", systemsDir), "Failed to read systems directory")
	}

	var results []string
	for _, archEntry := range archEntries {
		if !archEntry.IsDir() {
			continue
		}
		// snowfall-lib names: "<arch>-<format>", e.g. "x86_64-iso", "aarch64-raw-efi".
		// The format is everything after the first "-".
		parts := strings.SplitN(archEntry.Name(), "-", 2)
		if len(parts) != 2 {
			continue
		}
		kind := parts[1]
		if kind == "linux" || kind == "darwin" {
			continue // plain nixosConfigurations
		}

		systemEntries, err := os.ReadDir(filepath.Join(systemsDir, archEntry.Name()))
		if err != nil {
			return nil, errs.WithEF(err, data.WithField("dir", archEntry.Name()), "Failed to read arch systems directory")
		}
		for _, sysEntry := range systemEntries {
			if sysEntry.IsDir() {
				results = append(results, kind+"/"+sysEntry.Name())
			}
		}
	}
	sort.Strings(results)
	return results, nil
}
