# SPDX-FileCopyrightText: The ci Authors
# SPDX-License-Identifier: 0BSD

# Contexts an attacker can influence on the events we run on. GitHub's hardening
# guidance is to never expand them straight into a shell, where their contents
# become code; route them through env: and reference the shell variable instead.
# matrix/steps/inputs/needs contexts are not attacker-controlled and are fine.
package main

import rego.v1

untrusted_run_contexts := [
	"github.event.",
	"github.head_ref",
	"github.base_ref",
]

deny contains msg if {
	some entry in run_steps
	some ctx in untrusted_run_contexts

	# Match the context only inside a `${{ … }}` expansion — that is what gets
	# substituted into the script; the same string in env: is referenced as a
	# shell variable and is safe. Dots in the context are escaped to stay literal.
	pattern := concat("", [`\$\{\{[^}]*`, replace(ctx, ".", `\.`)])
	regex.match(pattern, entry.run)

	msg := sprintf("%s: run: expands untrusted ${{ %s… }} directly into the shell; pass it via env: and reference the variable", [entry.where, ctx])
}
