{
  description = "Pinned NixOS 26.05 Hyprland workstation";

  inputs = {
    # Follows the stable 26.05 channel. The lock file pins the exact revision.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    # Deliberately NOT pinned/following the main nixpkgs: this is the escape
    # hatch for packages that want to track upstream more closely than the
    # rest of this stable system. They install through the system and home
    # config. Bump just this input with `nix flake update nixpkgs-unstable`
    # and rebuild when you want newer versions.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Partitions and formats the disk of a fresh install (hosts/fresh).
    disko = {
      url = "github:nix-community/disko/cedd626e11b635470fa6f9fdb8ad79b0075dd7f9";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    aws-agent-toolkit = {
      url = "github:aws/agent-toolkit-for-aws/7fcb1da17abba610d7becc973c2141b40412e02c";
      flake = false;
    };
    # Public YARA rules for the system scanner. The lock file pins the exact
    # revision. Bump it with `nix flake update signature-base`.
    signature-base = {
      url = "github:Neo23x0/signature-base";
      flake = false;
    };
    ly-lock = {
      url = "github:rugbedbugg/ly-lock";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    aurora = {
      url = "github:rugbedbugg/aurora";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
      disko,
      aws-agent-toolkit,
      signature-base,
      ly-lock,
      aurora,
      ...
    }:
    let
      system = "x86_64-linux";
      vars = import ./vars.nix;
      palette = import ./palette.nix;
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      pkgsUnstable = import nixpkgs-unstable {
        inherit system;
        config.allowUnfree = true;
      };
      hostSpecialArgs = {
        pkgs-unstable = pkgsUnstable;
        inherit
          vars
          palette
          aws-agent-toolkit
          signature-base
          ;
      };
      commonModules = [
        # The commit this system was built from, which the bar's Nix
        # tooltip reads. A build from a dirty tree gets the commit with
        # "-dirty" on the end.
        { system.configurationRevision = self.rev or self.dirtyRev or null; }
        home-manager.nixosModules.home-manager
        ly-lock.nixosModules.default
        aurora.nixosModules.default
      ];
      hostModules = commonModules ++ [ ./hosts/nixos ];
      freshModules = commonModules ++ [
        disko.nixosModules.disko
        ./hosts/fresh
      ];
      host = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = hostSpecialArgs;
        modules = hostModules;
      };
    in
    {
      nixosConfigurations = {
        nixos = host;
        # A machine installed from this flake onto an empty disk. Unlike
        # nixos, it has no pinned storage layout.
        fresh = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = hostSpecialArgs;
          modules = freshModules;
        };
      };
      devShells.${system} = import ./devshells { inherit pkgs; };
      # Per-project dev shells. Start one with `nix flake init -t ~/0xNix#python`
      # and run `direnv allow`.
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
      formatter.${system} = pkgs.nixfmt;
      checks.${system} = import ./checks {
        inherit
          pkgs
          disko
          host
          hostModules
          freshModules
          hostSpecialArgs
          vars
          ;
      };
      packages.${system} = {
        system = host.config.system.build.toplevel;
        home = host.config.home-manager.users.${vars.username}.home.activationPackage;
      };
    };
}
