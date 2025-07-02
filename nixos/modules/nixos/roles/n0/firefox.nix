{ config, lib, pkgs, ... }: {
  config = lib.mkIf (config.bcl.role.name == "n0") {

    home-manager.users.n0rad = { lib, pkgs, ... }: {
      programs.firefox = {
        enable = true;
      #   profiles = {
      #     default = {
      #       id = 0;
      #       name = "default";
      #       isDefault = true;
      #       settings = {
      #         "browser.search.defaultenginename" = "DuckDuckGo";
      #         "browser.search.order.1" = "DuckDuckGo";
      #         "browser.uidensity" = 1;
      #         "browser.startup.homepage" = "chrome://browser/content/blanktab.html";
      #         "app.normandy.first_run" = false;

      #         "signon.rememberSignons" = false;
      #         "widget.use-xdg-desktop-portal.file-picker" = 1;
      #         "browser.aboutConfig.showWarning" = false;
      #         "browser.compactmode.show" = true;
      #         "browser.cache.disk.enable" = false; # Be kind to hard drive

      #         "mousewheel.default.delta_multiplier_x" = 20;
      #         "mousewheel.default.delta_multiplier_y" = 20;
      #         "mousewheel.default.delta_multiplier_z" = 20;

      #         "browser.newtabpage.activity-stream.showSearch" = false;
      #         "browser.newtabpage.activity-stream.improvesearch.topSiteSearchShortcuts" = false;
      #         "browser.newtabpage.activity-stream.feeds.topsites" = false;

      #         # "browser.newtabpage.activity-stream.showSponsored" = false;
      #         # "browser.newtabpage.activity-stream.system.showSponsored" = false;
      #         # "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;


      #   #   "extensions.pocket.enabled" = lock-false;
      #   #   "browser.newtabpage.pinned" = lock-empty-string;
      #   #   "browser.topsites.contile.enabled" = lock-false;


      # #   "browser.disableResetPrompt" = true;
      # #   "browser.download.panel.shown" = true;
      # #   "browser.download.useDownloadDir" = false;
      # #   "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;
      # #   "browser.shell.checkDefaultBrowser" = false;
      # #   "browser.shell.defaultBrowserCheckCount" = 1;
      # #   "browser.startup.homepage" = "https://start.duckduckgo.com";
      # #   "browser.uiCustomization.state" = ''{"placements":{"widget-overflow-fixed-list":[],"nav-bar":["back-button","forward-button","stop-reload-button","home-button","urlbar-container","downloads-button","library-button","ublock0_raymondhill_net-browser-action","_testpilot-containers-browser-action"],"toolbar-menubar":["menubar-items"],"TabsToolbar":["tabbrowser-tabs","new-tab-button","alltabs-button"],"PersonalToolbar":["import-button","personal-bookmarks"]},"seen":["save-to-pocket-button","developer-button","ublock0_raymondhill_net-browser-action","_testpilot-containers-browser-action"],"dirtyAreaCache":["nav-bar","PersonalToolbar","toolbar-menubar","TabsToolbar","widget-overflow-fixed-list"],"currentVersion":18,"newElementCount":4}'';
      # #   "dom.security.https_only_mode" = true;
      # #   "identity.fxaccounts.enabled" = false;
      # #   "privacy.trackingprotection.enabled" = true;
      # #   "signon.rememberSignons" = false;

      #         # Firefox 75+ remembers the last workspace it was opened on as part of its session management.
      #         # This is annoying, because I can have a blank workspace, click Firefox from the launcher, and
      #         # then have Firefox open on some other workspace.
      #         # "widget.disable-workspace-management" = true;
      #       };
      #       search = {
      #         force = true;
      #         default = "DuckDuckGo";
      #         order = [ "DuckDuckGo" "Google" ];
      #       };
      #     };
        # };
      };
    };


    programs.firefox = {
      enable = true;
      languagePacks = [ "fr" "en-US" ];

      # profiles = {
      #   default = {
      #     id = 0;
      #     name = "default";
      #     isDefault = true;
      #     settings = {
      #       "browser.startup.homepage" = "https://searx.aicampground.com";
      #       "browser.search.defaultenginename" = "Searx";
      #       "browser.search.order.1" = "Searx";
      #     };
      #     search = {
      #       force = true;
      #       default = "Searx";
      #       order = [ "Searx" "Google" ];
      #       engines = {
      #         "Nix Packages" = {
      #           urls = [{
      #             template = "https://search.nixos.org/packages";
      #             params = [
      #               { name = "type"; value = "packages"; }
      #               { name = "query"; value = "{searchTerms}"; }
      #             ];
      #           }];
      #           icon = "''${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
      #           definedAliases = [ "@np" ];
      #         };
      #         "NixOS Wiki" = {
      #           urls = [{ template = "https://nixos.wiki/index.php?search={searchTerms}"; }];
      #           iconUpdateURL = "https://nixos.wiki/favicon.png";
      #           updateInterval = 24 * 60 * 60 * 1000; # every day
      #           definedAliases = [ "@nw" ];
      #         };
      #         "Searx" = {
      #           urls = [{ template = "https://searx.aicampground.com/?q={searchTerms}"; }];
      #           iconUpdateURL = "https://nixos.wiki/favicon.png";
      #           updateInterval = 24 * 60 * 60 * 1000; # every day
      #           definedAliases = [ "@searx" ];
      #         };
      #         "Bing".metaData.hidden = true;
      #         "Google".metaData.alias = "@g"; # builtin engines only support specifying one additional alias
      #       };
      #     };
      #     # extensions = with pkgs.nur.repos.rycee.firefox-addons; [
      #     #   ublock-origin
      #     #   bitwarden
      #     #   darkreader
      #     #   vimium
      #     # ];
      #   };
      # };











      # profiles.${username}.settings = {
      #   # Settings
      # };
      policies = {
        DisableTelemetry = true;
        DisableFirefoxStudies = true;
        EnableTrackingProtection = {
          Value= true;
          Locked = true;
          Cryptomining = true;
          Fingerprinting = true;
        };
        DisablePocket = true;
        DisableFirefoxAccounts = true;
        DisableAccounts = true;
        DisableFirefoxScreenshots = true;
        OverrideFirstRunPage = "";
        OverridePostUpdatePage = "";
        DontCheckDefaultBrowser = true;
        DisplayBookmarksToolbar = "never"; # alternatives: "always" or "newtab"
        DisplayMenuBar = "default-off"; # alternatives: "always", "never" or "default-on"
        SearchBar = "unified"; # alternative: "separate"


        ExtensionSettings = {
  #        "*".installation_mode = "blocked"; # blocks all addons except the ones specified below
          # uBlock Origin:
          "uBlock0@raymondhill.net" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
            installation_mode = "force_installed";
          };
          # tab count
          "{c28e42b2-28b5-45f0-bdc8-6989ae7e6a7e}" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/tab-count-in-window-title/latest.xpi";
            installation_mode = "force_installed";
          };
          # new container
          "{71d4d33f-0bb1-4d92-8389-3f604d62a11a}" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/new-container-tab/latest.xpi";
            installation_mode = "force_installed";
          };
          # Tab Session Manager
          "Tab-Session-Manager@sienori" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/tab-session-manager/latest.xpi";
            installation_mode = "force_installed";
          };
          # KeePassXC-Browser
          "keepassxc-browser@keepassxc.org" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/keepassxc-browser/latest.xpi";
            installation_mode = "force_installed";
          };
          # I don't care about cookies
          "jid1-KKzOGWgsW3Ao4Q@jetpack" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/i-dont-care-about-cookies/latest.xpi";
            installation_mode = "force_installed";
          };
          # GNOME Shell integration	extension
          "chrome-gnome-shell@gnome.org" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/gnome-shell-integration/latest.xpi";
            installation_mode = "force_installed";
          };
          # Firefox Multi-Account Containers
          "@testpilot-containers" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/multi-account-containers/latest.xpi";
            installation_mode = "force_installed";
          };
          # Duplicate Tabs Closer
          "jid0-RvYT2rGWfM8q5yWxIxAHYAeo5Qg@jetpack" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/duplicate-tabs-closer/latest.xpi";
            installation_mode = "force_installed";
          };
          # Cookie AutoDelete
          "CookieAutoDelete@kennydo.com" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/cookie-autodelete/latest.xpi";
            installation_mode = "force_installed";
          };
          # Container Color Toolbar
          "{293bcb6f-b811-4f9b-a79e-281653ff07b8}" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/container-color-toolbar/latest.xpi";
            installation_mode = "force_installed";
          };
          # Auto Tab Discard
          "{c2c003ee-bd69-42a2-b0e9-6f34222cb046}" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/auto-tab-discard/latest.xpi";
            installation_mode = "force_installed";
          };
          # Absolute Enable Right Click & Copy
          "{9350bc42-47fb-4598-ae0f-825e3dd9ceba}" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/absolute-enable-right-click/latest.xpi";
            installation_mode = "force_installed";
          };
        };
      };
    };
  };
}
