package ci

import (
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/becloudless/becloudless/pkg/cmd/kube/chart"
	"github.com/becloudless/becloudless/pkg/docker"
	"github.com/becloudless/becloudless/pkg/git"
	"github.com/becloudless/becloudless/pkg/kube/helm"
	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/go-erlog/logs"
	"github.com/spf13/cobra"
	"helm.sh/helm/v3/pkg/chartutil"
)

const chartsFolder = "kube/charts"

func CiChartCmd() *cobra.Command {
	var kubeVersion string

	cmd := &cobra.Command{
		Use:   "chart",
		Short: "Handle helm charts",
		RunE: func(cmd *cobra.Command, args []string) error {
			repo, err := git.OpenRepository(".")
			if err != nil {
				return err
			}

			changes, err := repo.GetFilesChangedInCurrentBranch()
			if err != nil {
				return err
			}

			isMain, err := repo.IsCurrentBranchMain()
			if err != nil {
				return errs.WithE(err, "Failed to determine if current branch is main")
			}

			changed := make(map[string]struct{})
			for file := range changes {
				if !strings.HasPrefix(file, chartsFolder+"/") {
					continue
				}
				dir := findChartFolderFromFile(file)
				if dir == "" {
					logs.WithField("change", file).Debug("Skip change outside of a chart")
					continue
				}
				changed[dir] = struct{}{}
			}

			toBuild, err := addLocalDependents(changed)
			if err != nil {
				return err
			}

			remote := ""
			if isMain && len(toBuild) > 0 {
				remote, err = chartRemoteFromGitRepository(repo)
				if err != nil {
					return err
				}
			}

			for _, dir := range toBuild {
				logs.WithField("path", dir).Info("Building chart")
				if err := chart.BuildChart(dir, kubeVersion, false, false); err != nil {
					return err
				}
			}

			if !isMain {
				return nil
			}

			// toBuild is ordered with dependencies first
			for _, dir := range toBuild {
				logs.WithField("path", dir).WithField("remote", remote).Info("Pushing chart")
				if err := chart.PushChart(dir, helm.PushOptions{Remote: remote}); err != nil {
					return err
				}
			}

			return nil
		},
	}

	cmd.Flags().StringVar(&kubeVersion, "kube-version", "1.31.0", "Kubernetes version used for Capabilities.KubeVersion")
	return cmd
}

func chartRemoteFromGitRepository(repo *git.Repository) (string, error) {
	url, err := repo.GetRemoteOriginURL()
	if err != nil {
		return "", errs.WithE(err, "Failed to get remote origin URL")
	}
	registry, _, err := docker.GetRegistryAndRepositoryFromGitUrl(url)
	if err != nil {
		return "", errs.WithE(err, "Failed to deduce registry from git URL")
	}
	return "oci://" + registry, nil
}

// findChartFolderFromFile returns the closest parent folder of file containing a Chart.yaml, within the charts folder.
func findChartFolderFromFile(file string) string {
	dir := filepath.Dir(file)
	for strings.HasPrefix(dir, chartsFolder+"/") {
		if _, err := os.Stat(filepath.Join(dir, "Chart.yaml")); err == nil {
			return dir
		}
		dir = filepath.Dir(dir)
	}
	return ""
}

// addLocalDependents adds to the changed charts every chart depending on one of them through a file:// dependency,
// and returns them ordered so a chart always comes after the charts it depends on.
func addLocalDependents(changed map[string]struct{}) ([]string, error) {
	entries, err := os.ReadDir(chartsFolder)
	if err != nil {
		return nil, errs.WithEF(err, data.WithField("path", chartsFolder), "Failed to read charts folder")
	}

	localDeps := map[string][]string{} // chart dir -> chart dirs it depends on
	var all []string
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		dir := filepath.Join(chartsFolder, entry.Name())
		metadata, err := chartutil.LoadChartfile(filepath.Join(dir, "Chart.yaml"))
		if err != nil {
			if os.IsNotExist(err) {
				continue
			}
			return nil, errs.WithEF(err, data.WithField("path", dir), "Failed to read Chart.yaml")
		}
		all = append(all, dir)
		for _, dep := range metadata.Dependencies {
			if strings.HasPrefix(dep.Repository, "file://") {
				localDeps[dir] = append(localDeps[dir], filepath.Join(dir, strings.TrimPrefix(dep.Repository, "file://")))
			}
		}
	}
	sort.Strings(all)

	selected := map[string]bool{}
	for dir := range changed {
		selected[dir] = true
	}
	for updated := true; updated; {
		updated = false
		for _, dir := range all {
			if selected[dir] {
				continue
			}
			for _, dep := range localDeps[dir] {
				if selected[filepath.Clean(dep)] {
					selected[dir] = true
					updated = true
					break
				}
			}
		}
	}

	var ordered []string
	done := map[string]bool{}
	var visit func(dir string)
	visit = func(dir string) {
		if done[dir] || !selected[dir] {
			return
		}
		done[dir] = true
		for _, dep := range localDeps[dir] {
			visit(filepath.Clean(dep))
		}
		ordered = append(ordered, dir)
	}
	for _, dir := range all {
		visit(dir)
	}
	return ordered, nil
}
