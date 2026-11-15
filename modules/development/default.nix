{
  options,
  pkgs,
  ...
}:
{
  # Toolchain versions are defined once in devshells/default.nix. Fish is enabled
  # system-wide so it is registered as a valid login shell.
  programs.fish.enable = true;

  # Claude Code comes from Anthropic's install script, lives in ~/.local and
  # updates itself. Its binary is built for generic Linux, so nix-ld gives it
  # the dynamic loader it expects. The default libraries stay, and alsa-lib
  # backs its voice input. Its sandbox runs commands through bwrap and
  # proxies their network through socat, both looked up on PATH.
  programs.nix-ld = {
    enable = true;
    libraries = options.programs.nix-ld.libraries.default ++ [ pkgs.alsa-lib ];
  };
  environment.systemPackages = [
    pkgs.bubblewrap
    pkgs.socat
  ];
}
