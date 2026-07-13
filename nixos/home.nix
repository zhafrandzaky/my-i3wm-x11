# User-level Home Manager module (docs/DESIGN.md §6.3).
# Deploys the shared common/ configs verbatim as read-only store symlinks —
# possible because everything the desktop writes at runtime lives in
# ~/.local/state/i3wm-x11 (XDG state separation, docs/DESIGN.md §4).
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.i3wm-x11;
  common = ../common;
in
{
  options.i3wm-x11 = {
    withVSCode = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Install Visual Studio Code (unfree).";
    };
    withBrave = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Install Brave (unfree).";
    };
  };

  config = {
    home.packages =
      with pkgs;
      [
        # bar / menus / desktop chrome
        polybarFull # default polybar lacks pulseaudio & i3 support flags
        rofi
        dunst
        picom
        feh
        autotiling
        # terminal & shell environment
        kitty
        starship
        fastfetch
        eza
        bat
        fd
        # desktop tools (same set the Arch/Debian installers provide)
        flameshot
        zenity
        playerctl
        brightnessctl
        pavucontrol
        networkmanagerapplet
        blueman
        xfce.xfce4-power-manager
        lxappearance
        thunar
        firefox
        # theming engine
        pywal
        imagemagick
        papirus-icon-theme
        papirus-folders
        arc-theme
        # script runtime deps
        python3
        jq
        xclip
        libnotify
        psmisc
        xdg-utils
        mesa-demos
        xorg.xset
        xorg.xrandr
        curl
        neovim
        ripgrep
        tree
        htop
        mpv
      ]
      ++ lib.optionals cfg.withVSCode [ vscode ]
      ++ lib.optionals cfg.withBrave [ brave ];

    # --- Dotfiles: the exact common/ files, read-only from the store ---
    xdg.configFile = {
      "i3/config".source = common + "/configs/i3/config";
      "i3/scripts".source = common + "/scripts";
      "i3/themes".source = common + "/themes";
      "i3/lib".source = common + "/lib";
      "polybar".source = common + "/configs/polybar";
      "rofi".source = common + "/configs/rofi";
      "kitty".source = common + "/configs/kitty";
      "picom".source = common + "/configs/picom";
      # dunstrc as a single file: ~/.config/dunst stays a real directory so
      # theme_switcher can write dunstrc.d/50-theme.conf next to it
      "dunst/dunstrc".source = common + "/configs/dunst/dunstrc";
      "fastfetch/art".source = common + "/configs/fastfetch/art";
      "starship.toml".source = common + "/configs/starship.toml";
      # matplotlib backend parity with the imperative installers
      "matplotlib/matplotlibrc".text = "backend: TkAgg";
    };
    home.file.".zshrc".source = common + "/.zshrc";

    # --- Polkit agent as a user service: the i3 config's path-probe loop
    #     cannot know Nix store paths (docs/DESIGN.md §6.3) ---
    systemd.user.services.polkit-gnome-agent = {
      Unit = {
        Description = "polkit-gnome authentication agent";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
        Restart = "on-failure";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    # --- GTK/icon theme, declarative equivalent of the config's gsettings ---
    gtk = {
      enable = true;
      theme = {
        name = "Arc-Dark";
        package = pkgs.arc-theme;
      };
      iconTheme = {
        name = "Papirus-Dark";
        package = pkgs.papirus-icon-theme;
      };
    };

    # --- Seed initial theme state (first boot) and fastfetch presets.
    #     State seeding is not config mutation (docs/DESIGN.md §4/§6.3). ---
    home.activation.i3wmSeedState = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ${pkgs.bash}/bin/bash -c 'source ${common}/lib/paths.sh && i3wm_seed_state'
      ${pkgs.bash}/bin/bash ${common}/scripts/setup_fastfetch.sh >/dev/null || true
    '';
  };
}
