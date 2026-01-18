package docker

import (
	"github.com/becloudless/becloudless/pkg/git"
	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
)

func GetRegistryAndRepositoryFromGitUrl(gitUrl string) (string, string, error) {
	host, owner, repo, err := git.ParseGitUrl(gitUrl)
	if err != nil {
		return "", "", errs.WithEF(err, data.WithField("url", gitUrl), "Failed to parse git URL")
	}

	if host == "github.com" {
		return "ghcr.io", "ghcr.io/" + owner + "/" + repo, nil
	}
	return host, host + "/" + owner + "/" + repo, nil
}
