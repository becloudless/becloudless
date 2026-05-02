package terraform

import (
	"github.com/becloudless/becloudless/pkg/terraform"
	"github.com/becloudless/becloudless/pkg/terraform/project"
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/go-erlog/logs"
	"github.com/spf13/cobra"
)

func terraformApplyCmd() *cobra.Command {
	var path string
	cmd := &cobra.Command{
		Use:   "apply",
		Short: "Run apply on the path",
		Long:  "Run apply on the path fetching the right terraform version",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			if !project.IsTerraformProjectFolder(path) {
				logs.WithField("path", path).Warn("no terraform files found")
				return nil
			}

			tfVersion, err := project.GetProjectTerraformVersion(path)
			if err != nil {
				return errs.With("Cannot find a terraform version in the project").WithErr(err).WithField("path", path)
			}

			terraformClient, err := terraform.NewClient(tfVersion)
			if err != nil {
				return errs.WithE(err, "Failed to create terraform client")
			}
			defer terraformClient.Close()

			if err := terraformClient.RunInit(path); err != nil {
				return errs.WithE(err, "terraform init failed")
			}

			if err := terraformClient.RunApply(path); err != nil {
				logs.WithE(err).Warn("Failed")
			}
			return nil
		},
	}

	cmd.Flags().StringVar(&path, "chdir", ".", "terraform project path")

	return cmd
}
