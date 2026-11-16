{
  description = "Reusable TTY-themed desktop and development modules";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    # Update frequently changing applications without moving the system set.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    aws-agent-toolkit = {
      url = "github:aws/agent-toolkit-for-aws/7fcb1da17abba610d7becc973c2141b40412e02c";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
      aws-agent-toolkit,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      example = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          self.nixosModules.default
          home-manager.nixosModules.home-manager
          ./examples/workstation.nix
          { home-manager.users.example.imports = [ self.homeManagerModules.default ]; }
        ];
      };
    in
    {
      nixosModules.default = {
        imports = [
          ./modules/desktop
          ./modules/development
        ];
      };
      homeManagerModules.default =
        { pkgs, ... }:
        {
          imports = [
            ./home
            ./home/options.nix
          ];
          _module.args = {
            palette = import ./palette.nix;
            pkgs-unstable = import nixpkgs-unstable {
              system = pkgs.stdenv.hostPlatform.system;
              config.allowUnfree = true;
            };
            inherit aws-agent-toolkit;
          };
        };

      # Evaluate a fictional example without supplying installation policy.
      nixosConfigurations.example = example;
      packages.${system} = {
        example-home = example.config.home-manager.users.example.home.activationPackage;
        example-system = example.config.system.build.toplevel;
      };
      devShells.${system} = import ./devshells { inherit pkgs; };
      formatter.${system} = pkgs.nixfmt;
      checks.${system} = import ./checks {
        inherit pkgs;
        host = example;
        home = example.config.home-manager.users.example;
      };
      templates = {
        python = {
          path = ./templates/python;
          description = "Python with uv, ruff and pyright";
        };
        go = {
          path = ./templates/go;
          description = "Go with gopls and delve";
        };
        bash = {
          path = ./templates/bash;
          description = "Bash with shellcheck and shfmt";
        };
        rust = {
          path = ./templates/rust;
          description = "Rust with cargo and rust-analyzer";
        };
        node = {
          path = ./templates/node;
          description = "Node.js with pnpm and TypeScript";
        };
        cpp = {
          path = ./templates/cpp;
          description = "C and C++ with gcc, cmake and gdb";
        };
        systems = {
          path = ./templates/systems;
          description = "LLVM, debuggers and tracers for systems work";
        };
        ai = {
          path = ./templates/ai;
          description = "CPU-first Python data science and PyTorch";
        };
      };
    };
}
