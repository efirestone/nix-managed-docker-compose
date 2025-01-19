{
  description = "A nix service that runs docker-compose.yaml files included in your nix config repo.";

  inputs.nixpkgs.url = "nixpkgs/nixos-24.11-small";

  outputs = { self, nixpkgs }:
  let
    forEachSystem = nixpkgs.lib.genAttrs [
      "aarch64-linux"
      "x86_64-linux"
    ];

    overlayList = [ self.overlays.default ];
  in {
    # A Nixpkgs overlay that provides a 'managed-docker-compose' package.
    overlays.default = final: prev: { managed-docker-compose = final.callPackage ./package.nix {}; };

    packages = forEachSystem (system: {
      managed-docker-compose = nixpkgs.legacyPackages.${system}.callPackage ./package.nix {};
      default = self.packages.${system}.managed-docker-compose;
    });

    nixosModules = import ./nixos-modules { overlays = overlayList; };

    checks = forEachSystem (system: {
      # see: https://blog.thalheim.io/2023/01/08/how-to-execute-nixos-tests-interactively-for-debugging/
      # can run this test interactively by:
      # `nix run .#checks.x86_64-linux.moduleTest.driver -- --interactive`
      # then after being dropped into python shell:
      # >>> machine1.wait_for_unit("default.target")
      # >>> machine1.shell_interact()
      moduleTest = nixpkgs.legacyPackages.${system}.testers.runNixOSTest {
        name = "moduleTest";
        nodes.machine1 = {
          imports = [ self.outputs.nixosModules.managed-docker-compose ];

          # enable our custom module
          services.managed-docker-compose.enable = true;

          # our module requires these things (maybe it should enable them itself too?)
          virtualisation.docker.enable = true;
          environment.systemPackages = with nixpkgs.legacyPackages.${system}; [ 
            docker
            docker-compose
          ];

          # A default user able to use sudo
          users.users.guest = {
            isNormalUser = true;
            home = "/home/guest";
            extraGroups = [ "wheel" "docker" ];
            initialPassword = "guest";
          };

          security.sudo.wheelNeedsPassword = false;

          # Run a very lightweight image, but also one that doesn't immediately exit.
          environment.etc."docker-compose/hello/docker-compose.yaml".text = 
            ''
            services:
              myservice:
                image: docker.io/alpine:latest
                command: tail -f /dev/null
            '';
        };
        # TODO: need to make this into a non-trivial test!
        #       see: https://vtimofeenko.com/posts/practical-nix-flake-anatomy-a-guided-tour-of-flake.nix/#checks
        testScript = ''
          machine.wait_for_unit("default.target")
          assert "hello" == "hello"
        '';
      };
    });
  };
}
