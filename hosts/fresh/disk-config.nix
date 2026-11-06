# Storage for a machine installed from this flake. It wipes the whole disk
# named by `fresh.disk` when disko applies it, so the option defaults to the
# first virtio disk. That name exists only in a virtual machine. A real
# install must set it to a dedicated disk. Never point it at the disk of the
# laptop in hosts/nixos, which holds a second operating system.
{ lib, config, ... }:
{
  options.fresh.disk = lib.mkOption {
    type = lib.types.str;
    default = "/dev/vda";
    description = "Block device that disko partitions and formats.";
  };

  config = import ./disk-layout.nix { device = config.fresh.disk; };
}
