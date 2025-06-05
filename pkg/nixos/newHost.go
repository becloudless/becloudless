package nixos

import (
	"errors"
	"github.com/charmbracelet/huh"
	"github.com/n0rad/go-erlog/errs"
	"strings"
)

type NixosConfigBclSystem struct {
	Name     string `yaml:"-"`
	Enable   bool
	Hardware string
	Role     string
	Ids      string
	Devices  []string
}

func newHost(info SystemInfo) (*NixosConfigBclSystem, error) {
	system := NixosConfigBclSystem{
		Enable:   true,
		Ids:      "uuid=" + info.MotherboardUuid,
		Hardware: "nuc",
	}

	form := huh.NewForm(
		huh.NewGroup(
			huh.NewInput().
				Title("Machine name?").
				Value(&system.Name).
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
				Value(&system.Devices),

			huh.NewSelect[string]().
				Title("Role?").
				Options(
					huh.NewOption("Laptop", "laptop").Selected(true),
					huh.NewOption("Media", "media"),
					huh.NewOption("Server", "server"),
					huh.NewOption("Point of presence", "pop"),
				).
				Value(&system.Role),
		),
	)

	if err := form.Run(); err != nil {
		return nil, errs.WithE(err, "Failed to prepare system")
	}

	return &system, nil
}
