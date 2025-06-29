package bcl

import (
	"embed"
	"github.com/becloudless/becloudless/pkg/app"
)

var BCL Bcl

func init() {
	BCL.App.Name = "bcl"
}

type Bcl struct {
	app.App
}

func (bcl *Bcl) Init(assets embed.FS) error {
	return nil
}
