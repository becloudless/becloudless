# default is intentionally empty because this package cannot be loaded automatically by snowfall for all architecture
# this is due to the fact that we need to build with the kernel with linuxManualConfig to include ubootTools and full kernel config
# linuxManualConfig need importFromDerivation to load config
# importFromDerivation is a fucking hell in multi-architecture flake
