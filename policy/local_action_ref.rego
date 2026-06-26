# SPDX-FileCopyrightText: The ci Authors
# SPDX-License-Identifier: 0BSD

# A reusable workflow runs inside the *caller's* checkout, so `uses: ./name`
# resolves against the caller's repo rather than this one — the sibling action is
# absent there and the run fails. Reusable workflows must reference siblings by
# the absolute metio/ci/<name>@<ref> form (CLAUDE.md "Conventions & traps"). A
# normal workflow running in this repo may use ./name, so the rule is scoped to
# reusable workflows.
package main

import rego.v1

deny contains msg if {
	is_reusable_workflow
	some entry in action_uses
	is_local_ref(entry.uses)
	msg := sprintf("%s: local action ref %q in a reusable workflow resolves against the caller's checkout, not this repo; use metio/ci/<name>@<ref>", [entry.where, entry.uses])
}
