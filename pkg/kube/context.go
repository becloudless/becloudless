package kube

import (
	"path/filepath"
	"strings"

	"github.com/becloudless/becloudless/pkg/git"
	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
)

type Context struct {
	Cluster     string
	ClusterPath string
	Namespace   string
	KubeConfig  string
}

func (c Context) ToEnv() string {
	builder := strings.Builder{}

	builder.WriteString("export KUBE_CLUSTER=")
	builder.WriteString(c.Cluster)
	builder.WriteString("\n")

	builder.WriteString("export KUBE_CLUSTER_ROOT=")
	builder.WriteString(c.ClusterPath)
	builder.WriteString("\n")

	builder.WriteString("export KUBE_NAMESPACE=")
	builder.WriteString(c.Namespace)
	builder.WriteString("\n")

	builder.WriteString("export KUBECONFIG=")
	builder.WriteString(c.KubeConfig)
	builder.WriteString("\n")

	return builder.String()
}

func GetContext(path string) (Context, error) {
	var context Context
	repository, err := git.OpenRepository(path)
	if err != nil {
		return context, err
	}

	abs, err := filepath.Abs(path)
	if err != nil {
		return context, errs.WithEF(err, data.WithField("path", path), "Failed to read absolute path")
	}

	rel, err := filepath.Rel(repository.Root, abs)
	if err != nil {
		return context, errs.WithE(err, "Failed to find relative path from repo root to current path")
	}

	innerPaths := strings.Split(rel, "/")
	if len(innerPaths) < 3 ||
		!(innerPaths[0] == "kube" && innerPaths[1] == "clusters") {
		return context, nil
	}
	context.Cluster = innerPaths[2]
	context.ClusterPath = filepath.Join(repository.Root, innerPaths[0], innerPaths[1], innerPaths[2])
	context.KubeConfig = filepath.Join(repository.Root, ".kube", context.Cluster+".config")
	if len(innerPaths) > 3 {
		context.Namespace = innerPaths[3]
	}

	return context, nil
}
