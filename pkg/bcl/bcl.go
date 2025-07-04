package bcl

import (
	"github.com/becloudless/becloudless/pkg/bcl/app"
)

// BCL is the global app instance
var BCL Bcl

func init() {
	BCL.App.Name = "bcl"
}

type Bcl struct {
	app.App
}

func (bcl *Bcl) Init(home string) error {
	bcl.Home = home
	if err := bcl.PrepareHome(); err != nil {
		return err
	}

	// TODO THINGS

	return nil
}
