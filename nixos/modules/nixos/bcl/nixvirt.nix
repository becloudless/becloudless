# Instantiates the vendored NixVirt logic (../../../packages/nixvirt/) with
# the HOST'S OWN native `pkgs`, instead of NixVirt's own upstream flake.nix,
# which hardcodes `import nixpkgs { system = "x86_64-linux"; }` for
# everything (its Python helper scripts and default libvirt package). See
# ../../../packages/nixvirt/VENDORED.md for the full rationale.
#
# This makes libvirtd, its module-helper Python script, and virtdeclare all
# native builds on any architecture (e.g. aarch64), eliminating the need for
# `boot.binfmt.emulatedSystems = ["x86_64-linux"]` and any cross-arch
# bootstrap dance to get a serverVirt host to be able to rebuild itself.
{ config, lib, pkgs, ... }:
let
  vendorDir = ../../../packages/nixvirt;

  nixvirtPythonModulePackage = pkgs.runCommand "nixvirtPythonModulePackage" { } ''
    mkdir -p $out/${pkgs.python3.sitePackages}
    ln -s ${vendorDir}/tool/nixvirt.py $out/${pkgs.python3.sitePackages}/nixvirt.py
  '' // { pythonModule = pkgs.python3; };

  pythonInterpreterPackage = libvirt: pkgs.python3.withPackages (ps: [
    (ps.libvirt.override { inherit libvirt; })
    ps.lxml
    ps.xmldiff
    nixvirtPythonModulePackage
  ]);

  setShebang = name: path: libvirt: pkgs.runCommand name { } ''
    sed -e "1s|.*|\#\!${pythonInterpreterPackage libvirt}/bin/python3|" ${path} > $out
    chmod 755 $out
  '';

  moduleHelperFile = setShebang "nixvirt-module-helper" "${vendorDir}/tool/nixvirt-module-helper";

  nixvirtModules = import (vendorDir + "/modules.nix") {
    packages = pkgs;
    inherit moduleHelperFile;
  };
in
{
  imports = [ nixvirtModules.nixosModule ];
}
