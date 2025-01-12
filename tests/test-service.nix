# { pkgs, self }:

# pkgs.nixosConfigurations.testVM = pkgs.lib.nixosSystem {
#   system = "x86_64-linux";
#   modules = [
#     ({ config, pkgs, lib, ... }: {
#       imports = [ ./service.nix ];  # Import your service definition

#       services.managed-docker-compose.enable = true;  # Enable the service in the VM
#       virtualisation.memorySize = 1024;  # Optional: set VM memory
#     })
#   ];
# }

# # {
# #   description = "Home Server";

# #   inputs = {
# #     nixpkgs.url = "nixpkgs/nixos-24.11";
# #   };

# #   outputs = { self, nixpkgs }: {

# #     nixosConfigurations.default = nixpkgs.lib.nixosSystem {
# #       system = "x86_64-linux";
# #       modules = [
# #         ./configuration.nix
# #         ./copy-configs-to-etc.nix
# #       ];
# #       specialArgs = {
# #         defaultGateway = "10.1.10.1";
# #         serviceIPs = {
# #           lyrion = "10.1.10.160";
# #         };
# #       };
# #     };
# #   };
# # }


# { pkgs ? import <nixpkgs> {} }:

# let
#   # Import the NixOS test framework
#   makeTest = import "${pkgs.path}/nixos/tests/make-test.nix";
# in
# makeTest {
#   name = "my-custom-service-test";
#   nodes = {
#     testNode = { config, pkgs, ... }: {
#       imports = [ ./service.nix ];
#       services.managed-docker-compose.enable = true;
#     };
#   };
#   testScript = ''
#     $testNode->start();
#     $testNode->waitForUnit("my-custom-service");
#     $testNode->succeed("systemctl is-active my-custom-service");
#   '';
# }

# {
#   # (import ./lib.nix) {
#   pkgs.testers.runNixOSTest {
#     name = "from-nixos";
    
#     # self here is set by using specialArgs in `lib.nix`
#     nodes.node1 = { self, pkgs, ... }: {
#       imports = [ self.nixosModules.managed-docker-compose ];
#       # environment.systemPackages = [];
#     };

#     # doCheck = true;

#     # This is the test code that will check if our service is running correctly:
#     testScript = ''
#       start_all()
#       # wait for our service to start
#       node1.wait_for_unit("managed-docker-compose")
#       node1.wait_for_open_port(8000)
#       #output = node1.succeed("curl localhost:8000/index.html")
#       # Check if our webserver returns the expected result
#       #assert "Hello world" in output, f"'{output}' does not contain 'Hello world'"
#       output = "foo"
#       assert "bar" in output
#     '';
#   };
# }


# test2:
# These arguments are provided by `flake.nix` on import, see checkArgs
{ pkgs, self }:
let
  inherit (pkgs) lib;
  nixos-lib = import (pkgs.path + "/nixos/lib") {};
in
# (pkgs.testers.runNixOSTest {
(nixos-lib.runTest {
  name = "from-nixos";
  hostPkgs = pkgs;

  # self here is set by using specialArgs in `lib.nix`
  nodes.node1 = { self, pkgs, ... }: {
    imports = [ self.nixosModules.managed-docker-compose ];
    # environment.systemPackages = [];
  };

  # doCheck = true;

  # This is the test code that will check if our service is running correctly:
  testScript = ''
    start_all()
    # wait for our service to start
    node1.wait_for_unit("managed-docker-compose")
    node1.wait_for_open_port(8000)
    #output = node1.succeed("curl localhost:8000/index.html")
    # Check if our webserver returns the expected result
    #assert "Hello world" in output, f"'{output}' does not contain 'Hello world'"
    output = "foo"
    assert "bar" in output
  '';
})

# (nixos-lib.runTest {
#   hostPkgs = pkgs;
#   # optional to speed up to evaluation by skipping evaluating documentation
#   defaults.documentation.enable = lib.mkDefault false;
#   # This makes `self` available in the nixos configuration of our virtual machines.
#   # This is useful for referencing modules or packages from your own flake as well as importing
#   # from other flakes.
#   node.specialArgs = { inherit self; };
#   imports = [ test ];
# }).config.result