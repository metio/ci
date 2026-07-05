# SPDX-FileCopyrightText: The ci Authors
# SPDX-License-Identifier: 0BSD

package main

import rego.v1

flake_repo := {"has_flake": true}

no_flake_repo := {"has_flake": false}

nix_workflow := {
	"on": {"pull_request": {"branches": ["main"]}},
	"permissions": {"contents": "read"},
	"jobs": {"fmt": {
		"timeout-minutes": 10,
		"steps": [
			{"uses": "actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0"},
			{"uses": "./.github/actions/nix-devshell"},
			{"run": "nix develop --command jsonnetfmt --test ./*.libsonnet"},
		],
	}},
}

test_flags_setup_action_in_flake_repo if {
	bad := {
		"on": {"push": {}},
		"jobs": {"build": {"steps": [{"uses": "actions/setup-go@924ae3a1cded613372ab5595356fb5720e22ba16"}]}},
	}
	msgs := deny with input as bad with data.repo as flake_repo
	some msg in msgs
	contains(msg, "bypasses the flake devShell")
}

test_flags_lint_marketplace_action_in_flake_repo if {
	bad := {
		"on": {"push": {}},
		"jobs": {"typos": {"steps": [{"uses": "crate-ci/typos@37bb98842b0d8c4ffebdb75301a13db0267cef89"}]}},
	}
	msgs := deny with input as bad with data.repo as flake_repo
	some msg in msgs
	contains(msg, "bypasses the flake devShell")
}

test_allows_setup_action_without_flake if {
	doc := {
		"on": {"push": {}},
		"jobs": {"build": {"steps": [{"uses": "actions/setup-go@924ae3a1cded613372ab5595356fb5720e22ba16"}]}},
	}
	msgs := deny with input as doc with data.repo as no_flake_repo
	every msg in msgs {
		not contains(msg, "bypasses the flake devShell")
	}
}

test_flags_ad_hoc_installer_in_flake_repo if {
	bad := {
		"on": {"push": {}},
		"jobs": {"lint": {"steps": [{"run": "go run github.com/google/go-jsonnet/cmd/jsonnetfmt@latest --test ."}]}},
	}
	msgs := deny with input as bad with data.repo as flake_repo
	some msg in msgs
	contains(msg, "outside the flake devShell")
}

test_allows_devshell_tools_in_flake_repo if {
	msgs := deny with input as nix_workflow with data.repo as flake_repo
	count(msgs) == 0
}

# The nix installer and the devShell composite are the bootstrap — never
# flagged, in any repo.
test_allows_nix_bootstrap_in_flake_repo if {
	doc := {
		"on": {"push": {}},
		"permissions": {"contents": "read"},
		"jobs": {"fmt": {
			"timeout-minutes": 10,
			"steps": [
				{"uses": "DeterminateSystems/nix-installer-action@ef8a148080ab6020fd15196c2084a2eea5ff2d25"},
				{"uses": "nix-community/cache-nix-action@7df957e333c1e5da7721f60227dbba6d06080569"},
				{"run": "nix develop --command typos"},
			],
		}},
	}
	msgs := deny with input as doc with data.repo as flake_repo
	count(msgs) == 0
}

test_flags_nix_develop_without_installer if {
	bad := {
		"on": {"push": {}},
		"jobs": {"fmt": {"steps": [
			{"uses": "actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0"},
			{"run": "nix develop --command typos"},
		]}},
	}
	msgs := deny with input as bad
	some msg in msgs
	contains(msg, "no step installs nix")
}

test_allows_nix_develop_with_devshell_composite if {
	msgs := deny with input as nix_workflow
	every msg in msgs {
		not contains(msg, "no step installs nix")
	}
}
