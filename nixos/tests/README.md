
```bash
export SOPS_AGE_KEY_FILE=./tests/basic/secrets/age
sops --config tests/basic/repository/.sops.yaml edit tests/basic/repository/nixos/modules/nixos/global/default.secrets.yaml
```