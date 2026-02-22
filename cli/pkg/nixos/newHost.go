package nixos

import (
	"errors"
	"github.com/charmbracelet/huh"
	"github.com/n0rad/go-erlog/errs"
	"strings"
)

type SystemConfig struct {
	Name string `yaml:"-"`
	Bcl  SystemConfigBcl
}

type SystemConfigBcl struct {
	Boot   SystemConfigBclBoot
	System SystemConfigBclSystem
}

type SystemConfigBclBoot struct {
	Efi bool
}

type SystemConfigBclSystem struct {
	Enable   bool
	Hardware string
	Role     string
	Ids      string
	Devices  []string
}

func newSystemConfig(info SystemInfo) (SystemConfig, error) {
	config := SystemConfig{
		Bcl: SystemConfigBcl{
			Boot: SystemConfigBclBoot{
				Efi: info.EFI,
			},
			System: SystemConfigBclSystem{
				Enable:   true,
				Ids:      "uuid=" + info.MotherboardUuid,
				Hardware: "nuc",
			},
		}}

	form := huh.NewForm(
		huh.NewGroup(
			huh.NewInput().
				Title("Machine name?").
				Value(&config.Name).
				// Validating fields is easy. The form will mark erroneous fields
				// and display error messages accordingly.
				Validate(func(str string) error {
					if strings.ToLower(str) != str {
						return errors.New("Name must be lower")
					}
					return nil
				}),

			huh.NewMultiSelect[string]().
				Title("System disk(s)?").
				Description("Selecting multiple disks means running with RAID0").
				Options(huh.NewOptions(info.Disks...)...).
				Validate(func(i []string) error {
					if len(i) < 1 {
						return errors.New("A disk is mandatory")
					}
					return nil
				}).
				Value(&config.Bcl.System.Devices),

			huh.NewSelect[string]().
				Title("Role?").
				Options(
					huh.NewOption("Laptop", "laptop").Selected(true),
					huh.NewOption("Media", "media"),
					huh.NewOption("Server", "server"),
					huh.NewOption("Point of presence", "pop"),
				).
				Value(&config.Bcl.System.Role),
		),
	)

	if err := form.Run(); err != nil {
		return config, errs.WithE(err, "Failed to prepare system")
	}

	return config, nil
}
