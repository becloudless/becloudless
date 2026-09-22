#!/usr/bin/env bash
#
# Runs the helm-unittest suites in tests/*_test.yaml against this chart.
#
# This is a Helm library chart, so it can't be unit-tested directly (helm
# unittest run here fails every suite with "template ... not exists or not
# selected in test suite"). Instead, build a temporary wrapper chart that
# depends on this one (same pattern as ci/run.sh) and run helm-unittest from
# there, with the suites copied into the wrapper's own tests/ dir.
#
# Requires the helm-unittest plugin: helm plugin install https://github.com/helm-unittest/helm-unittest
#
# Usage:
#   ./tests/run.sh
set -euo pipefail

chart_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tests_dir="$chart_dir/tests"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/charts" "$tmp/templates" "$tmp/tests"
cat > "$tmp/Chart.yaml" <<EOF
apiVersion: v2
name: resources-test
version: 0.0.0
dependencies:
  - name: base-resources
    version: "0.0.0"
    repository: "file://charts/base-resources"
EOF
cat > "$tmp/templates/loader.yaml" <<'EOF'
{{ include "resources.loader.all" . }}
EOF
: > "$tmp/values.yaml"

cp -r "$chart_dir" "$tmp/charts/base-resources"
rm -rf "$tmp/charts/base-resources/ci" "$tmp/charts/base-resources/generate" "$tmp/charts/base-resources/tests"
cp "$tests_dir"/*_test.yaml "$tmp/tests/"

(cd "$tmp" && helm dependency update . > /dev/null)
(cd "$tmp" && helm unittest .)
