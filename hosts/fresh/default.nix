{ ... }:
{
  imports = [
    ../common.nix
    ./disk-config.nix
  ];

  # No hardware scan exists for a fresh machine. These cover a virtual
  # machine and common SATA, NVMe and USB boot disks.
  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_blk"
    "ahci"
    "nvme"
    "xhci_pci"
    "usb_storage"
    "sd_mod"
  ];
  hardware.graphics.enable = true;
  hardware.enableRedistributableFirmware = true;

  # Distinct from the laptop and from its Arch install on Tailscale.
  networking.hostName = "nixos-fresh";
  services.tailscale.extraSetFlags = [ "--hostname=nixos-fresh" ];
}
