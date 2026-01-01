package nixos

import (
	"fmt"
	"github.com/becloudless/becloudless/pkg/generated/schema"
	"github.com/charmbracelet/huh"
	"github.com/spf13/cobra"
	"reflect"
	"strings"
)

func nixosGlobalEditCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "edit",
		Short: "Edit global",
		RunE: func(cmd *cobra.Command, args []string) error {
			global := schema.Global{}
			_ = global.UnmarshalJSON([]byte{'{', '}'})

			huhFields := []huh.Field{}

			xv := reflect.ValueOf(&global).Elem() // Dereference into addressable value
			xt := xv.Type()

			for i := 0; i < xt.NumField(); i++ {
				f := xt.Field(i)
				name := strings.ToLower(f.Name)
				addr := xv.Field(i).Addr().Interface()

				switch ptr := addr.(type) {
				case *string:
					huhFields = append(huhFields,
						huh.NewInput().
							Title(name).
							Value(ptr))
				}
			}

			form := huh.NewForm(huh.NewGroup(huhFields...))
			if err := form.Run(); err != nil {
				return err
			}
			fmt.Println(global)
			return nil
		},
	}
	return cmd
}
