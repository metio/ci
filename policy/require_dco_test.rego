# SPDX-FileCopyrightText: The ci Authors
# SPDX-License-Identifier: 0BSD

package main

import rego.v1

test_flags_pr_workflow_without_dco if {
	bad := {
		"on": {"pull_request": {"branches": ["main"]}},
		"jobs": {"reuse": {"steps": [{"uses": "actions/checkout@sha"}]}},
	}
	msgs := deny with input as bad
	some msg in msgs
	contains(msg, "no DCO gate")
}

test_allows_pr_workflow_with_shared_dco if {
	ok := {
		"on": {"pull_request": {"branches": ["main"]}},
		"jobs": {"dco": {"steps": [{"uses": "metio/ci/dco@0123456789012345678901234567890123456789"}]}},
	}
	msgs := deny with input as ok
	every msg in msgs {
		not contains(msg, "no DCO gate")
	}
}

test_allows_pr_workflow_with_local_dco if {
	ok := {
		"on": {"pull_request": {"branches": ["main"]}},
		"jobs": {"dco": {"steps": [{"uses": "./dco"}]}},
	}
	msgs := deny with input as ok
	every msg in msgs {
		not contains(msg, "no DCO gate")
	}
}

test_exempts_reusable_workflow if {
	reusable := {
		"on": {"workflow_call": {}},
		"jobs": {"test": {"steps": [{"run": "echo hi"}]}},
	}
	msgs := deny with input as reusable
	every msg in msgs {
		not contains(msg, "no DCO gate")
	}
}

test_exempts_non_pr_workflow if {
	release := {
		"on": {"push": {"tags": ["*"]}},
		"jobs": {"release": {"steps": [{"run": "echo release"}]}},
	}
	msgs := deny with input as release
	every msg in msgs {
		not contains(msg, "no DCO gate")
	}
}

test_exempts_composite_action if {
	action := {"runs": {"using": "composite", "steps": [{"run": "echo hi"}]}}
	msgs := deny with input as action
	every msg in msgs {
		not contains(msg, "no DCO gate")
	}
}
