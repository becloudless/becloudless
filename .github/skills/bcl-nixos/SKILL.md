---
name: bcl-nixos
description: "Use when: editing or deploying NixOS modules, roles, hardware device modules or systems in becloudless or in a flake that consumes it (mkFlake, snowfall-lib, bcl.* options); evaluating a host config locally, testing local bcl edits from a consumer repo with --override-input, deploying with `bcl nix up`, fixing Nix errors (coercedTo submodules, indented string escaping, duplicate option declarations, missing lib function), corrupted nix store, wifi/sops/boot/plymouth modules."
---

# NixOS in bcl

Read [bcl-agent-workflow](../bcl-agent-workflow/SKILL.md) first (no commit, no deploy unless asked).
Nix pitfalls with full explanations: [references/nix-gotchas.md](./references/nix-gotchas.md).

## Layout

- `nixos/modules/nixos/bcl/**`: options and config under `bcl.*` (`bcl.hardware.device`, `bcl.hardware.commons`, `bcl.role`, `bcl.boot`, `bcl.wifi`, `bcl.global`, ...). `role/*.nix` are roles, `hardware/devices/*.nix` are device modules, `global.nix` + `global.schema.json` the shared config.
- `nixos/systems/<arch>/<host>` hosts, `nixos/packages`, `nixos/overlays`, `nixos/flake.nix` exposes `mkFlake`.
- A consumer repo calls `inputs.bcl.mkFlake { inherit inputs; src = ./.; snowfall.namespace = "<ns>"; ... }` and adds its own modules/hosts. `bclOverrides = { <host> = <otherInput>; }` builds a host from another bcl input.
- Docs: `website/content/docs/nixos/*.md` (adding a system, roles, global config, hardware).

## Module loading rule (important)

`modules/nixos/bcl/default.nix` imports every `.nix` file under `bcl/` recursively. snowfall-lib also exposes every folder that has its own `default.nix` as a separate namespaced module. So a nested file named `default.nix` is loaded twice and options declared in it fail with "option ... is already declared". Never name a nested file `default.nix` (only the top one); name it after its role (e.g. `role/role.nix`). Do not "fix" it by filtering `default.nix` out of the loader: downstream flakes only import the single top-level module and would lose the options.

Check: `cd nixos && nix flake check --show-trace`.

## Evaluate locally

From a consumer repo, test uncommitted bcl edits (consumers pin bcl to a branch/ref, plain `nix eval` ignores your working tree):

```bash
cd <consumer>/nixos
nix eval '.#nixosConfigurations.<host>.config.<attr>' --json \
  --override-input bcl 'path:<abs path to becloudless>/nixos' 2>&1 | tail -5
```

- `--override-input` only works with the flake attribute syntax (`.#attr`), not `--impure --expr getFlake`. The "not writing modified lock file" warning is expected and nothing is written.
- Use `--apply 'c: { ... }'` to print several values at once. Output includes harmless evaluation warnings (e.g. disko legacy table): filter with `tail`.
- Smoke-test any non trivial new `lib.*` helper this way: the pinned nixpkgs can be older than a local nixpkgs checkout (`lib.findFirstIndex` was missing). Prefer long-standing helpers (`splitString`, `hasPrefix`, `filterAttrs`, `mapAttrsToList`).
- To prove a code path is evaluated, plant `throw "CANARY"` (not `builtins.trace`, which may not force evaluation).
- To read the real pinned source of a flake input: `nix eval --raw --expr '(builtins.getFlake "<ref>").inputs.<x>.outPath'`, then grep it.
- `eval` proves the module evaluates, not that it works on the machine: say which one you verified.

## Deploy with the CLI

`bcl nix up` (aliases `upgrade`, `update`) wraps `nixos-rebuild`.

| Flag | Meaning |
|------|---------|
| (none) | local host from upstream git repo |
| `--git` | use the local git working tree instead of upstream |
| `-h <host>` (+ `-u`, `-p`, `-i`) | remote host over ssh |
| `--ask-sudo-password` | remote host whose sudo needs a password (with `--git -h`) |
| `-a switch\|boot\|test\|build\|reboot` | nixos-rebuild action (`boot` = next boot only) |
| `-n <name>` | system name to apply (renames) |
| `--input name=value` | override a flake input (needs `--git`) |

Deploying is done by the maintainer, not the agent. After a deploy, verify on the host: `readlink /run/current-system`, `uptime`, `systemctl is-active <unit>`, and the effective setting. Environment variables from `environment.sessionVariables` only reach new login sessions; a kernel module blacklist or `boot.kernelModules` change needs a reboot.

Known deploy failures:
- `lacks a signature by a trusted key` on a remote `--git` deploy of a host still on an old generation: bootstrap issue; run `bcl nix up --git` locally on that host once.
- Flake eval `syntax error, unexpected end of file` at `«github:.../<rev>»/flake.nix:1:1`, or `error parsing derivation ... file is empty`: corrupted store paths (often after an unclean shutdown). See [store repair](./references/nix-gotchas.md#store-corruption).
- `sops-install-secrets` is built on the host: it is in no binary cache, expected.
- A `nixos-rebuild --target-host` that prints "Done." may not have changed the generation: scan the whole output for `nix-copy-closure ... non-zero` / `lacks a signature by a trusted key` and confirm with `readlink -f /nix/var/nix/profiles/system` on the target (the global role sets `nix.settings.trusted-users = [ "root" "@wheel" ]` so the deploying user can copy unsigned closures).

Related: VM hosts, LVM, NixVirt, libvirt: [bcl-virtualization](../bcl-virtualization/SKILL.md). TV kiosk and Miracast: [bcl-tv-role](../bcl-tv-role/SKILL.md).

## Patterns that came up

- Hardware device module: gate with `lib.mkIf (config.bcl.hardware.device == "<name>")`, set `bcl.hardware.commons` (e.g. `intel`), boot loader, kernel modules, graphics packages, udev rules, and register the name in `bcl.hardware.knownDevices`. See `website/content/docs/hardware/adding-hardware.md`.
- Wifi: `bcl.wifi` reads SSIDs from the keys of the sops global secret file (`networking.wireless.<ssid>.password`, keys are plaintext even when values are encrypted) and generates NetworkManager profiles. SSIDs may contain dots: the key parser must not split on `.`. Add the same extraction fix to every module that parses these keys. A new SSID needs a new key in the encrypted secret file (the maintainer edits it with sops).
- Boot: GRUB + Plymouth needs `gfxpayload keep` and the GPU module in the initrd (i915 on Intel) or the splash falls back to text. If boot stalls at "Hold until boot process finishes up" (`plymouth-quit-wait`), look at `systemctl list-jobs` on the stuck machine before rebooting.
- Re-applying a setting after suspend: add the service to `wantedBy = [ "multi-user.target" "suspend.target" "hibernate.target" ]` with `after` the same targets.
- Firefox: `programs.firefox.preferences` ends up in `/etc/firefox/policies/policies.json` (check there to verify a deploy).
- Hardware/GPU/perf problems on a physical host: [bcl-host-debugging](../bcl-host-debugging/SKILL.md).
