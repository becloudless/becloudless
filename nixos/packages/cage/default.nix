{
  cage,
  fetchpatch,
}:
cage.overrideAttrs (prev: {
  patches = (prev.patches or []) ++ [
    # cage 0.3.0 (wlroots 0.20.0) does not advertise wp_fractional_scale_manager_v1.
    # jellyfin-desktop 3.0.0's wlproxy requires this protocol to proceed past its
    # boot-time VO wait (host_ready() blocks on jfn_wl_scale_known(), which is only
    # set by wp_fractional_scale_v1.preferred_scale). Without this patch, the app
    # hangs indefinitely before CEF ever initializes.
    ./0001-add-fractional-scale-manager.patch
  ];
})
