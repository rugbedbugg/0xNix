{
  description = "Reusable TTY-themed desktop and development modules";
  inputs = {
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs = {
      url = "github:NixOS/nixpkgs/26f4107e47e3ad0ffd0db220469ba83b6f6d96e8";
    };
    nixpkgs-unstable = {
      url = "github:NixOS/nixpkgs/nixos-unstable";
    };
  };
  outputs = inputs@{ nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; config.allowUnfree = true; };
      pkgsUnstable = import inputs.nixpkgs-unstable { inherit system; config.allowUnfree = true; };
      aws-agent-toolkit = inputs.aws-agent-toolkit or null;

    in
    {
      nixosModules.default = { imports = [ ./modules/desktop ./modules/development ]; };
      homeManagerModules.default = { pkgs, ... }: {
        imports = [ ./home ./home/options.nix ];
        _module.args = {
          palette = if builtins.pathExists ./palette.nix then import ./palette.nix else { };
          pkgs-unstable = import inputs.nixpkgs-unstable { system = pkgs.stdenv.hostPlatform.system; config.allowUnfree = true; };
          aws-agent-toolkit = inputs.aws-agent-toolkit or null;
        };
      };
      formatter.${system} = pkgs.nixfmt;
      devShells.${system} = import ./devshells { inherit pkgs; };
      packages.${system} = {
agents = pkgsUnstable.buildEnv {
          name = "agents";
          paths = with pkgsUnstable; [
            claude-code
            codex
            opencode
            antigravity-cli
            # Codex looks these up on PATH at runtime. It sandboxes commands
            # with bwrap. Its plugins use Node.js and Python.
            bubblewrap
            nodejs
            python3
          ];
        };
apps = pkgsUnstable.buildEnv {
          name = "apps";
          paths = with pkgsUnstable; [
            vesktop
            awscli2
            firefox
            google-chrome
            microsoft-edge
          ];
        };
      };
    };
}
