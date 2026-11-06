# Boots the host in a QEMU VM and checks that a clean deployment comes up.
#
# The other checks evaluate or build the system. This one boots it. It
# catches a configuration that builds but fails at boot or at login:
# - a system unit that fails on a fresh machine
# - the user missing or without its login shell
# - a Home Manager activation that fails on first boot
# - an expected executable missing from the user profile or the system path
# - the display manager or Tailscale daemon not running
#
# The test reuses the host's own module list. The VM module replaces the
# laptop's UUID filesystems and the boot loader, so hardware-configuration.nix
# stays untouched. The graphical session is out of scope. A Hyprland login in
# a headless VM is too flaky to gate on, so the test stops at the units that
# start it.
#
# The `agents` and `apps` profiles are not installed here. `nix profile`
# needs the network and a large closure, and the build sandbox has neither.
# scripts/install-profiles.sh covers them.
#
# Run it locally, since it needs /dev/kvm and builds the whole system:
#   nix build .#checks.x86_64-linux.vm --max-jobs 2 --cores 2 -L
{
  pkgs,
  hostModules,
  hostSpecialArgs,
  vars,
}:
pkgs.testers.runNixOSTest {
  name = "0xnix-vm";

  # The host sets nixpkgs.config.allowUnfree itself, which a read-only test
  # nixpkgs would reject.
  node.pkgsReadOnly = false;
  node.specialArgs = hostSpecialArgs;

  nodes.machine =
    { ... }:
    {
      imports = hostModules;
      virtualisation = {
        memorySize = 4096;
        cores = 2;
        diskSize = 8192;
      };
    };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    with subtest("system units"):
        machine.succeed("systemctl is-active display-manager.service")
        machine.succeed("systemctl is-active tailscaled.service")
        machine.succeed("systemctl is-active NetworkManager.service")
        machine.fail("systemctl --failed --no-legend | grep .")

    with subtest("user and Home Manager"):
        machine.succeed("id ${vars.username}")
        machine.succeed("test \"$(getent passwd ${vars.username} | cut -d: -f7)\" = /run/current-system/sw/bin/fish")
        machine.wait_for_unit("home-manager-${vars.username}.service")
        machine.succeed("test -e /home/${vars.username}/.config/hypr/hyprland.lua")
        machine.succeed("test -e /home/${vars.username}/.config/waybar/config")

    with subtest("executables"):
        for name in ["fish", "git", "fuzzel", "Hyprland"]:
            machine.succeed(f"su - ${vars.username} -c 'command -v {name}'")
  '';
}
