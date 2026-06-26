# SPDX-FileCopyrightText: The ci Authors
# SPDX-License-Identifier: 0BSD

package main

import rego.v1

test_allows_sha_pinned_action if {
	count(deny) == 0 with input as compliant_workflow
}

test_flags_tag_ref if {
	bad := {
		"on": {"push": {}},
		"permissions": {"contents": "read"},
		"jobs": {"build": {"steps": [{"uses": "actions/checkout@v7"}]}},
	}
	msgs := deny with input as bad
	some msg in msgs
	contains(msg, "not pinned to a 40-char commit SHA")
}

test_flags_ref_without_version if {
	bad := {
		"on": {"push": {}},
		"permissions": {"contents": "read"},
		"jobs": {"build": {"steps": [{"uses": "actions/checkout"}]}},
	}
	msgs := deny with input as bad
	some msg in msgs
	contains(msg, "not pinned to a 40-char commit SHA")
}

test_exempts_local_ref if {
	doc := {
		"on": {"push": {}},
		"permissions": {"contents": "read"},
		"jobs": {"build": {"steps": [{"uses": "./needs-release"}]}},
	}
	msgs := deny with input as doc
	every msg in msgs {
		not contains(msg, "not pinned to a 40-char commit SHA")
	}
}

test_flags_first_party_tag_ref if {
	# metio/ci/* actions are pinned to a SHA like any other; @main is not allowed.
	bad := {
		"on": {"workflow_call": {}},
		"permissions": {"contents": "read"},
		"jobs": {"build": {"steps": [{"uses": "metio/ci/calver@main"}]}},
	}
	msgs := deny with input as bad
	some msg in msgs
	contains(msg, "not pinned to a 40-char commit SHA")
}

test_allows_first_party_sha_ref if {
	doc := {
		"on": {"workflow_call": {}},
		"permissions": {"contents": "read"},
		"jobs": {"build": {"steps": [{"uses": "metio/ci/calver@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0"}]}},
	}
	msgs := deny with input as doc
	every msg in msgs {
		not contains(msg, "not pinned to a 40-char commit SHA")
	}
}

test_checks_composite_action_steps if {
	bad := {"runs": {"using": "composite", "steps": [{"uses": "sigstore/cosign-installer@v4"}]}}
	msgs := deny with input as bad
	some msg in msgs
	contains(msg, "not pinned to a 40-char commit SHA")
}
