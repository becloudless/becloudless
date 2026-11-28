package kube

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"

	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/go-erlog/logs"
	"github.com/spf13/cobra"

	"github.com/becloudless/becloudless/pkg/kube"
)

const (
	longhornNamespace     = "longhorn-system"
	longhornNodeResource  = "nodes.longhorn.io"
	longhornReplicaKind   = "replicas.longhorn.io"
	nodeRemovePollPeriod  = 10 * time.Second
	longhornNodeDeleteTry = 2 * time.Minute
)

type nodeRemoveOptions struct {
	nodeName        string
	evictionTimeout time.Duration
	drainTimeout    time.Duration
	shutdownTimeout time.Duration
	isConfirmed     bool
}

func kubeNodesRemoveCmd() *cobra.Command {
	options := nodeRemoveOptions{}

	cmd := cobra.Command{
		Use:     "remove <node>",
		Aliases: []string{"rm"},
		Short:   "Move the Longhorn replicas of a node away, drain it, wait for its shutdown and delete it from the cluster",
		Long: `Remove a worker node that will never come back.

1. evict the Longhorn replicas of the node (they are rebuilt on the other nodes) and stop scheduling on it
2. cordon and drain the node
3. wait for the node to be powered off (the kubelet would register the node again if it was deleted while running)
4. delete the Longhorn node and the kubernetes node

The control-plane nodes are refused: lower masterNodeCount of the NixOS role instead.`,
		Args: cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			options.nodeName = args[0]

			ctx, err := kube.GetContext(".")
			if err != nil {
				return errs.WithE(err, "Cannot find kube cluster context. Are you in a cluster folder?")
			}
			if ctx.KubeConfig == "" {
				return errs.With("Not in a cluster folder (kube/clusters/<cluster>)")
			}
			if _, err := os.Stat(ctx.KubeConfig); err != nil {
				return errs.WithEF(err, data.WithField("kubeconfig", ctx.KubeConfig), "The kubeconfig of the cluster does not exist")
			}
			return removeNode(ctx, options)
		},
	}

	cmd.Flags().DurationVar(&options.evictionTimeout, "eviction-timeout", time.Hour, "Maximum time to wait for the Longhorn replicas to be moved away")
	cmd.Flags().DurationVar(&options.drainTimeout, "drain-timeout", 15*time.Minute, "Maximum time of the drain")
	cmd.Flags().DurationVar(&options.shutdownTimeout, "shutdown-timeout", 30*time.Minute, "Maximum time to wait for the node to be powered off")
	cmd.Flags().BoolVarP(&options.isConfirmed, "yes", "y", false, "Do the removal, without it only the plan is shown")

	return &cmd
}

func removeNode(ctx kube.Context, options nodeRemoveOptions) error {
	fields := data.WithField("node", options.nodeName)

	if err := checkNodeIsRemovable(ctx, options.nodeName); err != nil {
		return err
	}

	hasLonghornNode, err := longhornNodeExists(ctx, options.nodeName)
	if err != nil {
		return err
	}

	logs.WithFields(fields).WithField("longhorn", hasLonghornNode).Info("Plan: evict the Longhorn replicas, drain, wait for the shutdown, delete the nodes")
	if !options.isConfirmed {
		logs.WithFields(fields).Warn("Nothing done, run again with --yes to remove the node")
		return nil
	}

	if hasLonghornNode {
		if err := evictLonghornReplicas(ctx, options); err != nil {
			return err
		}
	}

	logs.WithFields(fields).Info("Draining the node")
	if err := streamKubectl(ctx, "drain", options.nodeName, "--ignore-daemonsets", "--delete-emptydir-data", "--timeout="+options.drainTimeout.String()); err != nil {
		return errs.WithEF(err, fields, "Failed to drain the node")
	}

	logs.WithFields(fields).Info("Waiting for the node to be powered off")
	err = waitUntil(options.shutdownTimeout, nodeRemovePollPeriod, func() (bool, error) {
		readyStatus, err := kubectlOutput(ctx, "get", "node", options.nodeName, "-o", `jsonpath={.status.conditions[?(@.type=="Ready")].status}`)
		return readyStatus != "True", err
	})
	if err != nil {
		return errs.WithEF(err, fields, "The node is still running, power it off then run the command again")
	}

	if hasLonghornNode {
		logs.WithFields(fields).Info("Deleting the Longhorn node")
		err = waitUntil(longhornNodeDeleteTry, nodeRemovePollPeriod, func() (bool, error) {
			_, err := kubectlOutput(ctx, "-n", longhornNamespace, "delete", longhornNodeResource, options.nodeName, "--ignore-not-found")
			return err == nil, nil
		})
		if err != nil {
			return errs.WithEF(err, fields, "Failed to delete the Longhorn node")
		}
	}

	logs.WithFields(fields).Info("Deleting the kubernetes node")
	if _, err := kubectlOutput(ctx, "delete", "node", options.nodeName); err != nil {
		return errs.WithEF(err, fields, "Failed to delete the kubernetes node")
	}

	logs.WithFields(fields).Info("Node removed")
	return nil
}

func checkNodeIsRemovable(ctx kube.Context, nodeName string) error {
	fields := data.WithField("node", nodeName)

	if _, err := kubectlOutput(ctx, "get", "node", nodeName, "-o", "name"); err != nil {
		return errs.WithEF(err, fields, "The node does not exist")
	}

	controlPlaneNode, err := kubectlOutput(ctx, "get", "node", "-l", "node-role.kubernetes.io/control-plane", "--field-selector", "metadata.name="+nodeName, "-o", "name")
	if err != nil {
		return err
	}
	if controlPlaneNode != "" {
		return errs.WithF(fields, "The node is a control-plane node, lower masterNodeCount of the NixOS role instead")
	}
	return nil
}

func longhornNodeExists(ctx kube.Context, nodeName string) (bool, error) {
	longhornCrd, err := kubectlOutput(ctx, "get", "crd", longhornNodeResource, "-o", "name", "--ignore-not-found")
	if err != nil || longhornCrd == "" {
		return false, err
	}
	longhornNode, err := kubectlOutput(ctx, "-n", longhornNamespace, "get", longhornNodeResource, nodeName, "-o", "name", "--ignore-not-found")
	return longhornNode != "", err
}

// evictLonghornReplicas gives the node back to the scheduling if the eviction fails.
func evictLonghornReplicas(ctx kube.Context, options nodeRemoveOptions) error {
	fields := data.WithField("node", options.nodeName)

	logs.WithFields(fields).Info("Evicting the Longhorn replicas")
	if _, err := kubectlOutput(ctx, "-n", longhornNamespace, "patch", longhornNodeResource, options.nodeName, "--type", "merge",
		"-p", `{"spec":{"allowScheduling":false,"evictionRequested":true}}`); err != nil {
		return errs.WithEF(err, fields, "Failed to request the eviction of the Longhorn node")
	}

	previousReplicaCount := -1
	err := waitUntil(options.evictionTimeout, nodeRemovePollPeriod, func() (bool, error) {
		replicaNames, err := longhornReplicasOnNode(ctx, options.nodeName)
		if err != nil {
			return false, err
		}
		if len(replicaNames) != previousReplicaCount {
			logs.WithFields(fields).WithField("replicas", len(replicaNames)).Info("Longhorn replicas left on the node")
			previousReplicaCount = len(replicaNames)
		}
		return len(replicaNames) == 0, nil
	})
	if err != nil {
		if _, revertErr := kubectlOutput(ctx, "-n", longhornNamespace, "patch", longhornNodeResource, options.nodeName, "--type", "merge",
			"-p", `{"spec":{"allowScheduling":true,"evictionRequested":false}}`); revertErr != nil {
			logs.WithEF(revertErr, fields).Warn("Failed to cancel the eviction of the Longhorn node")
		}
		return errs.WithEF(err, fields, "The Longhorn replicas were not moved away, the eviction is cancelled")
	}
	return nil
}

func longhornReplicasOnNode(ctx kube.Context, nodeName string) ([]string, error) {
	replicaNames, err := kubectlOutput(ctx, "-n", longhornNamespace, "get", longhornReplicaKind,
		"-o", fmt.Sprintf(`jsonpath={.items[?(@.spec.nodeID==%q)].metadata.name}`, nodeName))
	return strings.Fields(replicaNames), err
}

func waitUntil(timeout time.Duration, pollPeriod time.Duration, isDone func() (bool, error)) error {
	deadline := time.Now().Add(timeout)
	for {
		done, err := isDone()
		if err != nil {
			return err
		}
		if done {
			return nil
		}
		if time.Now().After(deadline) {
			return errs.WithF(data.WithField("timeout", timeout), "Timeout reached")
		}
		time.Sleep(pollPeriod)
	}
}

func kubectlOutput(ctx kube.Context, arguments ...string) (string, error) {
	cmd := exec.Command("kubectl", arguments...)
	cmd.Env = append(os.Environ(), fmt.Sprintf("KUBECONFIG=%s", ctx.KubeConfig))
	output, err := cmd.Output()
	if err != nil {
		fields := data.WithField("arguments", arguments)
		var exitError *exec.ExitError
		if errors.As(err, &exitError) {
			fields = fields.WithField("stderr", strings.TrimSpace(string(exitError.Stderr)))
		}
		return "", errs.WithEF(err, fields, "kubectl failed")
	}
	return strings.TrimSpace(string(output)), nil
}

func streamKubectl(ctx kube.Context, arguments ...string) error {
	cmd := exec.Command("kubectl", arguments...)
	cmd.Env = append(os.Environ(), fmt.Sprintf("KUBECONFIG=%s", ctx.KubeConfig))
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}
