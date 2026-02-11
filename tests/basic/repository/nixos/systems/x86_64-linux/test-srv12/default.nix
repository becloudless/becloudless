{ inputs, ... }: inputs.yaml.lib.fromYaml ./default.yaml // { facter.reportPath = ./facter.json; }

