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

          imports = [ (modulesPath + "/installer/sd-card/sd-image-aarch64.nix") ];

          # Let 'nixos-version --json' know about the Git revision
          # of this flake.
          system.configurationRevision = nixpkgs.lib.mkIf (self ? rev) self.rev;

          users.mutableUsers = false;
          users.users.root = {
            password = "root";
          };
          users.users.user = {
            password = "user";
            isNormalUser = true;
            extraGroups = [ "wheel" ];
          };
          system.stateVersion = "22.11";
        })
      ];
    };

    packages.x86_64-linux.default = self.nixosConfigurations.cross-vm.config.system.build.sdImage;
  };

}
