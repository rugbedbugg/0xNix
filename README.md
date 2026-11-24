# 0xNix

TTY-themed desktop rice for Hyprland on NixOS.

## Modules

- Import `homeManagerModules.default` through the NixOS Home Manager module.
- Configure the compositor, UWSM, audio and portals in the host configuration. The rice reads NixOS options through `osConfig`.
- Set the account, home directory and state versions separately.
- Set `desktop.screen.width` and `desktop.screen.height` for the desired layout.

Keep application installation, language servers, development environments and machine services outside the rice.

## Appearance and interaction

- Keep the shared colours in `palette.nix`.
- Use the bars, launcher, notifications, wallpaper switcher, minimap and CRT controls as one desktop layout.
- Style foot, Fish, Starship, GTK and Qt with the VGA-inspired palette.
- Enable optional applications separately to apply their Vim, Neovim, lf, fastfetch, btop, tmux, Zathura and mpv themes. Enable `desktop.applicationThemes.zapfast.enable` to write the ZapFast theme without installing it.
- Set `desktop.launches` for tiled and floating application bindings. Supply raw shell commands. The launcher wraps each command in UWSM once.
- Set `desktop.overlays` for application toggles. Add companion window classes with `desktop.overlayWindows` to share the frame and reload geometry.
- Extend the bottom bar with `desktop.bottomBar.modules`, `modulesCenter`, `modulesRight` and `style`.
- Add executables to `desktop.wallpaperHooks` to receive the selected image path.

Keep the default terminal and scratch-terminal bindings or replace their option lists. Use unique toggle classes, workspace names and binding keys.

## Validation

```sh
nix flake check --no-build
nix fmt -- --check $(git ls-files '*.nix')
nix build --no-link .#checks.x86_64-linux.rice-scope
nix build --no-link .#checks.x86_64-linux.python-scripts
nix build --no-link .#checks.x86_64-linux.desktop-config
nix build --no-link .#checks.x86_64-linux.themed-applications
```

Use the internal fictional fixtures only for validation. No system deployment, application package set, development shell or project template is exported.
