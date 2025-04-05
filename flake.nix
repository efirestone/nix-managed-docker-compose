{
  description = "A nix service that runs docker-compose.yaml files included in your nix config repo.";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-24.11-small";
    flake-utils.url = "github:numtide/flake-utils";

    substitute-vars = {
      url = "github:efirestone/nix-substitute-vars/d426080";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, substitute-vars, ... }:
    {
      # Reusable module
      nixosModules.default = import ./module.nix;

      # Library interface (pass config → get derivation)
      lib.makePackage = { pkgs, config }: import ./lib.nix { inherit pkgs config; };

      nixosTests = flake-utils.lib.eachDefaultSystem (system:
        let
          pkgs = import nixpkgs { inherit system; };
          test = import ./tests/basic.nix { inherit pkgs; myPkgLib = self.lib; };
        in {
          nixosModules.default = import ./module.nix;
          lib.makePackage = { pkgs, config }: import ./lib.nix { inherit pkgs config; };

          # Run test on `nix flake check`
          checks.myPkg-test = test;
        }
        # managedDockerComposeTest = import ./tests/my-service-test.nix {
        #   inherit system;
        #   nixpkgs = pkgs;
        #   myService = self;
        # };
      );

      checks = flake-utils.lib.eachDefaultSystem (system:
        # let
        #   tests = self.nixosTests.${system}.managedDockerComposeTest;
        # in
        #   # Add the VM test to flake checks
        #   tests
        self.nixosTests.${system}.managedDockerComposeTest
      );
      # checks = flake-utils.lib.eachDefaultSystem (system:
      #   # let
      #   #   module = self.outputs.nixosModules.managed-docker-compose;
      #   #   tests = import ./tests/tests.nix {
      #   #     inherit module nixpkgs system;
      #   #   };
      #   # in
      #     tests
      # );
    };
}


#     let
#       supportedSystems = [ "x86_64-linux" "aarch64-linux" ];

#       forEachSystem = f:
#         nixpkgs.lib.genAttrs supportedSystems (system:
#           f { inherit system; pkgs = import nixpkgs { inherit system; }; });

#       overlayList = [ self.overlays.default ];
#   # in {
#   #   # A Nixpkgs overlay that provides a 'managed-docker-compose' package.
#   #   # overlays.default = final: prev: { managed-docker-compose = final.callPackage ./package.nix {}; };

#     in {
#         #   # A Nixpkgs overlay that provides a 'managed-docker-compose' package.
#       # overlays.default = final: prev: { managed-docker-compose = final.callPackage ./package.nix {}; };

#       # packages = forEachSystem ({ system, pkgs }: {
#       #   managed-docker-compose = nixpkgs.legacyPackages.${system}.callPackage ./package.nix {};
#       #   default = self.packages.${system}.managed-docker-compose;
#       # });

#       nixosModules.managed-docker-compose = { config, pkgs, lib, ... }@args:
#         # let
#         #   substituteVars = substitute-vars.lib.substituteVars;
#         # in 
#         # import ./nixos-modules (args // { inherit substituteVars; overlays = overlayList; });
#         import ./nixos-modules (args // { overlays = overlayList; });
#         # let
#         #   internalHelpers = import ./lib/helpers.nix;
#         # in
#         # import ./nixos-modules/my-service.nix (args // { inherit internalHelpers; });

#       # nixosTests = forEachSystem ({ system, pkgs }: {
#       #   myServiceTest = import ./tests/tests.nix {
#       #     inherit system;
#       #     nixpkgs = pkgs;
#       #     myService = self;
#       #   };
#       # });

#       nixosTests = forEachSystem ({ system, pkgs }: {
#         managedDockerComposeTest = import ./tests/tests.nix {
#           inherit system;
#           nixpkgs = pkgs;
#           module = self.nixosModules.managed-docker-compose;
#         };
#       });

#       checks = forEachSystem ({ system, pkgs }:
#         # let
#         #   tests = self.nixosTests.${system}.managedDockerComposeTest;
#         # in
#         #   # Add the VM test to flake checks
#         #   tests
#         self.nixosTests.${system}.managedDockerComposeTest
#       );

#       # nixosTests = forEachSystem ({ system, pkgs }: {
#       #   myServiceTest = import ./tests/my-service-test.nix {
#       #     inherit system;
#       #     nixpkgs = pkgs;
#       #     myService = self;
#       #   };
#       # });
#       # checks = forEachSystem ({ system, pkgs }: {
#       #   let
#       #     module = self.outputs.nixosModules.managed-docker-compose;
#       #     tests = import ./tests/tests.nix {
#       #       inherit module nixpkgs system;
#       #     };
#       #   in
#       #     tests
#       # });
#     };
#   # outputs = { self, nixpkgs, substitute-vars }:
#   # let
#   #   forEachSystem = nixpkgs.lib.genAttrs [
#   #     "aarch64-linux"
#   #     "x86_64-linux"
#   #   ];

#   #   # overlayList = [ self.overlays.default ];
#   # in {
#   #   # A Nixpkgs overlay that provides a 'managed-docker-compose' package.
#   #   # overlays.default = final: prev: { managed-docker-compose = final.callPackage ./package.nix {}; };

#   #   # packages = forEachSystem (system: {
#   #   #   managed-docker-compose = nixpkgs.legacyPackages.${system}.callPackage ./package.nix {};
#   #   #   default = self.packages.${system}.managed-docker-compose;
#   #   # });

#   #   nixosModules.managed-docker-compose = { config, pkgs, lib, ... }@args:
#   #     let
#   #       substituteVars = substitute-vars.lib.substituteVars;
#   #     in 
#   #     import ./nixos-modules (args // { inherit substituteVars; });# overlays = overlayList; });

#   #   checks = forEachSystem (system:
#   #   let
#   #     module = self.outputs.nixosModules.managed-docker-compose;
#   #     tests = import ./tests/tests.nix {
#   #       inherit module nixpkgs system;
#   #     };
#   #   in
#   #     tests
#   #   );
#   # };
# }



# # {
# #   # description = "Reusable NixOS service with internal specialArgs and VM test";

# #   # inputs.nixpkgs.url = "nixpkgs";

# #   outputs = { self, nixpkgs, ... }: let
# #     system = "x86_64-linux";
# #   in {
# #     nixosModules.myService = { config, pkgs, lib, ... }@args:
# #       let
# #         internalHelpers = import ./lib/helpers.nix;
# #       in
# #       import ./nixos-modules/my-service.nix (args // { inherit internalHelpers; });

# #     nixosTests.myServiceTest = import ./tests/my-service-test.nix {
# #       inherit system nixpkgs self;
# #       myService = self;
# #     };
# #   };
# # }

# # {
# #   description = "Reusable NixOS service with internal specialArgs and VM tests for multiple architectures";

# #   inputs.nixpkgs.url = "nixpkgs";

# #   outputs = { self, nixpkgs, ... }:
# #     let
# #       supportedSystems = [ "x86_64-linux" "aarch64-linux" ];

# #       forEachSystem = f:
# #         nixpkgs.lib.genAttrs supportedSystems (system:
# #           f { inherit system; pkgs = import nixpkgs { inherit system; }; });

# #     in {
# #       nixosModules.myService = { config, pkgs, lib, ... }@args:
# #         let
# #           internalHelpers = import ./lib/helpers.nix;
# #         in
# #         import ./nixos-modules/my-service.nix (args // { inherit internalHelpers; });

# #       nixosTests = forEachSystem ({ system, pkgs }: {
# #         myServiceTest = import ./tests/my-service-test.nix {
# #           inherit system;
# #           nixpkgs = pkgs;
# #           myService = self;
# #         };
# #       });
# #     };
# # }
