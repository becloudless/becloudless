{ lib, stdenv, fetchFromGitHub, glib }:

let
  # renovate: datasource=github-releases depName=nick-redwill/LiveLockScreen
  version = "3.1.0";
in

stdenv.mkDerivation {
  pname = "gnome-shell-extension-live-lock-screen";
  inherit version;

  src = fetchFromGitHub {
    owner = "nick-redwill";
    repo = "LiveLockScreen";
    rev = "v${version}";
    hash = "sha256-ufUNfF750iy8vYpc3tZlR/HAuHth9KxiUERwAAjAVaQ=";
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