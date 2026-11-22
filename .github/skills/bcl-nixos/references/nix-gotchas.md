# Nix gotchas

## coercedTo and submodules

`lib.types.coercedTo from coerce final` requires `from` not to be (or contain) a submodule, nested `coercedTo` included. Nesting where the inner `final` is a submodule fails at eval with `coercedTo: coercedType must not have submodules`.

Workaround for "accept one item or a list of items" (item = string or submodule): do not use `coercedTo` for the single/list wrapping. Use `lib.types.either itemType (lib.types.listOf itemType)` with `itemType = lib.types.either lib.types.str submoduleType`, and normalise with `apply = d: map normalize (if builtins.isList d then d else [ d ]);`.

## Indented strings (`''...''`)

- `${` interpolates. Escape a literal `$` with `''$`.
- `''` is special. A literal `''` is written `'''`.
- The parser is greedy left to right: three `'` in a row are always the `'''` escape, never "one quote + `''$`". So `'''${var}'` does NOT produce a quoted escaped `${var}`; it ends in a real nix interpolation and fails with "undefined variable".
- To put a single literal quote next to other escapes use `''\'`.
- For shell `${...}` (bash/mpv property expansion) avoid single quotes in bash: write `\''${name}` (nix escapes the dollar, bash `\$` keeps it literal). In a bash `$(( ... ))` or `${x##*/}` inside a nix string, write `''${x##*/}`.

## Duplicate option declaration

"option X is already declared in <path>": a file with real `options.*` loaded twice (see the module loading rule in the skill). Files with only `config` blocks merge silently, which hides the double import.

## Store corruption

Symptoms: `error parsing derivation '/nix/store/..drv': file is empty (possible filesystem corruption)`, or a flake input whose `flake.nix` is empty.

- Flake input: as root `nix flake metadata 'github:OWNER/REPO/REV' --refresh` gives the `Path:`; `wc -l <path>/flake.nix` = 0 and `nix-store --verify-path <path>` ("was modified!") confirm local corruption. Check `dmesg -T | grep -i corrupt` for an unclean shutdown.
- Fix: `sudo nix-store --gc` (not `--delete <path>`: "still alive" because of temporary roots). Then re-run the deploy.
- Empty `.drv` files: `nix-store --delete --ignore-liveness` is refused; `nix-store --gc --option keep-derivations false` drops all `.drv`, regenerated on next eval. `--repair` cannot fix `.drv`. Empty non-`.drv` files can be legitimate; empty `.drv` never are.
- `bcl nix up` has this recovery built in (captures the error, gc, retries, `--verify --check-contents --repair`), but the host runs a pinned released CLI: it only reaches hosts after a release.

## flake-utils-plus `pkgs` and bclOverrides

`self.pkgs.<system>` is resolved from the outer flake's fixpoint, not from the `mkFlake` that built the host. `bclOverrides` must merge each override's own `pkgs` into the wrapper output or overlays only present in the override input are invisible ("<pkg> cannot be found in pkgs"). The fix lives in the `mkFlake` wrapper, so it only helps consumers whose `bcl` input (not just the override input) points at code that has it.

## Misc

- `systemd` scripts written in nix: `path = [ pkgs.x ];` puts tools on PATH; a `script` with a `for` over `/dev/cpu/[0-9]*` and `$(( 0x$v & ~1 ))` works in `sh`.
- `hardware.graphics.extraPackages` carries VA-API drivers; `intel-vaapi-driver` is the i965 driver for pre-Broadwell Intel.
