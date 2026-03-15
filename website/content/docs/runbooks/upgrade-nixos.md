+++
title = "Upgrade NixOS"
weight = 30
description = "Updating the flake lockfile and deploying NixOS updates"
+++

## When to Use

- Applying security patches to one or more machines
- Updating the flake lockfile to get newer packages
- Upgrading the NixOS channel version

---

## Step 1 — Update the Flake Lockfile

From the repository root:

```bash
nix flake update
```

To update only a specific input (e.g., nixpkgs):

```bash
nix flake update nixpkgs
```

Review the diff:

```bash
git diff flake.lock
```

---

## Step 2 — Build and Validate

Test the build for a specific machine without deploying:

```bash
nixos-rebuild dry-build --flake .#<hostname>
```

Check for evaluation errors or broken packages before proceeding.

---

## Step 3 — Deploy

### Single Machine

```bash
bcl nixos deploy <hostname>
```

Or directly with nixos-rebuild:

```bash
nixos-rebuild switch --flake .#<hostname> --target-host root@<hostname>
```

### All Machines (sequential)

```bash
for host in host1 host2 host3; do
  echo "Deploying to $host..."
  bcl nixos deploy $host
done
```

---

## Step 4 — Commit the Updated Lockfile

```bash
git add flake.lock
git commit -m "chore(nixos): update flake inputs $(date +%Y-%m-%d)"
git push
```

---

## Rollback

If a deployment causes issues, roll back to the previous generation:

```bash
ssh root@<hostname> nixos-rebuild --rollback switch
```

Or boot into a previous generation from the bootloader menu.

