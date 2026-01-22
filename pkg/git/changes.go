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

func (r Repository) GetBranchLastCommit(branch string) (string, error) {
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

		commit, err := r.GetBranchLastCommit(branch)
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

		if from == nil && to == nil {
			continue
		}

		if from == nil {
			path = to.Path()
			ct = ChangeAdded
		} else if to == nil {
			path = from.Path()
			ct = ChangeDeleted
		} else if from.Path() != to.Path() {
			path = to.Path()
			ct = ChangeRenamed
		} else {
			// Modified file
			path = to.Path()
		}

		if path == "" {
			continue
		}

		files[path] = ct
	}

	return files, nil
}

func (r Repository) GetCommitsInBranch(branch string) ([]string, error) {
	branchHashStr, err := r.GetBranchLastCommit(branch)
	if err != nil {
		return nil, err
	}
	branchHash, ok := plumbing.FromHex(branchHashStr)
	if !ok {
		return nil, errs.WithEF(nil, r.logData.WithField("commit", branchHashStr), "Invalid branch commit hash")
	}

	branchCommit, err := r.Repo.CommitObject(branchHash)
	if err != nil {
		return nil, errs.WithEF(err, r.logData.WithField("commit", branchHashStr), "Failed to get branch commit object")
	}

	var baseCommit *object.Commit
	var baseBranchName string

	for _, b := range mainBranches {
		h, err := r.GetBranchLastCommit(b)
		if err == nil {
			baseHash, ok := plumbing.FromHex(h)
			if ok {
				c, err := r.Repo.CommitObject(baseHash)
				if err == nil {
					baseCommit = c
					baseBranchName = b
					break
				}
			}
		}
	}

	if baseCommit == nil {
		return nil, errs.WithEF(nil, r.logData, "Could not find main or master branch to compare against")
	}

	mergeBases, err := branchCommit.MergeBase(baseCommit)
	if err != nil {
		return nil, errs.WithEF(err, r.logData.WithField("branch", branch).WithField("base", baseBranchName), "Failed to calculate merge base")
	}
	if len(mergeBases) == 0 {
		return nil, errs.WithEF(nil, r.logData, "No common ancestor found")
	}

	mergeBaseHash := mergeBases[0].Hash
	var commits []string

	cIter, err := r.Repo.Log(&git.LogOptions{From: branchHash})
	if err != nil {
		return nil, errs.WithEF(err, r.logData, "Failed to get commit log")
	}

	err = cIter.ForEach(func(c *object.Commit) error {
		if c.Hash == mergeBaseHash {
			return io.EOF
		}
		commits = append(commits, c.Hash.String())
		return nil
	})

	if err != nil && err != io.EOF {
		return nil, errs.WithEF(err, r.logData, "Failed to iterate commits")
	}

	return commits, nil
}
