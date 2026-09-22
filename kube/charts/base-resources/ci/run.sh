#!/usr/bin/env bash
#
# Renders each ci/<case>-values.yaml through the chart (via a temporary
# wrapper chart, since this is a Helm library chart and can't be
# `helm template`'d on its own) and diffs the output against the matching
# ci/<case>-result.yaml golden file.
#
# Usage:
#   ./ci/run.sh          # check all cases against their golden files
#   ./ci/run.sh --update # regenerate the golden files instead of checking
set -euo pipefail

chart_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ci_dir="$chart_dir/ci"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/charts" "$tmp/templates"
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
rm -rf "$tmp/charts/base-resources/ci" "$tmp/charts/base-resources/generate"

(cd "$tmp" && helm dependency update . > /dev/null)

update=false
if [[ "${1:-}" == "--update" ]]; then
  update=true
fi

fail=0
for values in "$ci_dir"/*-values.yaml; do
  case_name="$(basename "$values" -values.yaml)"
  result="$ci_dir/${case_name}-result.yaml"

  actual="$(cd "$tmp" && helm template test-release . -f charts/base-resources/values.yaml -f "$values" --show-only templates/loader.yaml)"

  if $update; then
    printf '%s\n' "$actual" > "$result"
    echo "UPDATED $case_name"
    continue
  fi

  if [[ ! -f "$result" ]]; then
    echo "FAIL $case_name: missing golden file $result (run with --update to create it)"
    fail=1
    continue
  fi

  if diff -u "$result" <(printf '%s\n' "$actual"); then
    echo "PASS $case_name"
  else
    echo "FAIL $case_name"
    fail=1
  fi
done

exit $fail
