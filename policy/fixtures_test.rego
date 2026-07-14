# SPDX-FileCopyrightText: The ci Authors
# SPDX-License-Identifier: 0BSD

# Fully convention-compliant documents shared across the policy unit tests: each
# rule's "allows the good case" test asserts no deny fires against these, so a
# fixture doubles as a cross-rule cleanliness check. SHAs are real refs from this
# repo so the pin check treats them as valid.
package main

import rego.v1

compliant_workflow := {
	"on": {"pull_request": {"branches": ["main"]}},
	"permissions": {"contents": "read"},
	"jobs": {
		"build": {
			"timeout-minutes": 10,
			"steps": [
				{"uses": "actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0"},
				{"run": "go build ./..."},
			],
		},
		# A PR gate carries the DCO check (require-dco), so the shared "fully
		# compliant" fixture does too.
		"dco": {
			"timeout-minutes": 10,
			"steps": [
				{"uses": "actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0"},
				{"uses": "metio/ci/dco@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0"},
			],
		},
	},
}

compliant_action := {"runs": {"using": "composite", "steps": [
	{"uses": "sigstore/cosign-installer@6f9f17788090df1f26f669e9d70d6ae9567deba6"},
	{"run": "echo hello"},
]}}
