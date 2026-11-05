{
  description = "Reusable TTY-themed desktop and development modules";
  inputs = {
    aws-agent-toolkit = {
      url = "github:aws/agent-toolkit-for-aws/7fcb1da17abba610d7becc973c2141b40412e02c";
      flake = false;
    };
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
asm-exec = pkgsUnstable.writeShellApplication {
        name = "asm-exec";
        runtimeInputs = [
          pkgsUnstable.python3
          pkgsUnstable.awscli2
        ];
        text = ''
          exec python3 ${aws-agent-toolkit}/plugins/aws-core/skills/aws-secrets-manager/references/asm-exec "$@"
        '';
      };
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
            # `aws ssm start-session` hands the session to this binary, so it
            # updates together with the CLI.
            ssm-session-manager-plugin
            asm-exec
            firefox
            google-chrome
            microsoft-edge
            zapfast
            # Both reach YouTube through yt-dlp, which breaks when YouTube
            # changes. Here it updates with the profile instead of waiting
            # for a rebuild.
            mpv
            youtube-tui
          ];
        };
      };
      templates = {
        ai = { path = ./templates/ai; description = "ai development environment"; };
        bash = { path = ./templates/bash; description = "bash development environment"; };
        cpp = { path = ./templates/cpp; description = "cpp development environment"; };
        go = { path = ./templates/go; description = "go development environment"; };
        node = { path = ./templates/node; description = "node development environment"; };
        python = { path = ./templates/python; description = "python development environment"; };
        rust = { path = ./templates/rust; description = "rust development environment"; };
        systems = { path = ./templates/systems; description = "systems development environment"; };
      };
    };
}
