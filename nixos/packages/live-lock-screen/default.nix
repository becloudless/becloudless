{ lib, stdenv, fetchFromGitHub, gnome-shell }:

stdenv.mkDerivation rec {
  pname = "live-lock-screen";
  version = "unstable-2024";

  src = fetchFromGitHub {
    owner = "nick-redwill";
    repo = "LiveLockScreen";
    rev = "main";
    sha256 = lib.fakeSha256;
  };

  installPhase = ''
    runHook preInstall
    extDir="$out/share/gnome-shell/extensions/live-lockscreen@nick-redwill"
    mkdir -p "$extDir"
    cp -r . "$extDir"
    runHook postInstall
  '';

  meta = with lib; {
    description = "Live Lock Screen GNOME Shell Extension";
    homepage = "https://github.com/nick-redwill/LiveLockScreen";
    license = licenses.gpl2Only;
    maintainers = [];
    platforms = platforms.linux;
  };
}
