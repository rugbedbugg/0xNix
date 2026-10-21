{ config, pkgs, ... }:
{
  # The original install's boot settings plus two additions: a three-entry boot
  # menu and the title rewrite below.
  # Building does not execute the boot installer. A switch still writes
  # loader.conf and may update shared EFI binaries.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # Keep the boot menu to the current generation and two fallbacks.
  boot.loader.systemd-boot.configurationLimit = 3;

  # Short boot menu titles: "NixOS <generation> (<kernel>) <created>".
  # Only the title changes; the version line still orders entries newest first.
  boot.loader.systemd-boot.extraInstallCommands = ''
    for entry in ${config.boot.loader.efi.efiSysMountPoint}/loader/entries/nixos-generation-*.conf; do
      gen=''${entry##*/nixos-generation-}
      gen=''${gen%%[-.]*}
      kernel=$(${pkgs.gnused}/bin/sed -n 's/^version .*(Linux \([^)]*\)).*/\1/p' "$entry")
      created=$(${pkgs.coreutils}/bin/date -d @"$(${pkgs.coreutils}/bin/stat -c %Y /nix/var/nix/profiles/system-$gen-link)" '+%F %R' 2>/dev/null) || created=
      ${pkgs.gnused}/bin/sed -i "s/^title .*/title NixOS $gen ($kernel) $created/" "$entry"
    done
  '';
}
