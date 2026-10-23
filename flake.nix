{
  description = "Pinned NixOS 26.05 Hyprland workstation";

  inputs = {
    # Exact revision used by the installed generation 1.
    nixpkgs.url = "github:NixOS/nixpkgs/26f4107e47e3ad0ffd0db220469ba83b6f6d96e8";
    # Deliberately NOT pinned/following the main nixpkgs: this is the escape
    # hatch for frequently updated packages that want to track upstream more
    # closely than the rest of this stable system. Bump just this input with
    # `nix flake update nixpkgs-unstable` when you want newer versions.
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
        # Frequently updated packages live in the user profile instead of the
        # system.
        # Updating them then needs no sudo and no new system generation:
        #   nix flake update nixpkgs-unstable --flake ~/0xNix
        #   nix profile upgrade --all
        # Install once with `nix profile add ~/0xNix#agents ~/0xNix#apps`.
        agents = pkgsUnstable.buildEnv {
          name = "agents";
          paths = with pkgsUnstable; [
            claude-code
            codex
            opencode
            antigravity-cli
            # Codex looks these up on PATH at runtime. It sandboxes commands
            # with bwrap, its Codex Security MCP server runs on node and the
            # Tableau plugin's startup hook builds a python3 venv.
            bubblewrap
            nodejs
            python3
          ];
        };
        # Keybinds launch vesktop and firefox from ~/.nix-profile/bin, so they
        # need this installed.
        apps = pkgsUnstable.buildEnv {
          name = "apps";
          paths = with pkgsUnstable; [
            vesktop
            awscli2
            # `aws ssm start-session` hands the session to this binary, so it
            # updates together with the CLI.
            ssm-session-manager-plugin
            firefox
            google-chrome
            microsoft-edge
          ];
        };
      };
    };
}
