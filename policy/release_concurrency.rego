# SPDX-FileCopyrightText: The ci Authors
# SPDX-License-Identifier: 0BSD

# A release workflow that renders notes with the release-notes action must
# serialize its runs with a top-level concurrency block. The notes cover the
# range since the previous tag, and that lower bound is read before the run
# creates its own tag; two near-simultaneous runs would each read the same bound
# and emit overlapping notes. concurrency is a per-workflow key, so the action
# can't provide it — every consumer must (README "Serialize release runs").
# A workflow only ever called by another runs inside its caller's run, so the
# caller's concurrency group covers it; repeating that group in the called
# workflow would queue it behind the very run that waits for it.
package main

import rego.v1

deny contains msg if {
	is_workflow
	uses_release_notes
	not called_only
	not input.concurrency.group
	msg := "release workflow uses release-notes but has no top-level concurrency block; near-simultaneous runs would read the same previous tag and emit overlapping notes (README: 'Serialize release runs (required)')"
}

uses_release_notes if {
	some entry in action_uses
	endswith(uses_path(entry.uses), "release-notes")
}

called_only if {
	is_reusable_workflow
	count(workflow_triggers) == 1
}
