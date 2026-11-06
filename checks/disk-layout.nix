# Applies the fresh host's disk layout to an empty virtual disk, installs a
# minimal NixOS onto it and boots that disk.
#
# The layout is the one thing the fresh host adds below the shared desktop
# modules. This test shows that disko partitions, formats and mounts it and
# that systemd-boot starts from the result. It installs a minimal system
# rather than the desktop, which keeps the test short. The desktop boots in
# the vm-fresh check.
#
# Run it locally, since it needs /dev/kvm:
#   nix build .#checks.x86_64-linux.disk-layout -L
{ pkgs, disko }:
disko.lib.testLib.makeDiskoTest {
  inherit pkgs;
  name = "fresh-layout";
  disko-config = import ../hosts/fresh/disk-layout.nix { device = "/dev/vda"; };
  extraTestScript = ''
    machine.succeed("mountpoint /boot")
    machine.succeed("test \"$(findmnt -n -o FSTYPE /boot)\" = vfat")
    machine.succeed("test \"$(findmnt -n -o FSTYPE /)\" = ext4")
  '';
}
