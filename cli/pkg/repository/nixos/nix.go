package nixos

import (
	"regexp"
	"strings"
)

var namePattern = regexp.MustCompile(`^[a-z0-9]([a-z0-9-]*[a-z0-9])?$`)

func nixString(value string) string {
	escaped := strings.NewReplacer(`\`, `\\`, `"`, `\"`, "${", `\${`).Replace(value)
	return `"` + escaped + `"`
}

func nixStringList(values []string) string {
	quotedValues := make([]string, len(values))
	for i, value := range values {
		quotedValues[i] = nixString(value)
	}
	return "[ " + strings.Join(quotedValues, " ") + " ]"
}
