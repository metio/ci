# SPDX-FileCopyrightText: The ci Authors
# SPDX-License-Identifier: 0BSD

package main

import rego.v1

test_flags_workflow_without_permissions if {
	bad := {
		"on": {"push": {}},
		"jobs": {"build": {"steps": [{"run": "echo hi"}]}},
	}
	msgs := deny with input as bad
	some msg in msgs
	contains(msg, "no top-level permissions")
}

test_allows_workflow_with_permissions if {
	msgs := deny with input as compliant_workflow
	every msg in msgs {
		not contains(msg, "no top-level permissions")
	}
}

test_composite_action_needs_no_permissions if {
	msgs := deny with input as compliant_action
	every msg in msgs {
		not contains(msg, "no top-level permissions")
	}
}
