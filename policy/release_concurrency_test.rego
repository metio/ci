# SPDX-FileCopyrightText: The ci Authors
# SPDX-License-Identifier: 0BSD

package main

import rego.v1

test_flags_release_notes_without_concurrency if {
	bad := {
		"on": {"push": {"branches": ["main"]}},
		"permissions": {"contents": "write"},
		"jobs": {"release": {"steps": [{"uses": "./release-notes"}]}},
	}
	msgs := deny with input as bad
	some msg in msgs
	contains(msg, "no top-level concurrency block")
}

test_allows_release_notes_with_concurrency if {
	doc := {
		"on": {"push": {"branches": ["main"]}},
		"permissions": {"contents": "write"},
		"concurrency": {"group": "release", "cancel-in-progress": false},
		"jobs": {"release": {"steps": [{"uses": "metio/ci/release-notes@main"}]}},
	}
	msgs := deny with input as doc
	every msg in msgs {
		not contains(msg, "no top-level concurrency block")
	}
}

test_no_concurrency_required_without_release_notes if {
	msgs := deny with input as compliant_workflow
	every msg in msgs {
		not contains(msg, "no top-level concurrency block")
	}
}
