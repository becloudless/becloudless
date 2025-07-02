{ config, lib, pkgs, ... }:
let
  cfg = config.bcl.keepassxc;
in {

  options.bcl.keepassxc = {
    enable = lib.mkEnableOption "Enable";
    user = lib.mkOption {
      type = lib.types.str;
#      default = "";
    };
  };


  config = lib.mkIf cfg.enable {
    programs.ssh.startAgent = true;

    home-manager.users."${cfg.user}" = { lib, pkgs, ... }: {
      home.file.".config/autostart/org.keepassxc.KeePassXC.desktop".text = ''
        [Desktop Entry]
        Name=KeePassXC
        GenericName=Password Manager
        Exec=keepassxc
        TryExec=keepassxc
        Icon=keepassxc
        StartupWMClass=keepassxc
        StartupNotify=true
        Terminal=false
        Type=Application
        Version=1.0
        Categories=Utility;Security;Qt;
        MimeType=application/x-keepass2;
        X-GNOME-Autostart-enabled=true
        X-GNOME-Autostart-Delay=2
        X-KDE-autostart-after=panel
        X-LXQt-Need-Tray=true
      '';

      home.file.".config/keepassxc/keepassxc.ini".text = ''
        [General]
        ConfigVersion=2
        HideWindowOnCopy=true
        MinimizeAfterUnlock=true

        [Browser]
        AlwaysAllowAccess=true
        BestMatchOnly=false
        CustomProxyLocation=
        Enabled=true
        HttpAuthPermission=true

        [FdoSecrets]
        ConfirmAccessItem=false
        Enabled=true

        [GUI]
        ApplicationTheme=dark
        CompactMode=true
        HideUsernames=false
        MinimizeOnClose=true
        MinimizeOnStartup=false
        MinimizeToTray=true
        MonospaceNotes=true
        ShowExpiredEntriesOnDatabaseUnlock=false
        ShowTrayIcon=true
        TrayIconAppearance=monochrome-light

        [KeeShare]
        Active="<?xml version=\"1.0\"?><KeeShare><Active/></KeeShare>\n"
        Own="<?xml version=\"1.0\"?><KeeShare><PrivateKey>MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQDlJ6LQLqCPTTm7krwwTBxiQRmLH08kRgnbz6mcSXsn1bIy1QJLcz2j6A23IxdLB1RHAC287SzCZmgw2rx8dObRgkYQa3tGFBpK8+CujrJLUuTr3BR8/b0CFdPTOI3T+Xhv7SMYRQzj0q6gICwy7BJ5wshXQW02PrVQl63FysDq64mKyi1WL+tdw6VfhDiuvD/qI5+6dmsA7LqcvN4bGsSwNkOeqPterV6I8uxhppR0AR8gzcsAbp7T3zfUihip6mYB8BIM86U82AHJ4yNJL9Nhc85V81jAkiDXy48wd5lhH3suf4JYpCvnwUGy1QnTB8KvSG6R3kA6FzAdhwfr2r/PAgMBAAECggEAHrxGZVeJAoolnwfV2kEtzMHq4VLwOa8eiGSIh8//8ZOt2eKMcxPrEG5sqdkjjn/WU8rtgjm/jKLRVmgoQCXVMFmhoyHUwCKsdMwpdnro5XB3XZPrDZQM7gLWeANNsUD0i0f1B+l5tUmfUWvZ8cnhyoIP0/WQZpEE9GEma3E/7IzXmBhvnViqRqAU9JWheQt2tiZ4H6IZo1fRqAE24rug0TspycY3FyW3W0b1xM1Tj80R6nVgsMhbkIkDIx9voeqjxP6hgCCjU8T8LCCsoKPcYlZCfN3APvRVOJMw8+Ni+sEd2PRx5zQuLe4rnR1K/37/5dOKcD1fbbA8INUKgHlAHQKBgQD/vLq5m/RQYJUJxMckIelTeUXbyefQrh2StZqac48RSCpadxaxYfDQ+ZoV2WBbfzAKu1w3xRkMEkGhZigTrJOXW4WhwX9valav9bl5Nr1vcVRK7iwY/jqY46zhM2mbyoVDshkBfttij2ciKYuboqKQikElAtwjLyeE5V/lKcy3RQKBgQDlY+oJcCTy3E0Ml/+ccxcgy/MPrBdLqaWaAQTGbhWw7OJOrkWsi4ZVrpPa+IrdlmUHu0lDkJPEGDUCjspRVNFpWtLrTz2mFg/+BdKcnNs77mBY4uaE/8BTotCH6YDAI3hBfhw0LcxWjoGyIW4zSwJkjrvcDlTvhp0oYBw0aobSAwKBgGyBCMCDmM8Zi2KPqOZ9tN+Dzs4IBmEV3tpGTwhFC2iLs9yaNnigU2p23Jd0mVt4xUtoXyIScCQdAteV3l8qk5xean5M+OKuvYT+vujc/tbvwJHiJ7ea9gW0Y79Q7vf4nz4vrEhkKHTS3zExa1hnUo38+tLXOct70Eqkf2FdsMv5AoGAFEiQckMzUTI/seRi2s+mdOTz2ifqa2tV1FdQt8cWLe3UWQa57Hbt6vej5VHi3ZMl3dgms02+czF8xnwf0a9BUSKR0fLQzbXXtiuHowePry314QY3Qf1nYT3dWJdCJjs8r/XZwpdmISU6vKiOGQUB8ihY3i16Py/VB7Pv6oac40cCgYEAjGqQerfilTSMXxw8zerFiEmLPosVr2pOhQ3hiZ107vh/tqx4d3EQLJDieln/vYy77m1hV5l3XROcHQ/yuuIIo+F8Gy9CDb3Ml7hC21q/cFa2ntqhzs21XQObhzpNK5l4vQv337y6qW2pd4D2kQPfpFEAOEtAan4ku6o0QdeRtVA=</PrivateKey><PublicKey><Signer>n0rad</Signer><Key>MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQDlJ6LQLqCPTTm7krwwTBxiQRmLH08kRgnbz6mcSXsn1bIy1QJLcz2j6A23IxdLB1RHAC287SzCZmgw2rx8dObRgkYQa3tGFBpK8+CujrJLUuTr3BR8/b0CFdPTOI3T+Xhv7SMYRQzj0q6gICwy7BJ5wshXQW02PrVQl63FysDq64mKyi1WL+tdw6VfhDiuvD/qI5+6dmsA7LqcvN4bGsSwNkOeqPterV6I8uxhppR0AR8gzcsAbp7T3zfUihip6mYB8BIM86U82AHJ4yNJL9Nhc85V81jAkiDXy48wd5lhH3suf4JYpCvnwUGy1QnTB8KvSG6R3kA6FzAdhwfr2r/PAgMBAAECggEAHrxGZVeJAoolnwfV2kEtzMHq4VLwOa8eiGSIh8//8ZOt2eKMcxPrEG5sqdkjjn/WU8rtgjm/jKLRVmgoQCXVMFmhoyHUwCKsdMwpdnro5XB3XZPrDZQM7gLWeANNsUD0i0f1B+l5tUmfUWvZ8cnhyoIP0/WQZpEE9GEma3E/7IzXmBhvnViqRqAU9JWheQt2tiZ4H6IZo1fRqAE24rug0TspycY3FyW3W0b1xM1Tj80R6nVgsMhbkIkDIx9voeqjxP6hgCCjU8T8LCCsoKPcYlZCfN3APvRVOJMw8+Ni+sEd2PRx5zQuLe4rnR1K/37/5dOKcD1fbbA8INUKgHlAHQKBgQD/vLq5m/RQYJUJxMckIelTeUXbyefQrh2StZqac48RSCpadxaxYfDQ+ZoV2WBbfzAKu1w3xRkMEkGhZigTrJOXW4WhwX9valav9bl5Nr1vcVRK7iwY/jqY46zhM2mbyoVDshkBfttij2ciKYuboqKQikElAtwjLyeE5V/lKcy3RQKBgQDlY+oJcCTy3E0Ml/+ccxcgy/MPrBdLqaWaAQTGbhWw7OJOrkWsi4ZVrpPa+IrdlmUHu0lDkJPEGDUCjspRVNFpWtLrTz2mFg/+BdKcnNs77mBY4uaE/8BTotCH6YDAI3hBfhw0LcxWjoGyIW4zSwJkjrvcDlTvhp0oYBw0aobSAwKBgGyBCMCDmM8Zi2KPqOZ9tN+Dzs4IBmEV3tpGTwhFC2iLs9yaNnigU2p23Jd0mVt4xUtoXyIScCQdAteV3l8qk5xean5M+OKuvYT+vujc/tbvwJHiJ7ea9gW0Y79Q7vf4nz4vrEhkKHTS3zExa1hnUo38+tLXOct70Eqkf2FdsMv5AoGAFEiQckMzUTI/seRi2s+mdOTz2ifqa2tV1FdQt8cWLe3UWQa57Hbt6vej5VHi3ZMl3dgms02+czF8xnwf0a9BUSKR0fLQzbXXtiuHowePry314QY3Qf1nYT3dWJdCJjs8r/XZwpdmISU6vKiOGQUB8ihY3i16Py/VB7Pv6oac40cCgYEAjGqQerfilTSMXxw8zerFiEmLPosVr2pOhQ3hiZ107vh/tqx4d3EQLJDieln/vYy77m1hV5l3XROcHQ/yuuIIo+F8Gy9CDb3Ml7hC21q/cFa2ntqhzs21XQObhzpNK5l4vQv337y6qW2pd4D2kQPfpFEAOEtAan4ku6o0QdeRtVA=</Key></PublicKey></KeeShare>\n"
        QuietSuccess=true

        [PasswordGenerator]
        AdditionalChars=
        ExcludedChars=
        Length=500
        LowerCase=true
        Numbers=true
        SpecialChars=true
        UpperCase=true
        WordCount=9

        [SSHAgent]
        Enabled=true

        [Security]
        LockDatabaseIdle=true
        LockDatabaseIdleSeconds=36000
        LockDatabaseScreenLock=false
      '';
    };

    environment.systemPackages = with pkgs; [
      keepassxc
    ];
  };
}
