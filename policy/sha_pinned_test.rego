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

test_exempts_same_org_ref if {
	doc := {
		"on": {"workflow_call": {}},
		"permissions": {"contents": "read"},
		"jobs": {"build": {"steps": [{"uses": "metio/ci/calver@main"}]}},
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
