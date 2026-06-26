# SPDX-FileCopyrightText: The ci Authors
# SPDX-License-Identifier: 0BSD

package main

import rego.v1

test_flags_event_context_in_run if {
	bad := {
		"on": {"issues": {}},
		"permissions": {"contents": "read"},
		"jobs": {"build": {"steps": [{"run": "echo ${{ github.event.issue.title }}"}]}},
	}
	msgs := deny with input as bad
	some msg in msgs
	contains(msg, "github.event.")
}

test_flags_head_ref_in_run if {
	bad := {
		"on": {"pull_request_target": {}},
		"permissions": {"contents": "read"},
		"jobs": {"build": {"steps": [{"run": "git checkout ${{ github.head_ref }}"}]}},
	}
	msgs := deny with input as bad
	some msg in msgs
	contains(msg, "github.head_ref")
}

test_allows_trusted_contexts_in_run if {
	doc := {
		"on": {"workflow_call": {}},
		"permissions": {"contents": "read"},
		"jobs": {"build": {"steps": [{"run": "echo ${{ matrix.k8s }} ${{ steps.x.outputs.y }}"}]}},
	}
	msgs := deny with input as doc
	every msg in msgs {
		not contains(msg, "directly into the shell")
	}
}

test_allows_untrusted_context_routed_through_env if {
	# The event value reaches the step via env:, referenced as a shell variable —
	# the safe pattern. Only run: text is inspected, so the env mapping is fine.
	doc := {
		"on": {"issues": {}},
		"permissions": {"contents": "read"},
		"jobs": {"build": {"steps": [{
			"env": {"TITLE": "${{ github.event.issue.title }}"},
			"run": "echo \"$TITLE\"",
		}]}},
	}
	msgs := deny with input as doc
	every msg in msgs {
		not contains(msg, "directly into the shell")
	}
}
