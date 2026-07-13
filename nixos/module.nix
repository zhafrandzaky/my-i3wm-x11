# System-level NixOS module (docs/DESIGN.md §6.2).
# Provides everything the desktop needs from the system: X11 + i3 session,
# audio, networking, bluetooth, fonts, PAM for the locker, udev backlight
# rule, and the user's shell/groups. User-level concerns live in home.nix.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.i3wm-x11;
in
{
  options.services.i3wm-x11 = {
    enable = lib.mkEnableOption "the my-i3wm-x11 desktop (system layer)";

    username = lib.mkOption {
      type = lib.types.str;
      description = "User the desktop is set up for (shell, groups, Home Manager).";
      example = "alice";
    };

    enableDisplayManager = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Use LightDM instead of the startx pattern. Parity default with the
        Arch/Debian installers is no display manager (startx). If your system
        already runs another display manager (GDM/SDDM), leave this false and
        keep yours: i3 appears there as an additional session.
      '';
    };

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

  config = lib.mkIf cfg.enable {
    # --- X11 + i3 session ---
    services.xserver.enable = true;
    services.xserver.windowManager.i3.enable = true;
    services.xserver.displayManager.startx.enable = !cfg.enableDisplayManager;
    services.xserver.displayManager.lightdm.enable = cfg.enableDisplayManager;
    services.displayManager.defaultSession = lib.mkIf cfg.enableDisplayManager "none+i3";

    # --- Audio (PipeWire, parity with Arch/Debian installers) ---
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };

    # --- Networking & Bluetooth ---
    networking.networkmanager.enable = true;
    hardware.bluetooth.enable = true;
    services.blueman.enable = true;

    # --- Screen locker: PAM service is mandatory; a plain package in
    #     home.packages cannot authenticate (docs/DESIGN.md §6.2) ---
    programs.i3lock = {
      enable = true;
      package = pkgs.i3lock-color;
    };

    # --- dconf: required system-side for the Home Manager gtk module's
    #     settings activation (otherwise HM fails with a D-Bus
    #     "name is not activatable" error on first switch) ---
    programs.dconf.enable = true;

    # --- Shell ---
    programs.zsh.enable = true;
    users.users.${cfg.username} = {
      shell = pkgs.zsh;
      extraGroups = [
        "video"
        "input"
        "audio"
        "networkmanager"
      ];
    };
    # zsh plugins at /run/current-system/sw/share/... (probed by common/.zshrc)
    environment.systemPackages = with pkgs; [
      zsh-autosuggestions
      zsh-syntax-highlighting
      git
    ];

    # --- Fonts (same set the Arch/Debian installers provide) ---
    fonts.packages = with pkgs; [
      nerd-fonts.jetbrains-mono
      nerd-fonts.symbols-only
      nerd-fonts.hack
      fira-code
      cascadia-code
      ibm-plex
      noto-fonts-cjk-sans
      noto-fonts-color-emoji
      font-awesome
      material-design-icons
    ];

    # --- Backlight keys without root (same rule the installers write) ---
    services.udev.extraRules = ''
      ACTION=="add", SUBSYSTEM=="backlight", RUN+="${pkgs.coreutils}/bin/chgrp video /sys/class/backlight/%k/brightness"
      ACTION=="add", SUBSYSTEM=="backlight", RUN+="${pkgs.coreutils}/bin/chmod g+w /sys/class/backlight/%k/brightness"
    '';

    # Scoped unfree allowance for the optional apps. mkDefault so a host with
    # its own allowUnfree policy wins.
    nixpkgs.config.allowUnfreePredicate = lib.mkIf (cfg.withVSCode || cfg.withBrave) (
      lib.mkDefault (
        pkg:
        builtins.elem (lib.getName pkg) [
          "vscode"
          "brave"
        ]
      )
    );
  };
}
