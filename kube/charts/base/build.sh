#!/usr/bin/env bash
set -euo pipefail

PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

go run $PATH/build.go
