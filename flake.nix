# SPDX-FileCopyrightText: The ci Authors
# SPDX-License-Identifier: 0BSD

# The shared metio development environment. Every repo's flake consumes this as
# an input and builds its devShell from `ci.lib.mkDevShell`, so the lint gate
# (reuse, typos, yamllint, actionlint, shellcheck, markdownlint) is defined once
# here instead of copied into each flake, and the three Go tools nixpkgs does
# not ship (arch-go, modernize, helm-schema) are built from source in one place
# — this repo's `update-flake.yml` keeps their versions + hashes current, and a
# consuming repo picks the update up by bumping its `ci` flake input (Renovate
# lock maintenance).
#
# A repo's flake becomes:
#
#   inputs.ci.url = "github:metio/ci";
#   inputs.nixpkgs.follows = "ci/nixpkgs";   # one nixpkgs pin, org-wide
#   outputs = { nixpkgs, ci, ... }: {
#     devShells.<sys>.default = ci.lib.mkDevShell {
#       pkgs = nixpkgs.legacyPackages.<sys>;
#       packages = [ … repo-specific tools + gate commands … ];
#       env.KUBEBUILDER_ASSETS = "${ci.lib.kubebuilderAssets pkgs}";  # controllers only
#     };
#   };
{
  description = "metio shared CI: a reusable devShell plus the Go tools nixpkgs lacks";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-compat.url = "github:edolstra/flake-compat";
  };

  outputs =
    { self, nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # dadav/helm-schema (docs chart-values reference). Tags carry no `v`.
      helm-schema =
        pkgs:
        pkgs.buildGoModule rec {
          pname = "helm-schema";
          version = "0.23.4";
          src = pkgs.fetchFromGitHub {
            owner = "dadav";
            repo = "helm-schema";
            rev = version;
            hash = "sha256-btkkNzye9if4lF/YdhalbwA2/dcZArU6/9Hr0bTJf1M=";
          };
          vendorHash = "sha256-jbK+XD5CbjMQJUJCcKbNN8LhYuhuy+Z3XcCmgiYw25Y=";
        };

      # arch-go (architecture rules, arch-go.yml).
      arch-go =
        pkgs:
        pkgs.buildGoModule rec {
          pname = "arch-go";
          version = "2.1.2";
          src = pkgs.fetchFromGitHub {
            owner = "arch-go";
            repo = "arch-go";
            rev = "v${version}";
            hash = "sha256-clwVZ/5PwUiD1LzRG6jGghQWcWZP3Pj3CzrdZiHUrIQ=";
          };
          vendorHash = "sha256-xIf+Ty1Pqa3oqqFLFsOv8Jz2bLOaIF+kjfGao05FhrM=";
        };

      # modernize (newer-Go idiom check), a subpackage of x/tools' gopls module.
      modernize =
        pkgs:
        pkgs.buildGoModule rec {
          pname = "modernize";
          version = "0.47.0";
          src = pkgs.fetchFromGitHub {
            owner = "golang";
            repo = "tools";
            rev = "v${version}";
            hash = "sha256-JfrmKeIAhHhxMqOfh27w+T9PaBAIzh47wOokXmr1Z5Q=";
          };
          modRoot = "gopls";
          subPackages = [ "internal/analysis/modernize/cmd/modernize" ];
          vendorHash = "sha256-GF9KSCr2aMjczVKz9H2t5Gc2kF0wqmKenO7qa8TQw4o=";
        };

      # controller-runtime envtest wants a dir holding etcd, kube-apiserver, and
      # kubectl. Assemble it from nixpkgs so a controller's tests run offline
      # against the flake-pinned Kubernetes, no setup-envtest download.
      kubebuilderAssets =
        pkgs:
        pkgs.runCommand "kubebuilder-assets" { } ''
          mkdir -p $out
          ln -s ${pkgs.etcd}/bin/etcd $out/etcd
          ln -s ${pkgs.kubernetes}/bin/kube-apiserver $out/kube-apiserver
          ln -s ${pkgs.kubectl}/bin/kubectl $out/kubectl
        '';

      # The lint gate every metio repo shares, byte-for-byte.
      lintTools =
        pkgs: with pkgs; [
          reuse
          typos
          yamllint
          actionlint
          shellcheck # actionlint shells out to it for run: blocks
          markdownlint-cli2
        ];

      # Assemble a repo's devShell: the shared lint gate plus the repo's own
      # tools and gate commands, any extra env vars, its command menu, and any
      # always-run setup. `menu` prints only for an interactive shell — otherwise
      # it lands on the stdout that `nix develop --command <tool>` captures and
      # reads as tool output (e.g. golang.yml's gofumpt gate captures
      # `unformatted="$(… gofumpt -l .)"`). `shellHook` always runs.
      mkDevShell =
        {
          pkgs,
          packages ? [ ],
          env ? { },
          menu ? "",
          shellHook ? "",
        }:
        pkgs.mkShell (
          env
          // {
            packages = lintTools pkgs ++ packages;
            shellHook = ''
              if [ -t 1 ]; then
                echo "metio devshell — shared lint gate: reuse, typos, yamllint, actionlint, markdownlint-cli2"
                ${menu}
              fi
            ''
            + shellHook;
          }
        );
    in
    {
      # System-independent building blocks a repo's flake composes.
      lib = {
        inherit
          mkDevShell
          lintTools
          helm-schema
          arch-go
          modernize
          kubebuilderAssets
          ;
      };

      # The from-source packages, buildable for `nix build` and `nix-update`.
      packages = forAllSystems (pkgs: {
        helm-schema = helm-schema pkgs;
        arch-go = arch-go pkgs;
        modernize = modernize pkgs;
      });

      # This repo dogfoods its own shared devShell: conftest runs the policy
      # tests, the rest of the lint gate comes from mkDevShell.
      devShells = forAllSystems (pkgs: {
        default = mkDevShell {
          inherit pkgs;
          packages = [ pkgs.conftest ];
          menu = ''echo "  plus conftest for the convention policies (policy/)."'';
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-rfc-style);
    };
}
