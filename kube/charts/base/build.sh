#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# the chart is its own go module and the build works on the current directory
cd "$DIR"
go run ./build.go
