# Nix Native Docker Compose Service

A Nix service that directly runs docker-compose.yaml files included in your nix config repo. The service takes care of fetching and starting up containers from Docker Compose files that are included in your config, and spinning down containers from Compose files that are no longer part of your config. This service does not use [virtualisation.oci-containers](https://mynixos.com/options/virtualisation.oci-containers), and instead uses Docker (or Podman) Compose directly.

# Installation

This package and service are designed to be used with flakes. To install, add the following lines to your flake.nix:

```
{
  inputs {
    managed-docker-compose.url = "github:efirestone/nix-managed-docker-compose/0.1.0";
    nixpkgs.url = "nixpkgs/nixos-24.11";
  };

  outputs = { self, nixpkgs, managed-docker-compose }: let
    system = "x86_64-linux";
  in {
    nixosConfigurations.myHost = nixpkgs.lib.nixosSystem {
      system = system;
      modules = [
        ./configuration.nix
        managed-docker-compose.nixosModules.${system}.managedDockerCompose
      ];
    };
  };
}
```

# Configuration

In your configuration, enable the service:

```
services.managedDockerCompose.enable = true;
```

You can also manually configure the backend to be "docker" or "podman". By default the service will use the value from `virtualisation.oci-containers.backend`, so you should only need to manually specify this configuration option if you want to use two different backends for containers defined via `virtualisation.oci-containers` and containers managed via `managed-docker-compose`.

```
# Not usually required
services.managedDockerCompose.backend = "docker";
```

## Usage
Below is a complete example usage:
```
  services.managedDockerCompose = {
    enable = true;
    # choose a name for your container
    projects.<name of container> = { 
      # make sure the docker compose file is in your git repo
      composeFile = ./path/to/docker-compose.yaml;
    };

    # Optional (not usually required):
    # backend = "docker";
  };
```

# Why Use Docker Compose Instead of Other Built-In Nix Options?

Nix is amazing for creating reproducible, well-documented builds, and works well for command line tools and general system definition. As a package manager, the story is more complicated.

In Nix, larger projects with dependencies can end up using the wrong dependency versions, it can be difficult to pull in the latest versions of projects, and many projects simply aren't available as native Nix packages yet. Flakes and initiatives like FlakeHub (which uses [semantic versioning](https://docs.determinate.systems/flakehub/#semver)) aim to improve this, but are still far from comprehensive. The Self-Hosted podcast provides similar thoughts about the Nix packaging landscape in [Episode 139](https://selfhosted.show/139?t=1492).

Nix does provide a way to fill out its ecosystem and avoid some of these issues: Docker containers. Using Nix' `virtualisation.oci-containers` config you can run Docker containers using either Docker or Podman. This works well for individual containers, but doesn't provide an easy way to group containers or define networks between them, similar to what Docker Compose does (see [Why Use Compose?](https://docs.docker.com/compose/intro/features-uses/)). The [compose2nix](https://github.com/aksiksi/compose2nix) project tries to bridge that gap, but it makes maintenance more difficult.

That's where the managed-docker-compose flake comes in: it lets you use docker-compose.yaml files directly, using the standard `docker compose` (or `podman compose`) tooling.

# Benefits of Docker Over Nix Packages

## Docker Is The Standard

Basically every project out there provides its own Docker container, or has a well-supported third party one available. They're generally easy to find, and kept up to date.

The fact that Docker images are the standard means that they're usually the official release vessel for a project, and are published at the same time a new project version is cut. In contrast, Nix packages are updated to new project versions more slowly, almost always by third-party maintainer. Those Nix packages are then officially published every six months with the stable nixpkgs releases. Outside of those official releases you can adopt the unstable versions, but that's often [cumbersome](https://discourse.nixos.org/t/how-to-install-a-previous-version-of-a-specific-package-with-configuration-nix/25551/18).

## Docker Images Are More Often Maintained by the Creators

Many projects provide their own Dockerfile directly in the project. And, importantly, they publish a new docker image whenever there's a new version as part of the version release. This means that there's always an up-to-date Docker image, and if there are any issues then they are addressed by the project maintainer quickly and correctly.

The Docker image being maintained by the project creators means that you can file bugs against it and expect them to be addressed quickly, and that there will never be friction between the project maintainers and the package maintainers (as has happened with [some Nix packages](https://nixos.wiki/wiki/Home_Assistant) in the past).

## Docker Images Better Control Their Dependencies

Docker images have an explicit build step, and that build step is usually executed as part of a CI job. This means that Docker creates a build artifact, which won't change, and then ideally tests are run against that artifact. If the tests succeed, then no changes to any of the dependencies used by that image will affect its behavior and invalidate that working functionality. (This assumes the image doesn't do any self-updating, which is against the Docker philosophy.)

By contrast, Nix is shipped as one giant release, with shared dependencies amongst packages. If Package A depends on Package B, and Package B changes, it doesn't appear that Package A gets re-tested, even though it changed. There are [some packages](https://hydra.nixos.org/job/nixos/release-24.11/tested#tabs-constituents) that have their tests run before each release, but it's far from comprehensive.

The way that Nix declares its package dependencies, without regard for semantic versioning, means that it's relatively easy for a Nix package to end up depending on a version which it was not supposed to. For example, let's say Project A is a Python project. In its [pyproject.toml](https://packaging.python.org/en/latest/guides/writing-pyproject-toml/) it declares that it depends on Python Project B, version 3.8 or later. At some point, a Nix package was created for Project A and all of those pyproject.toml dependencies were translated into Nix package dependencies (which do not include versions). The version of Project B in nixpkgs was version 3.8 or later, so everything works. Later, however, someone changes Project B to be version 4.0, which is mostly compatible with version 3, but might have some small breaking changes. There's nothing to verify that Project A still works in this case. Cursory testing might look fine, but the small incompatible changes that would have been caught by semantic versioning are still there, and may break in unexpected ways later.

With Docker, all dependencies are dictated by the pyproject.toml in the project. A version bump to a dependency there will run all of the project's CI tests and verify that everything remains functional.

## Docker Documentation and Community Are Better

Docker has been around for a while, and is widely used. If you need help getting Docker or Docker Compose working, it's likely that you can find existing documentation or previously asked questions that can help. And, if not, there are many communities where you can ask your question and get answers. By using this flake you're using standard Docker or Podman tooling, which will be familiar to those communities.

## Docker Tools Are More Mature

There is lots of tooling out there to make Docker better. For example, dashboards like [Portainer](https://www.portainer.io) or [Dockge](https://github.com/louislam/dockge) provide clear insight into how your services are running. And tools like [Renovate](https://docs.renovatebot.com) can help keep your images up to date automatically. These all work perfectly because we're using standard Docker tooling and Docker Compose definitions.

# What Do I Lose By Using Docker Over Nix Packages?

Nix packages do have advantages that are worth mentioning. It should be noted that running a Docker container directly using Nix' `virtualisation.oci-containers` does not have any of these advantages, only native Nix containers do. It should also be noted that some "native" Nix packages are implemented as Docker containers under the covers, which means that those packages also don't gain these advantages.

## Docker Images Are Bigger

Docker images bake in all of their dependencies. So two images that have the same dependency will both contain independent implementations on disk, doubling the space required. Although Docker layers can sometimes mitigate this, it's rare that two services actually use identical layers, so it rarely saves space in practice. The Nix package repo, on the other hand, generally has one canonical implementation of a package, and so there is a lot less duplication.

## You Need Two Sets of Tools

If you're running services using Nix containers, as well as running Docker containers, then you'll need two sets of tools to monitor, debug, and manage those containers. Nix packages are managed via `systemd` while Docker containers are managed via `dockerd`. Most larger services that need monitoring and managing can be run using Docker when using this flake (and we'd recommend doing so), but you will inevitably need to understand `systemd` for proper Nix administration.

## There Are Two Firewalls To Manage

If you run a service via a Nix package, it will often have a convenience property along the lines of `openFirewall = true;` in order to open the port for the service on the machine's firewall. This is an elegant solution which is possible because the package is running directly on the Nix machine.

Docker runs its own [bridge network](https://docs.docker.com/engine/network/) by default, and so in order to expose the port for a service you need to specify that port twice: once in the service definition of the docker-compose.yaml, and again in your Nix config so that it's exposed at the machine level. This can be avoided by using Docker host networking or MACVLAN networking, but there are still two systems at play which must be understood.

# Development

To test out any changes, run this at the repo root:

```
nix flake check -L --all-systems
```

## Better Logs and Debugging Timeouts

If you're having trouble figuring out why a test is failing, including in cases where the test is timing out for unclear reasons, it's often the case that the failure is farther up in the logs. The best way to view these logs is to:

1. Start the test using `--verbose`:

```
nix flake check --verbose --all-systems
```

This will print out the path to the derivation for the test. For the `dockerTest`, it will be something like `/nix/store/j2iaq6in46kippzdjviabcdef2564316-vm-test-run-dockerTest.drv`.

2. Let the test run up to a failure. If you're hitting a timeout, you don't necessarily need to let it hit the full timeout limit, but do let it run until all the useful work is done and the output consistently indicates that it's waiting on something.

3. View the logs using the store path from (1):

```
nix log /nix/store/j2iaq6in46kippzdjviabcdef2564316-vm-test-run-dockerTest.drv
```

Scroll through the logs and hopefully you'll be able to find the actual failure.

## Interactive Debugging

You can get an interactive shell for both the test environment, and the VMs within the test environment. This can be useful when you need to quickly look around and inspect the values you want to test for.

To run the Python test script interactively (this is for the `dockerTest` test on an `x86_64` machine):

```
nix run .#checks.x86_64-linux.dockerTest.driver -- --interactive
```

From here you can test various test helper commands.

Then from the python shell, if you want to get an interactive shell within one of the VMs (in this case the VM named `machine`), you can do so with:

```
>>> machine.wait_for_unit("managed-docker-compose.service")
>>> machine.shell_interact()
```

See [this article](https://blog.thalheim.io/2023/01/08/how-to-execute-nixos-tests-interactively-for-debugging/) for more.
