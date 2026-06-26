# SPDX-FileCopyrightText: The ci Authors
# SPDX-License-Identifier: 0BSD

package main

import rego.v1

test_flags_local_ref_in_reusable_workflow if {
	bad := {
		"on": {"workflow_call": {}},
		"permissions": {"contents": "read"},
		"jobs": {"build": {"steps": [{"uses": "./calver"}]}},
	}
	msgs := deny with input as bad
	some msg in msgs
	contains(msg, "resolves against the caller's checkout")
}

test_allows_local_ref_in_normal_workflow if {
	doc := {
		"on": {"push": {"branches": ["main"]}},
		"permissions": {"contents": "write"},
		"jobs": {"release": {"steps": [{"uses": "./calver"}]}},
	}
	msgs := deny with input as doc
	every msg in msgs {
		not contains(msg, "resolves against the caller's checkout")
	}
}

test_allows_absolute_ref_in_reusable_workflow if {
	doc := {
		"on": {"workflow_call": {}},
		"permissions": {"contents": "read"},
		"jobs": {"build": {"steps": [{"uses": "metio/ci/calver@main"}]}},
	}
	msgs := deny with input as doc
	every msg in msgs {
		not contains(msg, "resolves against the caller's checkout")
	}
}
