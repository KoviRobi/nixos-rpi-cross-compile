{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  inputs.home-manager.url = "github:nix-community/home-manager";
  inputs.home-manager.inputs.nixpkgs.follows = "nixpkgs";

  inputs.kovirobi.url = "github:KoviRobi/nixos-config/flake";
  inputs.kovirobi.inputs.nixpkgs.follows = "nixpkgs";
  inputs.kovirobi.inputs.home-manager.follows = "home-manager";

  inputs.deploy-rs.url = "github:serokell/deploy-rs";

  outputs = { self, nixpkgs, home-manager, kovirobi, deploy-rs }: {

    nixosConfigurations.cross-vm = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = let system = "aarch64-linux"; in [
        ({ pkgs, lib, modulesPath, ... }: {
          nixpkgs = {
            crossSystem = lib.systems.examples.aarch64-multiplatform;
            overlays = builtins.attrValues kovirobi.overlays;
          };

          networking.hostName = "pi";
          networking.domain = "badger-toad.ts.net";
          networking.firewall.allowedUDPPorts = [ 53 67 68 ];
          networking.firewall.allowedTCPPorts = [ 53 ];
          networking.defaultGateway = { address = "192.168.0.1"; interface = "end0"; };
          networking.interfaces.end0 = {
            ipv4.addresses = [{ address = "192.168.0.38"; prefixLength = 24; }];
          };
          services.dnsmasq = {
            enable = true;
            settings = {
              interface = [ "end0" ];
              domain-needed = true;
              local = [ "/home/" ];
              server = [ "1.1.1.1" "1.0.0.1" ];
              dhcp-authoritative = true;
              dhcp-option = [ "option:router,192.168.0.1" ];
              dhcp-range = "192.168.0.10,192.168.0.254";
              dhcp-hostsdir = "/etc/dnsmasq-hosts";
              cache-size = "10000";
            };
          };

          imports = [ (modulesPath + "/installer/sd-card/sd-image-aarch64.nix") ];

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
            extraGroups = [ "wheel" ];
            openssh.authorizedKeys.keys = import "${kovirobi}/pubkeys.nix";
          };
          system.stateVersion = "22.11";

          security.sudo.wheelNeedsPassword = false;

          services.tailscale.enable = true;

          services.openssh.enable = true;
          services.openssh.settings.PermitRootLogin = "no";

          nix.settings.experimental-features = [ "nix-command" "flakes" ];
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

          environment.shellAliases.nixrepl =
            "nix repl --expr 'builtins.getFlake \"${self}\"'";

          environment.systemPackages = [ pkgs.python3 pkgs.python3.pkgs.pip ];
        })

        home-manager.nixosModule
        {
          # environment.systemPackages = [ home-manager.defaultPackage.${system} ];
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.rmk = {
            imports = kovirobi.homeModules.simple;
            home.stateVersion = "22.11";
            systemd.user.services.tmux-server.Install.WantedBy = [ "basic.target" ];
          };
        }
      ];
    };

    nixpkgs = import nixpkgs {
      system = "x86_64-linux";
      crossSystem = nixpkgs.lib.systems.examples.aarch64-multiplatform;
      overlays = builtins.attrValues kovirobi.overlays;
    };

    packages.x86_64-linux.default = self.nixosConfigurations.cross-vm.config.system.build.sdImage;

    deploy.nodes.pi = {
      sshUser = "rmk";
      user = "root";
      hostname = "pi.badger-toad.ts.net";
      profiles.system = {
        path = self.activate.nixos self.nixosConfigurations.cross-vm;
      };
    };

    # I've had to change the `deploy-rs` to use the one from `self.nixpkgs`
    # because that is cross-compiled.
    activate = rec {
      custom =
        {
          __functor = customSelf: base: activate:
            self.nixpkgs.buildEnv {
              name = ("activatable-" + base.name);
              paths =
                [
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

      nixos = base:
        (custom // {
          dryActivate = "$PROFILE/bin/switch-to-configuration dry-activate";
          boot = "$PROFILE/bin/switch-to-configuration boot";
        })
          base.config.system.build.toplevel
          ''
            # work around https://github.com/NixOS/nixpkgs/issues/73404
            cd /tmp

            $PROFILE/bin/switch-to-configuration switch

            # https://github.com/serokell/deploy-rs/issues/31
            ${with base.config.boot.loader;
            nixpkgs.lib.optionalString systemd-boot.enable
            "sed -i '/^default /d' ${efi.efiSysMountPoint}/loader/loader.conf"}
          '';

      home-manager = base: custom base.activationPackage "$PROFILE/activate";

      noop = base: custom base ":";
    };

  };
}
