{ lib, buildGnomeExtension, fetchFromGitHub }:

buildGnomeExtension {
  pname = "live-lock-screen";
  version = "unstable-2024";

  src = fetchFromGitHub {
    owner = "nick-redwill";
    repo = "LiveLockScreen";
    rev = "main";
    sha256 = "sha256-wX8mo1ZC7AYf44p3F14L03X0wjNPjDOZ+zof6mWS0ds=";
  };

  meta = with lib; {
    description = "Live Lock Screen GNOME Shell Extension";
    homepage = "https://github.com/nick-redwill/LiveLockScreen";
    license = licenses.gpl2Only;
    maintainers = [];
    platforms = platforms.linux;
  };
}
