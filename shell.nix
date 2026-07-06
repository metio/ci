# SPDX-FileCopyrightText: The ci Authors
# SPDX-License-Identifier: 0BSD

# nix-shell compatibility: exposes the flake's devShell to plain `nix-shell`.
(import (
  let
    lock = builtins.fromJSON (builtins.readFile ./flake.lock);
    node = lock.nodes.flake-compat.locked;
  in
  fetchTarball {
    url = "https://github.com/edolstra/flake-compat/archive/${node.rev}.tar.gz";
    sha256 = node.narHash;
  }
) { src = ./.; }).shellNix
