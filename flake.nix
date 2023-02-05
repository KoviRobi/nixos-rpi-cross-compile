{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }: {

    nixosConfigurations.cross-vm = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ({ pkgs, lib, modulesPath, ... }: {
          nixpkgs = {
            crossSystem = lib.systems.examples.aarch64-multiplatform;
          };

          networking.hostName = "pi";
          networking.domain = "badger-toad.ts.net";

          imports = [ (modulesPath + "/installer/sd-card/sd-image-aarch64.nix") ];

          # Let 'nixos-version --json' know about the Git revision
          # of this flake.
          system.configurationRevision = nixpkgs.lib.mkIf (self ? rev) self.rev;

          users.mutableUsers = false;
          users.users.root = {
            hashedPassword = "$y$j9T$92t3XJPmBHWk1baoc0WTu/$DAC5AJseext1xVG7N0PK2tHYJ4L0qEZpbJleu1V5sS5";
          };
          users.users.user = {
            hashedPassword = "$y$j9T$92t3XJPmBHWk1baoc0WTu/$DAC5AJseext1xVG7N0PK2tHYJ4L0qEZpbJleu1V5sS5";
            isNormalUser = true;
            extraGroups = [ "wheel" ];
            openssh.authorizedKeys.keys = [
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHfojmpABobr3CEgN3eCu3mEqpr3oAs2h5NfY1ZtppIK ccl\\rmk@RMKW10L2"
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBxS1hIoi4jj4h00KoIfBJJX6aMF5TtdZZxBOqLRRKCH rmk35 pc id_ed25519"
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJCjMm+GhqvoboXvOJO/MuLccb606oJyHYyL4Mo3kuLO u0_a301@Legion Duel"
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKG9Dg3j/KJgDbtsUSyOJBF7+bQzfDQpLo4gqDX195rJ rmk@rmk-cc-pc-nixos-a"
            ];
          };
          system.stateVersion = "22.11";

          security.sudo.wheelNeedsPassword = false;

          services.tailscale.enable = true;

          services.openssh.enable = true;
          services.openssh.settings.PermitRootLogin = "no";
        })
      ];
    };

    packages.x86_64-linux.default = self.nixosConfigurations.cross-vm.config.system.build.sdImage;
  };

}
