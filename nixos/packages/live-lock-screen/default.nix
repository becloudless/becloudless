{ lib, stdenv, fetchFromGitHub, glib }:

let
  # renovate: datasource=github-releases depName=nick-redwill/LiveLockScreen
  version = "3.1.0-unstable-2026-05-29";
in

stdenv.mkDerivation {
  pname = "gnome-shell-extension-live-lock-screen";
  inherit version;

  src = fetchFromGitHub {
    owner = "nick-redwill";
    repo = "LiveLockScreen";
    rev = "aae99ffb9087e8eca7ee04b27f2c890f577b1074";
    hash = "sha256-xj9ppjgw/r0wall39XHlSSZLUYYSW+tpLpSxLEoBD/s=";
  };

  nativeBuildInputs = [ glib ];

  uuid = "live-lockscreen@nick-redwill";

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/gnome-shell/extensions/live-lockscreen@nick-redwill
    cp -r . $out/share/gnome-shell/extensions/live-lockscreen@nick-redwill/
    glib-compile-schemas $out/share/gnome-shell/extensions/live-lockscreen@nick-redwill/schemas
    runHook postInstall
  '';

  meta = {
    description = "A GNOME Shell extension that lets you set any video as your lock screen background";
    homepage = "https://github.com/nick-redwill/LiveLockScreen";
    license = lib.licenses.agpl3Only;
    platforms = lib.platforms.linux;
  };
}