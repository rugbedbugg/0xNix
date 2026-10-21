{
  description = "Pinned NixOS 26.05 Hyprland workstation";

  inputs = {
    # Exact revision used by the installed generation 1.
    nixpkgs.url = "github:NixOS/nixpkgs/26f4107e47e3ad0ffd0db220469ba83b6f6d96e8";
    # Deliberately NOT pinned/following the main nixpkgs: this is the escape
    # hatch for daily-driver CLI tools (coding agents, system tools) that
    # want to track upstream more closely than the rest of this stable
    # system. Bump just this input with `nix flake lock --update-input
    # nixpkgs-unstable` when you want newer versions of those tools.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    ly-lock = {
      url = "github:rugbedbugg/ly-lock";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
      ly-lock,
      ...
    }:
    let
      system = "x86_64-linux";
      vars = import ./vars.nix;
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      pkgsUnstable = import nixpkgs-unstable {
        inherit system;
        config.allowUnfree = true;
      };
      host = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          pkgs-unstable = pkgsUnstable;
          inherit vars;
        };
        modules = [
          home-manager.nixosModules.home-manager
          ly-lock.nixosModules.default
          ./hosts/nixos
        ];
      };
    in
    {
      nixosConfigurations.nixos = host;
      devShells.${system} = import ./devshells { inherit pkgs; };
      formatter.${system} = pkgs.nixfmt;
      checks.${system} = import ./checks { inherit pkgs host vars; };
      packages.${system} = {
        system = host.config.system.build.toplevel;
        home = host.config.home-manager.users.${vars.username}.home.activationPackage;
      };
    };
}
