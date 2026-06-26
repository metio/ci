# SPDX-FileCopyrightText: The ci Authors
# SPDX-License-Identifier: 0BSD

package main

import rego.v1

test_flags_job_without_timeout if {
	bad := {
		"on": {"push": {}},
		"permissions": {"contents": "read"},
		"jobs": {"build": {"steps": [{"run": "echo hi"}]}},
	}
	msgs := deny with input as bad
	some msg in msgs
	contains(msg, "no timeout-minutes")
}

test_allows_job_with_timeout if {
	msgs := deny with input as compliant_workflow
	every msg in msgs {
		not contains(msg, "no timeout-minutes")
	}
}

test_exempts_reusable_workflow_caller if {
	# A job that calls a reusable workflow can't set timeout-minutes, so its
	# absence must not be flagged.
	doc := {
		"on": {"pull_request": {}},
		"permissions": {"contents": "read"},
		"jobs": {"go": {"uses": "metio/ci/.github/workflows/golang.yml@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0"}},
	}
	msgs := deny with input as doc
	every msg in msgs {
		not contains(msg, "no timeout-minutes")
	}
}

test_composite_action_has_no_jobs if {
	msgs := deny with input as compliant_action
	every msg in msgs {
		not contains(msg, "no timeout-minutes")
	}
}
