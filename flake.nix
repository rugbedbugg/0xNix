{
  description = "TTY-themed desktop rice";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      home-manager,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      rice = {
        imports = [
          ./home
          ./home/options.nix
        ];
        _module.args.palette = import ./palette.nix;
      };
      fixture =
        extraModules:
        nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            home-manager.nixosModules.home-manager
            ./examples/workstation.nix
            { home-manager.users.example.imports = [ rice ]; }
          ]
          ++ extraModules;
        };
      minimal = fixture [ ];
      themed = fixture [ ./examples/themed-apps.nix ];
    in
    {
      homeManagerModules.default = rice;
      formatter.${system} = pkgs.nixfmt;
      checks.${system} = import ./checks {
        inherit pkgs minimal themed;
        host = minimal;
        home = minimal.config.home-manager.users.example;
      };
    };
}
