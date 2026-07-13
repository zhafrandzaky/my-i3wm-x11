# Example host configuration for the my-i3wm-x11 desktop.
# Copy this next to your hardware-configuration.nix and adjust the marked
# values, or let nixos/install.sh generate a personalized copy for you.
{ config, pkgs, ... }:

{
  # ---- adjust these ----
  networking.hostName = "i3wm-example";

  users.users.tester = {
    isNormalUser = true;
    description = "Tester";
    extraGroups = [ "wheel" ];
    initialPassword = "changeme"; # change after first login!
  };

  services.i3wm-x11 = {
    enable = true;
    username = "tester";
    enableDisplayManager = false; # true = LightDM; false = startx (parity)
    withVSCode = false; # unfree
    withBrave = false; # unfree
  };
  # ----------------------

  # Flakes for this host (permanence is declarative, never via nix.conf edits)
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/vda"; # adjust to your disk (or use systemd-boot on EFI)

  networking.useDHCP = false; # NetworkManager (enabled by the module) manages the network

  services.openssh.enable = true;

  # Never change this after installation (see NixOS manual).
  system.stateVersion = "26.05";
}
