+++
title = "Wi-Fi P2P / Miracast Hardware Compatibility"
weight = 20
description = "Known Wi-Fi chipset limitations for P2P (Wi-Fi Direct) Group Owner mode, relevant to bcl.role.tv.miracast"
+++

## Intel AX200 / AX201 (iwlwifi): 5GHz P2P Group Owner not supported on Linux

**Symptom**: when `bcl.role.tv.miracast` (or any P2P-based Wi-Fi Display / Miracast
setup) tries to form or negotiate a P2P group on 5GHz, it fails outright. Forcing it
via `wpa_cli p2p_group_add freq=<5GHz channel>` returns a clean `FAIL`, with the exact
reason visible via `wpa_cli log_level debug` + `journalctl`:

```
P2P: The forced channel for GO (5180 MHz) is not supported for P2P uses
```

This was tested exhaustively on channels 36, 44, 149, and 153 (5180/5220/5745/5765
MHz) - all four rejected identically. Only 2.4GHz channels are accepted for P2P-GO on
this chip. Winning P2P GO-Negotiation against a peer that also requests max
`go_intent` (e.g. most modern Android phones) doesn't help either - `p2p_go_intent`
only goes up to 15 (max), so a tie against an equally-max-intent peer is not
something we can win by config alone, and even when won, it still can't force 5GHz
per the restriction above.

### Root cause

Confirmed via `iw phy phy0 info` that the radio/driver DOES generically advertise
`HE Iftypes: AP, P2P-GO` capability on BOTH the 2.4GHz and 5GHz bands - this is NOT a
simple "chip can't do 5GHz P2P" limitation at the generic capability level. The block
happens one layer up, in wpa_supplicant's own P2P-specific channel list
(`p2p_supported_freq()`), which is populated from what the **iwlwifi driver/firmware**
specifically reports as usable *for P2P purposes* - and for the Intel
AX200/AX201 generation's Linux driver, that P2P-specific list only ever includes
2.4GHz channels, regardless of regulatory domain or DFS status.

This is a confirmed, Intel-acknowledged **Linux-driver-specific bug**, not a hardware
ceiling:

- Intel Community thread: [AX201 not connecting to p2p go on 5 GHz](https://community.intel.com/t5/Wireless/AX201-not-connecting-to-p2p-go-on-5-GHz/m-p/1236286)
  (Dec 2020 - Feb 2021) reports the exact same symptom on the exact same chip.
- The same physical hardware (Intel NUC) with an **older `ac` chip (Wi-Fi 5)** works
  fine on 5GHz P2P-GO - the failure is specific to the newer `ax`/Wi-Fi 6 generation
  (AX200/AX201) and its Linux driver.
- The reporter confirmed the SAME NUC, same P2P-GO peer, works correctly on 5GHz
  P2P-GO when booted into **Windows** with Intel's Windows driver - proving the
  radio/firmware hardware itself can do 5GHz P2P-GO; the bug is specifically in
  Intel's Linux `iwlwifi` driver/firmware-loading path.
- Intel's own support engineer escalated this internally to their engineering team
  ("the engineering team has started investigating this P2P issue more deeply") as of
  Feb 2021 - the public thread ends there with no further update ever posted, i.e.
  still effectively unresolved for Linux users years later.
- `dmesg` in that thread also showed iwlwifi crashing in some 5GHz P2P-GO attempts -
  consistent with a full network outage observed here on a live `p2p_group_add
  freq=5180` attempt (required a physical reboot to recover; a later, more controlled
  retry returned a clean `FAIL` instead of crashing, with a background `journalctl -f`
  capture confirming the exact rejection reason above).

**Conclusion: do not spend more time trying to force 5GHz P2P-GO on Intel
AX200/AX201 hardware from Linux/NixOS config alone** - this requires either an
Intel driver/firmware fix (unresolved as of this writing) or different Wi-Fi
hardware.

### Recommended alternative hardware for 5GHz Miracast/Wi-Fi Direct

Use a dedicated USB Wi-Fi adapter for the Miracast role instead of the host's
built-in Intel AX200/AX201, leaving the built-in adapter for normal networking.
Chipsets confirmed to support 5GHz P2P-GO on Linux:

- **MediaTek MT7612U / MT7610U** (`mt76x2u` driver, mainline kernel) - widely used
  in Miracast/Wi-Fi Direct USB dongles, good 5GHz P2P support.
- **Realtek RTL8812AU / RTL8811AU** (`rtl8812au`, out-of-tree but actively
  maintained, e.g. morrownr's driver) - commonly used specifically for Wi-Fi
  Direct/Miracast projects, with explicit 5GHz GO support.
