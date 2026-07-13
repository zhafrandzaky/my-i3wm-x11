{
  description = "my-i3wm-x11 — i3wm (X11) desktop as first-class NixOS modules";

  # NOTE: this flake lives in nixos/ and references ../common. It must be
  # consumed with the whole repository as the source, i.e.:
  #   github:zhafrandzaky/my-i3wm-x11?dir=nixos
  #   path:/path/to/clone?dir=nixos
  # (docs/DESIGN.md §2, §6)

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
    }:
    let
      lib = nixpkgs.lib;
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      # System-level module (X11/i3 session, audio, network, fonts, PAM...).
      nixosModules.desktop = import ./module.nix;

      # User-level module (packages, dotfiles, user services).
      homeManagerModules.dotfiles = import ./home.nix;

      # Batteries-included composition: system module + Home Manager wiring.
      nixosModules.default = { config, ... }: {
        imports = [
          self.nixosModules.desktop
          home-manager.nixosModules.home-manager
        ];
        config = lib.mkIf config.services.i3wm-x11.enable {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          # Back up any pre-existing dotfiles instead of aborting activation
          home-manager.backupFileExtension = "hmbak";
          home-manager.users.${config.services.i3wm-x11.username} = {
            imports = [ self.homeManagerModules.dotfiles ];
            i3wm-x11.withVSCode = config.services.i3wm-x11.withVSCode;
            i3wm-x11.withBrave = config.services.i3wm-x11.withBrave;
            home.stateVersion = lib.mkDefault "26.05";
          };
        };
      };

      # Example host (also serves as the eval check target).
      nixosConfigurations.example = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          self.nixosModules.default
          ./example/configuration.nix
          ./example/hardware-configuration.nix
        ];
      };

      checks.${system} = {
        # Force full module-system evaluation without building the system.
        example-eval = pkgs.runCommand "i3wm-x11-example-eval" { } ''
          echo ${self.nixosConfigurations.example.config.system.build.toplevel.drvPath} > $out
        '';
      };

      formatter.${system} = pkgs.nixfmt-rfc-style;
    };
}
