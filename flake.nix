{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  inputs.home-manager.url = "github:nix-community/home-manager";
  inputs.home-manager.inputs.nixpkgs.follows = "nixpkgs";

  inputs.kovirobi.url = "github:KoviRobi/nixos-config/flake";
  inputs.kovirobi.inputs.nixpkgs.follows = "nixpkgs";
  inputs.kovirobi.inputs.home-manager.follows = "home-manager";

  inputs.deploy-rs.url = "github:serokell/deploy-rs";

  inputs.nixos-hardware.url = "github:NixOS/nixos-hardware";

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      kovirobi,
      deploy-rs,
      nixos-hardware,
    }:
    let
      overlays = builtins.attrValues kovirobi.overlays ++ [
        (final: prev: {
          gitFull = prev.git.override {
            withSsh = true;
          };
        })
      ];
    in
    {

      nixosConfigurations.cross-vm = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules =
          let
            system = "aarch64-linux";
          in
          [
            (
              {
                pkgs,
                lib,
                modulesPath,
                ...
              }:
              {
                nixpkgs = {
                  crossSystem = lib.systems.examples.aarch64-multiplatform;
                  inherit overlays;
                };

                networking.hostName = "pi";
                networking.domain = "badger-toad.ts.net";
                networking.firewall.allowedUDPPorts = [
                  53
                  67
                  68
                ];
                networking.firewall.allowedTCPPorts = [ 53 ];
                networking.defaultGateway = {
                  address = "192.168.0.1";
                  interface = "end0";
                };
                networking.interfaces.end0 = {
                  ipv4.addresses = [
                    {
                      address = "192.168.0.38";
                      prefixLength = 24;
                    }
                  ];
                };
                services.dnsmasq = {
                  enable = true;
                  settings = {
                    interface = [ "end0" ];
                    domain-needed = true;
                    local = [ "/home/" ];
                    server = [
                      "1.1.1.1"
                      "1.0.0.1"
                    ];
                    dhcp-authoritative = true;
                    dhcp-option = [ "option:router,192.168.0.1" ];
                    dhcp-range = "192.168.0.10,192.168.0.254";
                    dhcp-hostsdir = "/etc/dnsmasq-hosts";
                    cache-size = "10000";
                  };
                };

                imports = [
                  "${nixos-hardware}/raspberry-pi/4"
                  (modulesPath + "/installer/sd-card/sd-image-aarch64.nix")
                ];

                hardware.raspberry-pi."4".fkms-3d.enable = true;

                # Let 'nixos-version --json' know about the Git revision
                # of this flake.
                system.configurationRevision = nixpkgs.lib.mkIf (self ? rev) self.rev;

                users.mutableUsers = false;
                users.users.root = {
                  hashedPassword = "$y$j9T$92t3XJPmBHWk1baoc0WTu/$DAC5AJseext1xVG7N0PK2tHYJ4L0qEZpbJleu1V5sS5";
                };
                users.users.rmk = {
                  hashedPassword = "$y$j9T$92t3XJPmBHWk1baoc0WTu/$DAC5AJseext1xVG7N0PK2tHYJ4L0qEZpbJleu1V5sS5";
                  isNormalUser = true;
                  extraGroups = [
                    "wheel"
                    "dialout"
                    "video"
                    "tty"
                  ];
                  openssh.authorizedKeys.keys = builtins.attrValues (import "${kovirobi}/pubkeys.nix");
                };
                system.stateVersion = "22.11";

                security.sudo.wheelNeedsPassword = false;

                services.tailscale.enable = true;

                services.openssh.enable = true;
                services.openssh.settings.PermitRootLogin = "no";

                nix.settings.experimental-features = [
                  "nix-command"
                  "flakes"
                ];
                nix.settings.trusted-public-keys = [
                  "pc-nixos-a-1:2ajz3MCJ5lorXbQ5JcRoneIYBNbssblrwPgdanqE07g="
                  "rmk-cc-pc-nixos-a:0hnzFy2JuBXDEwmfNf6UHDO0uTAQ69Z1aryW62z+AWs="
                ];
                nix.registry.nixpkgs.flake = nixpkgs;
                nix.registry.nixos-config.flake = self;

                nix.nixPath = [
                  "nixpkgs=${nixpkgs}"
                  "home-manager=${home-manager}"
                  "${nixpkgs}"
                ];

                environment.shellAliases.nixrepl = "nix repl --expr 'builtins.getFlake \"${self}\"'";

                environment.systemPackages = [
                  pkgs.python3
                  pkgs.python3.pkgs.pip
                  pkgs.wol
                ];

                boot.supportedFilesystems = lib.mkForce [
                  "vfat"
                  "f2fs"
                  "xfs"
                  "ntfs"
                  "cifs"
                  "ext4"
                ];
                boot.loader.generic-extlinux-compatible.enable = true;
              }
            )

            home-manager.nixosModule
            {
              # environment.systemPackages = [ home-manager.defaultPackage.${system} ];
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.rmk = {
                imports = kovirobi.homeModules.simple;
                home.stateVersion = "22.11";
                systemd.user.services.tmux-server.Install.WantedBy = [ "basic.target" ];
                programs.git.signing.format = "ssh";
              };
            }
          ];
      };

      nixpkgs = import nixpkgs {
        system = "x86_64-linux";
        crossSystem = nixpkgs.lib.systems.examples.aarch64-multiplatform;
        inherit overlays;
      };

      packages.x86_64-linux.default = self.nixosConfigurations.cross-vm.config.system.build.sdImage;

      deploy.nodes.pi = {
        sshUser = "rmk";
        user = "root";
        hostname = "pi.badger-toad.ts.net";
        fastConnection = true;
        profiles.system = {
          path = self.activate.nixos self.nixosConfigurations.cross-vm;
        };
      };

      # I've had to change the `deploy-rs` to use the one from `self.nixpkgs`
      # because that is cross-compiled.
      activate = rec {
        custom = {
          __functor =
            customSelf: base: activate:
            self.nixpkgs.buildEnv {
              name = ("activatable-" + base.name);
              paths = [
                base
                (self.nixpkgs.writeTextFile {
                  name = base.name + "-activate-path";
                  text = ''
                    #!${self.nixpkgs.runtimeShell}
                    set -euo pipefail

                    if [[ "''${DRY_ACTIVATE:-}" == "1" ]]
                    then
                        ${customSelf.dryActivate or "echo ${self.nixpkgs.writeScript "activate" activate}"}
                    elif [[ "''${BOOT:-}" == "1" ]]
                    then
                        ${customSelf.boot or "echo ${self.nixpkgs.writeScript "activate" activate}"}
                    else
                        ${activate}
                    fi
                  '';
                  executable = true;
                  destination = "/deploy-rs-activate";
                })
                (self.nixpkgs.writeTextFile {
                  name = base.name + "-activate-rs";
                  text = ''
                    #!${self.nixpkgs.runtimeShell}
                    exec ${self.nixpkgs.deploy-rs}/bin/activate "$@"
                  '';
                  executable = true;
                  destination = "/activate-rs";
                })
              ];
            };
        };

        nixos =
          base:
          (
            custom
            // {
              dryActivate = "$PROFILE/bin/switch-to-configuration dry-activate";
              boot = "$PROFILE/bin/switch-to-configuration boot";
            }
          )
            base.config.system.build.toplevel
            ''
              # work around https://github.com/NixOS/nixpkgs/issues/73404
              cd /tmp

              $PROFILE/bin/switch-to-configuration switch

              # https://github.com/serokell/deploy-rs/issues/31
              ${
                with base.config.boot.loader;
                nixpkgs.lib.optionalString systemd-boot.enable "sed -i '/^default /d' ${efi.efiSysMountPoint}/loader/loader.conf"
              }
            '';

        home-manager = base: custom base.activationPackage "$PROFILE/activate";

        noop = base: custom base ":";
      };

      netboot =
        let
          buildPkgs = nixpkgs.legacyPackages.x86_64-linux;
          netboot-system = self.nixosConfigurations.cross-vm;
          kernel-cmdline = [ "init=${toplevel}/init" ] ++ netboot-system.config.boot.kernelParams;
          inherit (netboot-system.config.system.build) kernel initialRamdisk toplevel;
        in
        buildPkgs.writeShellApplication {
          name = "netboot";
          text = ''
            cat <<EOF
            Don't forget to open the following ports in the firewall:
            UDP: 67 69 4011
            TCP: 64172

            This can be done via

                sudo iptables -I nixos-fw 1 -i enp4s0 -p udp -m udp --dport 67    -j nixos-fw-accept
                sudo iptables -I nixos-fw 2 -i enp4s0 -p udp -m udp --dport 69    -j nixos-fw-accept
                sudo iptables -I nixos-fw 3 -i enp4s0 -p udp -m udp --dport 4011  -j nixos-fw-accept
                sudo iptables -I nixos-fw 4 -i enp4s0 -p tcp -m tcp --dport 64172 -j nixos-fw-accept

            (change enp4s0 to the interface you are using).

            And once you are done, closed via

                sudo iptables -D nixos-fw -i enp4s0 -p udp -m udp --dport 67    -j nixos-fw-accept
                sudo iptables -D nixos-fw -i enp4s0 -p udp -m udp --dport 69    -j nixos-fw-accept
                sudo iptables -D nixos-fw -i enp4s0 -p udp -m udp --dport 4011  -j nixos-fw-accept
                sudo iptables -D nixos-fw -i enp4s0 -p tcp -m tcp --dport 64172 -j nixos-fw-accept

            If you need to do DHCP also, consider

                sudo ip addr add 192.168.10.1/24 dev enp4s0
                sudo nix run 'nixpkgs#dnsmasq' -- \\
                  --interface enp4s0 \\
                  --dhcp-range 192.168.10.10,192.168.10.254 \\
                  --dhcp-leasefile=dnsmasq.leases \\
                  --no-daemon
            EOF
            nix run nixpkgs\#pixiecore -- \
              boot ${kernel}/bzImage ${initialRamdisk}/initrd \
              --cmdline "${builtins.concatStringsSep " " kernel-cmdline}" \
              --debug --dhcp-no-bind --port 64172 --status-port 64172 \
              "$@"
          '';
        };

    };
}
