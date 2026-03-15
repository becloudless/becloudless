+++
title = "OrangePi 5 / 5 Plus"
weight = 10
description = "OrangePi 5/5+ U-Boot SPI flash procedure"
+++

Reference: <http://www.orangepi.org/orangepiwiki/index.php/Orange_Pi_5_Plus>

## Install U-Boot to SPI Flash

```bash
git clone https://github.com/orangepi-xunlong/orangepi-build.git
docker run --rm -it -v $PWD:/build ubuntu:jammy
cd /build
apt-get update && apt-get install sudo
sudo ./build.sh # or sudo ./build.sh docker BOARD=orangepi5plus BRANCH=current BUILD_OPT=u-boot
cd output/debs/u-boot/
sudo dpkg -x linux-u-boot-current-orangepi5plus_1.2.2_arm64.deb .
ls usr/lib/linux-u-boot-current-orangepi5plus_1.2.2_arm64/rkspi_loader.img
sudo dd if=rkspi_loader.img of=/dev/mtdblock0 status=progress conv=fsync,notrunc
```

