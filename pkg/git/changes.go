package git

import (
	"io"
	"slices"

	"github.com/go-git/go-git/v6"
	"github.com/go-git/go-git/v6/plumbing"
	"github.com/go-git/go-git/v6/plumbing/object"
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/go-erlog/logs"
)

type ChangeType string

const (
	ChangeAdded    ChangeType = "added"
	ChangeModified ChangeType = "modified"
	ChangeDeleted  ChangeType = "deleted"
	ChangeRenamed  ChangeType = "renamed"
)

var mainBranches = []string{"main", "master"}

func (r Repository) IsCurrentBranchMain() (bool, error) {
	branch, err := r.GetCurrentBranchName()
	if err != nil {
		return false, errs.WithE(err, "Failed to get current branch name")
	}
	return slices.Contains(mainBranches, branch), nil
}

func (r Repository) GetCurrentBranchName() (string, error) {
	headRef, err := r.Repo.Head()
	if err != nil {
		return "", errs.WithEF(err, r.logData, "Failed to get HEAD reference")
	}

	name := headRef.Name()
	if !name.IsBranch() {
		return "", errs.WithEF(nil, r.logData.WithField("ref", name.String()), "HEAD is not pointing to a branch")
	}
	return name.Short(), nil
}

func (r Repository) GetBranchCommit(branch string) (string, error) {
	refName := plumbing.NewBranchReferenceName(branch)
	ref, err := r.Repo.Reference(refName, true)
	if err != nil {
		return "", errs.WithEF(err, r.logData.WithField("branch", branch), "Failed to get branch reference")
	}
	return ref.Hash().String(), nil
}

// TODO handle the added then deleted case
func (r Repository) GetFilesChangedInCurrentBranch() (map[string]ChangeType, error) {

	branch, err := r.GetCurrentBranchName()
	if err != nil {
		return nil, errs.WithE(err, "Failed to get current branch name")
	}

	var commitHashes []string
	if slices.Contains(mainBranches, branch) {
		logs.WithField("branch", branch).Info("Current branch is a main branch, building only last commit")

		commit, err := r.GetBranchCommit(branch)
		if err != nil {
			return nil, errs.WithE(err, "Failed to get last commit of current branch")
		}
		commitHashes = []string{commit}
	} else {
		logs.WithField("branch", branch).Info("Current branch found")
		hashs, err := r.GetCommitsInBranch(branch)
		if err != nil {
			return nil, errs.WithEF(err, r.logData.WithField("branch", branch), "Failed to get commits in branch")
		}
		commitHashes = hashs
	}

	logs.WithField("commits", commitHashes).Trace("Commits to analyze for changes")

	changedFiles := make(map[string]ChangeType)
	for _, hash := range commitHashes {
		files, err := r.GetFilesChangedInCommit(hash)
		if err != nil {
			return nil, errs.WithEF(err, r.logData.WithField("commit", hash), "Failed to get files changed in commit")
		}
		for path, ct := range files {
			changedFiles[path] = ct
		}
	}

	return changedFiles, nil
}

func (r Repository) GetFilesChangedInCommit(commitHash string) (map[string]ChangeType, error) {
	hex, ok := plumbing.FromHex(commitHash)
	if !ok {
		return nil, errs.WithEF(nil, r.logData.WithField("commit", commitHash), "Invalid commit hash")
	}

	commit, err := r.Repo.CommitObject(hex)
	if err != nil {
		return nil, errs.WithEF(err, r.logData.WithField("commit", commitHash), "Failed to get commit object")
	}

	parentIter := commit.Parents()
	parent, err := parentIter.Next()
	if err != nil && err != io.EOF {
		return nil, errs.WithEF(err, r.logData.WithField("commit", commitHash), "Failed to get parent commit")
	}

	var patch *object.Patch
	if parent != nil {
		patch, err = parent.Patch(commit)
	} else {
		// Initial commit; diff against empty tree
		emptyTree := &object.Tree{}
		var tree *object.Tree
		tree, err = commit.Tree()
		if err == nil {
			patch, err = emptyTree.Patch(tree)
		}
	}
	if err != nil {
		return nil, errs.WithEF(err, r.logData.WithField("commit", commitHash), "Failed to compute patch for commit")
	}

	files := make(map[string]ChangeType)
	for _, filePatch := range patch.FilePatches() {
		from, to := filePatch.Files()

		var path string
		ct := ChangeModified

		switch {
		case from == nil && to != nil:
			// Added file
			path = to.Path()
			ct = ChangeAdded
		case from != nil && to == nil:
			// Deleted file
			path = from.Path()
			ct = ChangeDeleted
		case from != nil && to != nil && from.Path() != to.Path():
			// Renamed (or moved) file
			path = to.Path()
			ct = ChangeRenamed
		default:
			// Modified file
			if to != nil {
				path = to.Path()
			} else if from != nil {
				path = from.Path()
			}
		}

		if path == "" {
			continue
		}

		files[path] = ct
	}

	return files, nil
}

func (r Repository) GetCommitsInBranch(branch string) ([]string, error) {
	// Resolve the branch tip
	refName := plumbing.NewBranchReferenceName(branch)
	ref, err := r.Repo.Reference(refName, true)
	if err != nil {
		return nil, errs.WithEF(err, r.logData.WithField("branch", branch), "Failed to get branch reference")
	}

	// Try to find the reference branch (where this branch was created from).
	// Heuristic: prefer "main", then "master". If neither exists, fall back
	// to traversing the full history from the branch tip.
	var baseRef *plumbing.Reference
	for _, b := range mainBranches {
		br := plumbing.NewBranchReferenceName(b)
		rref, e := r.Repo.Reference(br, true)
		if e == nil {
			baseRef = rref
			break
		}
	}

	// Collect commits reachable from the base branch to know where to stop.
	stop := map[plumbing.Hash]struct{}{}
	if baseRef != nil {
		baseIter, err := r.Repo.Log(&git.LogOptions{From: baseRef.Hash()})
		if err != nil {
			return nil, errs.WithEF(err, r.logData.WithField("branch", branch), "Failed to get commits for base branch")
		}
		for {
			c, err := baseIter.Next()
			if err != nil {
				if err == io.EOF {
					break
				}
				baseIter.Close()
				return nil, errs.WithEF(err, r.logData.WithField("branch", branch), "Failed to iterate over base branch commits")
			}
			stop[c.Hash] = struct{}{}
		}
		baseIter.Close()
	}

	logIter, err := r.Repo.Log(&git.LogOptions{From: ref.Hash()})
	if err != nil {
		return nil, errs.WithEF(err, r.logData.WithField("branch", branch), "Failed to get commits for branch")
	}
	defer logIter.Close()

	var commits []string
	for {
		c, err := logIter.Next()
		if err != nil {
			if err == io.EOF {
				break
			}
			return nil, errs.WithEF(err, r.logData.WithField("branch", branch), "Failed to iterate over commits")
		}

		// If we have a base branch and this commit is reachable from it,
		// we reached the common history; stop here.
		if _, ok := stop[c.Hash]; ok {
			break
		}

		commits = append(commits, c.Hash.String())
	}

	return commits, nil
}
