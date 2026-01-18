package git

import (
	"net/url"
	"strings"

	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
)

// parseGitRemote parses a git remote URL (HTTPS or SSH-like) and returns host, owner, repo.
// Examples supported:
//   - https://github.com/owner/repo.git
//   - http://git.example.com/owner/repo
//   - git@github.com:owner/repo.git
//   - ssh://git@gitea.example.com/owner/repo.git
func ParseGitUrl(gitUrl string) (host, owner, repo string, err error) {
	// Try URL parse first (handles http/https/ssh://)
	if strings.Contains(gitUrl, "://") {
		u, e := url.Parse(gitUrl)
		if e != nil {
			return "", "", "", e
		}

		// u.Host may contain port; drop it
		host = u.Host
		if i := strings.Index(host, ":"); i >= 0 {
			host = host[:i]
		}

		parts := strings.Split(strings.TrimPrefix(u.Path, "/"), "/")
		if len(parts) < 2 {
			return "", "", "", errs.WithF(data.WithField("url", gitUrl), "remote path does not contain owner/repo")
		}
		owner = parts[0]
		repo = parts[1]
		repo = strings.TrimSuffix(repo, ".git")
		return host, owner, repo, nil
	}

	// SSH scp-like syntax: git@github.com:owner/repo.git
	if i := strings.Index(gitUrl, "@"); i >= 0 {
		rest := gitUrl[i+1:]
		// rest is like: github.com:owner/repo.git
		parts := strings.SplitN(rest, ":", 2)
		if len(parts) != 2 {
			return "", "", "", errs.WithF(data.WithField("url", gitUrl), "invalid scp-like git URL")
		}
		host = parts[0]
		path := parts[1]

		pathParts := strings.Split(path, "/")
		if len(pathParts) < 2 {
			return "", "", "", errs.WithF(data.WithField("url", gitUrl), "url path does not contain owner/repo")
		}
		owner = pathParts[0]
		repo = pathParts[1]

		repo = strings.TrimSuffix(repo, ".git")
		return host, owner, repo, nil
	}

	return "", "", "", errs.WithF(data.WithField("url", gitUrl), "unsupported git URL format")
}
