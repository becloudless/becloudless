package bcl

import (
	"embed"
	"github.com/becloudless/becloudless/pkg/app"
)

// BCL is the global app instance
var BCL Bcl

func init() {
	BCL.App.Name = "bcl"
}

type Bcl struct {
	app.App
}

func (bcl *Bcl) Init(assets embed.FS) error {
	if err := bcl.PrepareHome(); err != nil {
		return err
	}
	return nil
}
