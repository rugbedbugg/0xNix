{ pkgs, ... }:
{
  # Ryzen 3 7320U / Radeon 610M. The running kernel already binds amdgpu.
  # Keep the installed firmware family and generated storage module.
  hardware.graphics.enable = true;
  # The kernel already detects the Bluetooth adapter as hci0. This runs the
  # BlueZ service that wireplumber and KDE Connect look for, and installs
  # bluetoothctl for pairing from a shell.
  hardware.bluetooth.enable = true;
  # The MediaTek MT7902 Wi-Fi card (14c3:7902) is unknown to 6.18's mt7921e;
  # 7.2 binds it with the MT7902 firmware already in linux-firmware.
  boot.kernelPackages = pkgs.linuxPackages_latest;
  services = {
    upower.enable = true;
    power-profiles-daemon.enable = true;
    libinput.enable = true;
  };
  environment.systemPackages = [ pkgs.brightnessctl ];
}
