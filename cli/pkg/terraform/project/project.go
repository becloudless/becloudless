package project

import (
	"os"
	"regexp"
	"strings"

	"github.com/hashicorp/go-version"
	"github.com/hashicorp/terraform-config-inspect/tfconfig"
	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
)

func GetProjectTerraformVersion(projectPath string) (*version.Version, error) {
	module, diags := tfconfig.LoadModule(projectPath)
	if diags.HasErrors() {
		return nil, errs.WithE(diags.Err(), "Failed to load module")
	}

	if len(module.RequiredCore) != 1 {
		return nil, errs.WithF(data.WithField("len", len(module.RequiredCore)), "requiredCore not found")
	}
	requiredVersionSetting := module.RequiredCore[0]

	// We allow `= x.y.z`, `=x.y.z` or `x.y.z` where `x`, `y` and `z` are integers.
	re := regexp.MustCompile(`^=?\s*([^\s]+)\s*$`)
	matched := re.FindStringSubmatch(requiredVersionSetting)
	if len(matched) == 0 {
		return nil, errs.WithF(data.WithField("path", projectPath).WithField("version", requiredVersionSetting), "Invalid version")

	}
	version, err := version.NewVersion(matched[1])
	if err != nil {
		return nil, errs.WithEF(err, data.WithField("version", matched[1]), "Failed to parse version")
	}

	return version, nil
}

func IsTerraformProjectFolder(path string) bool {
	items, _ := os.ReadDir(path)
	for _, item := range items {
		if !item.IsDir() && strings.HasSuffix(item.Name(), ".tf") {
			return true
		}
	}
	return false
}
