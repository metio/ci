# SPDX-FileCopyrightText: The ci Authors
# SPDX-License-Identifier: 0BSD

# This repo ships the reusable workflows, composite actions, and convention
# policies — not the nix toolchain. That moved to metio/nix-devshell, which owns
# `lib.mkDevShell`, the from-source Go tools, and the Nix-installer action. This
# flake is now just a thin consumer: it builds this repo's own devShell (the
# shared lint gate plus conftest, for running the policy tests locally) from
# `devshell.lib.mkDevShell`, exactly as every other metio repo does.
{
  description = "metio shared CI: reusable workflows, composite actions, and convention policies";

  inputs = {
    devshell.url = "github:metio/nix-devshell";
    nixpkgs.follows = "devshell/nixpkgs";
    flake-compat.follows = "devshell/flake-compat";
  };

  outputs =
    { nixpkgs, devshell, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      # Dogfoods the shared devShell: conftest runs the policy tests, the rest of
      # the lint gate comes from mkDevShell.
      devShells = forAllSystems (pkgs: {
        default = devshell.lib.mkDevShell {
          inherit pkgs;
          packages = [ pkgs.conftest ];
          menu = ''echo "  plus conftest for the convention policies (policy/)."'';
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-rfc-style);
    };
}
