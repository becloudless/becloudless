# Test Systems for Etcd Cluster Size Validation

This directory contains test systems to validate the dynamic etcd cluster configuration based on `clusterSize`.

## Test Systems

### test-srv11 and test-srv12

Two server systems configured with the `serverKube` role to test etcd cluster formation.

**Configuration:**
- **Group**: `test-server`
- **Role**: `serverKube`
- **Cluster Name**: `test`
- **Cluster Number**: `1`
- **Cluster Size**: `2` (manually configured in group settings)

**Expected Behavior:**

The etcd `initial-cluster` line should be dynamically generated as:
```
srv11=https://192.168.41.11:2380,srv12=https://192.168.41.12:2380
```

This is computed using:
```nix
lib.concatMapStringsSep "," 
  (n: "srv${clusterNumber}${n}=https://192.168.41.${clusterNumber}${n}:2380") 
  (lib.genList (n: n + 1) clusterSize)
```

With `clusterNumber = 1` and `clusterSize = 2`, this generates the cluster line with both nodes.

## Running Tests

Execute the test script to validate the configuration:

```bash
cd tests/basic
./test-etcd-cluster.sh
```

This will verify:
1. Both systems have `clusterSize = 2`
2. The etcd configuration is properly generated
3. NixOS configurations are valid

## Files Structure

```
tests/basic/repository/nixos/
├── modules/nixos/groups/test-server/
│   ├── default.nix              # Group configuration with serverKube role
│   └── default.secrets.yaml      # SOPS encrypted secrets
└── systems/x86_64-linux/
    ├── test-srv11/
    │   ├── default.nix          # System entry point
    │   ├── default.yaml         # System configuration
    │   └── facter.json          # Hardware facts
    └── test-srv12/
        ├── default.nix          # System entry point
        ├── default.yaml         # System configuration
        └── facter.json          # Hardware facts
```

## CI Integration

These test systems are automatically included in `nix flake check` and will validate that:
- The etcd cluster configuration syntax is correct
- All required options are properly set
- The dynamic cluster line generation works as expected

