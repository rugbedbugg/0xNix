# 0xNix

Reusable TTY-themed desktop and development modules.

## Modules

- Import `nixosModules.default` for the compositor, audio, portals and development integration.
- Import `homeManagerModules.default` through NixOS Home Manager for the desktop theme and applications.
- Set the account, home directory and state versions in the consuming configuration.
- Set `desktop.screen.width` and `desktop.screen.height` for the desired layout.

The `example` configuration uses fictional values for evaluation. It is not an installation target. Supply the machine configuration separately.

## Development

Use `nix develop` for the repository's formatters and linters. Start a project with `nix flake init -t .#python`. Templates are available for Python, Go, Bash, Rust, Node.js, C++, systems work and CPU-based AI work.

## Validation

```sh
nix flake check --no-build
nix build --no-link .#checks.x86_64-linux.python-scripts
nix build --no-link .#checks.x86_64-linux.desktop-config
```

The example does not describe a deployed host.
