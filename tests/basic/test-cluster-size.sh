#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/repository/nixos"

echo "Testing etcd cluster size computation..."
echo ""

# Test that both systems have clusterSize = 2
echo "Checking test-srv11 clusterSize..."
clusterSize11=$(nix eval .#nixosConfigurations.test-srv11.config.bcl.role.serverKube.clusterSize 2>/dev/null || echo "failed")
echo "  test-srv11 clusterSize: $clusterSize11"

echo "Checking test-srv12 clusterSize..."
clusterSize12=$(nix eval .#nixosConfigurations.test-srv12.config.bcl.role.serverKube.clusterSize 2>/dev/null || echo "failed")
echo "  test-srv12 clusterSize: $clusterSize12"

# Validate both are 2
if [ "$clusterSize11" = "2" ] && [ "$clusterSize12" = "2" ]; then
    echo ""
    echo "✓ SUCCESS: Both systems have clusterSize = 2"
    exit 0
else
    echo ""
    echo "✗ FAILURE: Expected clusterSize = 2 for both systems"
    exit 1
fi

