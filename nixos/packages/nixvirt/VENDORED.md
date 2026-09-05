# Vendored NixVirt

These files (`generate-xml/`, `templates/`, `tool/`, `guest-install.nix`,
`lib.nix`, `modules.nix`, `LICENSE`) are copied byte-for-byte from
[AshleyYakeley/NixVirt](https://github.com/AshleyYakeley/NixVirt) v0.6.0
(commit `5dfe108fd859b122f9a96981cb6bc12297653d6c`), MIT licensed (see
`LICENSE`).

## Why vendored instead of used as a flake input

NixVirt's own `flake.nix` hardcodes:

```nix
packages = import nixpkgs { system = "x86_64-linux"; };
```

for the entire flake, including the Python helper scripts
(`nixvirt-module-helper`, `virtdeclare`) and the default `libvirt` package
used by its NixOS module. This means every host using
`nixvirt.nixosModules.default` — regardless of its own architecture — pulls
in x86_64-linux derivations for these pieces. On a non-x86_64-linux host
(e.g. aarch64 orangepi boards used for `bcl.role.serverVirt`), this requires
`boot.binfmt.emulatedSystems = ["x86_64-linux"]` (QEMU user-mode emulation)
just to build/rebuild the system, and still needs an x86_64 machine to
bootstrap the very first deploy (the target can't cross-build its own binfmt
fix before binfmt itself is registered).

The files copied here (`modules.nix`, `lib.nix`, `guest-install.nix`,
`generate-xml/*.nix`, `templates/*.nix`, `tool/*`) are all already
architecture-agnostic — they take `packages` (a nixpkgs instance) as a plain
function argument rather than assuming any particular system. Only NixVirt's
own `flake.nix` glue code hardcodes `x86_64-linux` when constructing that
`packages` argument. By vendoring the arch-agnostic files and instantiating
them ourselves with the *host's own* `pkgs` (see
`../../modules/nixos/bcl/nixvirt.nix`), every host builds fully native
derivations for libvirtd, its Python helper scripts, and VM templates — no
binfmt emulation or cross-arch bootstrap needed on any architecture.

## Updating

To pick up a newer NixVirt release, replace these files with the
corresponding ones from the new tag/commit (same list as above), and update
the version/commit noted here. Check the upstream `CHANGELOG.md` for any
interface changes to `lib.nix`/`modules.nix` that might require corresponding
changes to `../../modules/nixos/bcl/nixvirt.nix` or
`../../modules/nixos/bcl/role/serverVirtVms.nix`.
