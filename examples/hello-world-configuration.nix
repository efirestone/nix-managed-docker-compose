# credit: https://github.com/jecaro/simple-nix-vm/blob/master/vm.nix
#
# Build this VM with nix build  ./#nixosConfigurations.vm.config.system.build.vm
# Then run is with: ./result/bin/run-nixos-vm
# To be able to connect with ssh enable port forwarding with:
# QEMU_NET_OPTS="hostfwd=tcp::2222-:22" ./result/bin/run-nixos-vm
# Then connect with ssh -p 2222 guest@localhost
{ lib, config, pkgs, ... }:
{

  virtualisation.docker.enable = true;

  environment.systemPackages = with pkgs; [ 
    docker
    docker-compose
  ];

  # got a small docker compose from here:
  #  https://stackoverflow.com/questions/71719908/what-is-the-smallest-image-that-can-be-used-to-leave-docker-compose-running-inde
  environment.etc."docker-compose/hello/docker-compose.yaml".text = 
    ''
    version: '3.9'
    services:
      myservice:
        image: registry.hub.docker.com/alpine:latest
        command: tail -f /dev/null
    '';

  # and now enable our custom module
  services.managed-docker-compose.enable = true;

  # Internationalisation options
  i18n.defaultLocale = "en_US.UTF-8";

  # Options for the screen
  virtualisation.vmVariant = {
    virtualisation.resolution = {
      x = 1280;
      y = 1024;
    };
    virtualisation.qemu.options = [
      # Better display option
      "-vga virtio"
      "-display gtk,zoom-to-fit=false,show-cursor=on"
      # Enable copy/paste
      # https://www.kraxel.org/blog/2021/05/qemu-cut-paste/
      "-chardev qemu-vdagent,id=ch1,name=vdagent,clipboard=on"
      "-device virtio-serial-pci"
      "-device virtserialport,chardev=ch1,id=ch1,name=com.redhat.spice.0"
    ];
  };

  # A default user able to use sudo
  users.users.guest = {
    isNormalUser = true;
    home = "/home/guest";
    extraGroups = [ "wheel" "docker" ];
    initialPassword = "guest";
  };

  security.sudo.wheelNeedsPassword = false;

  # Enable ssh
  services.sshd.enable = true;


  
  # Stub options (mostly only necessary to get `nix flake check` to work, since this config is usually only run in a vm`)
  fileSystems."/".device = "/dev/sda";
  boot.loader.grub.devices = [ "/" ];

  system.stateVersion = "24.11";

}