---
name: bcl-host-debugging
description: "Use when: investigating performance problems, freezes, periodic stutter, video lag, a CPU stuck at low clock, desktop/compositor crashes, GPU/VA-API/codec support, wifi quality or boot stalls on a physical Linux/NixOS host (laptop, mini PC, SBC), over ssh. Measurement recipes: turbostat, MSR registers (PROCHOT), PSI, per-thread sampling, SMM stalls from hwmon drivers, Firefox hardware decoding, no-Vulkan GPUs with COSMIC/iced."
---

# Debugging a physical host

Read [bcl-agent-workflow](../bcl-agent-workflow/SKILL.md) first. Everything below starts read-only over `ssh`; commands needing sudo go through the interactive terminal flow described there (batch them, the user types the password). Fixes belong in the NixOS config ([bcl-nixos](../bcl-nixos/SKILL.md)); a live test is temporary and must be described as such.

## Method

1. Reproduce and timestamp the symptom with the user (how often, what freezes: mouse, video, everything).
2. Establish what is running now: `uptime`, `readlink /run/current-system`, `top -b -n1 -H -o %CPU`, `cat /proc/pressure/{cpu,io,memory}`, `journalctl -b -p warning`, `coredumpctl list`. Compare crash timestamps with the boot/generation time before blaming a config.
3. Sample over time instead of once: a loop printing time, CPU frequency, temperature, load every few seconds; per-thread top (`top -b -d 1 -n 50 -H -o %CPU`) to catch periodic spikes.
4. Change one thing, re-measure, keep the numbers (before/after) for the report.
5. Rule out with data (wifi: `ping -i 0.2 -c 300 <gw>` jitter and loss; I/O: PSI; memory: `free`, PSI; GPU: `gt_cur_freq_mhz`), and say what is excluded.

Measurement tools without installing anything: `nix shell nixpkgs#linuxPackages.turbostat nixpkgs#stress nixpkgs#msr-tools nixpkgs#iw -c ...` (run as root for turbostat/msr after `modprobe msr`).

## CPU stuck at a low clock

- `scaling_cur_freq` can lie; use `turbostat --quiet --interval 2 --num_iterations 6` while `stress -c <threads> -t 14` runs. Compare `Bzy_MHz` with the base/turbo clocks, check `CoreTmp`/`PkgTmp`, `PkgWatt` and the `SMI` column.
- Cool CPU, busy 100%, minimum clock, low power: an external clamp. Read the registers (per CPU with `rdmsr -a -x`):
  - `0x19c` IA32_THERM_STATUS: bit 0 thermal, bit 2 PROCHOT/FORCEPR, bit 3 its log, bits 10/11 power limit and log.
  - `0x1fc` MSR_POWER_CTL: bit 0 `BD_PROCHOT` (CPU obeys the external PROCHOT line).
  - `0x198` PERF_STATUS (current ratio), `0x199` PERF_CTL (requested), `0x1a0` MISC_ENABLE (bit 16 EIST, bit 38 turbo disable), `0x1ad` turbo ratio limit, `0xce` platform info.
- PROCHOT asserted with thermal and power bits clear = the board's embedded controller is clamping (no battery or an unrecognised charger on laptops, even on AC). Real fix: a recognised battery/charger, or BIOS settings. Software workaround: clear bit 0 of `0x1fc` on every CPU (`wrmsr -a 0x1fc $(( value & ~1 ))`), temporary until reboot, then make it a oneshot systemd service re-run after suspend. It removes the EC protection line (the CPU keeps its own thermal protection), so say so and watch temperatures under load.
- Verified effect on a Sandy Bridge laptop: 800 MHz to about 2.35-2.5 GHz on 8 threads, package power about 13 W to about 41 W.

## Periodic freezes of everything (mouse, video) every N seconds

- Suspect firmware calls (SMM) that halt all CPUs: `turbostat` `SMI` column, `journalctl -k | grep 'SMM call took'`.
- Dell laptops: reading the fan sensor through `dell_smm_hwmon` takes about 500 ms; time it with `date +%s%N` around `cat /sys/class/hwmon/hwmonX/fan1_input` (temperature files take about 12 ms). Anything that polls hwmon (node_exporter's default hwmon collector on every scrape, `sensors`, desktop widgets) freezes the machine each time. Fix: blacklist `dell_smm_hwmon` (loses fan RPM only) or disable the polling reader. Test live with `sudo rmmod dell_smm_hwmon`.
- Also check kworker threads in `D` state (`ps -eo pid,stat,wchan:32,comm`) and ACPI GPE counters (`/sys/firmware/acpi/interrupts`, compare two samples) for an interrupt storm.

## Video playback lag

- Decide whether decoding is on the GPU: `vainfo` (needs `LIBVA_DRIVER_NAME`), per-thread CPU of the Firefox media/RDD and content processes during playback.
- Old Intel (Sandy Bridge gen6) only has the legacy i965 VA-API driver (`intel-vaapi-driver`), decoding H.264/MPEG-2/VC-1 only: VP8/VP9/AV1 are CPU decoded. YouTube serves VP9/AV1 by default, which saturates the CPU. Firefox prefs (`programs.firefox.preferences`): `media.ffmpeg.vaapi.enabled`, `media.hardware-video-decoding.force-enabled`, and to force H.264 `media.mediasource.vp9.enabled = false`, `media.av1.enabled = false`. Verify with "Stats for nerds" (codec must read `avc1`, not `vp09`/`av01`) and `about:support` (Media section). If prefs are ignored, use an H.264-forcing extension.
- Background load matters on 4-core/8-thread old CPUs: sync daemons (syncthing) and software decoding together cause stutter; check per-process CPU before blaming the GPU.

## Desktop and GPU

- GPUs without Vulkan (pre-Ivy Bridge Intel, i.e. Mesa `crocus`) break wgpu based apps: COSMIC portal/settings (iced) abort at start on lavapipe shader validation errors (`iced_wgpu ... unpack_u32`), seen as `xdg-desktop-portal-cosmic` SIGABRT crash loops. Fix: `environment.sessionVariables.ICED_BACKEND = "tiny-skia"` (CPU renderer; the compositor itself uses GL). Applies to new sessions only: verify with the crash timestamps after the new login, not with the repo.
- Compositor segfaults: `coredumpctl info <pid>`, `journalctl -b --user -u cosmic-*`; usually a consequence of the GPU/renderer setup.

## Wifi

- `iw dev <if> link` (signal, bitrate), `iw dev <if> get power_save`, NetworkManager logs, ping jitter. A card that cannot see the SSID is often 2.4 GHz only (e.g. Intel Centrino Wireless-N 1000): the router needs a 2.4 GHz SSID for it.
- Being on ethernet and wifi of the same subnet needs loose reverse-path filtering and ARP settings (already in `bcl.wifi`).

## Boot

- Stall before the login manager with Plymouth: see [bcl-nixos](../bcl-nixos/SKILL.md) (boot patterns). Capture `systemctl list-jobs` and `systemd-analyze blame` on the stuck machine before rebooting; for the next boot add `systemd.log_level=debug`.
