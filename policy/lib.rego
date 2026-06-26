# SPDX-FileCopyrightText: The ci Authors
# SPDX-License-Identifier: 0BSD

# Shared helpers for the metio CI convention policies. conftest hands each rule a
# single parsed YAML file as `input` — a workflow under .github/workflows or a
# composite action.yml — so these helpers classify the document and then expose
# its uses:/run: steps in one shape regardless of which kind it is.
package main

import rego.v1

# GitHub's `on:` trigger key. The conftest YAML loader resolves the bareword `on`
# to the boolean true (YAML 1.1 bool rules), so a workflow's triggers live under
# input[true]; the string-key branch covers a strict YAML 1.2 loader too. Only
# one branch is ever defined for a given file, so the complete rule has one value.
workflow_triggers := t if t := input[true]

workflow_triggers := t if t := input.on

is_workflow if input.jobs

is_reusable_workflow if workflow_triggers.workflow_call

is_local_ref(u) if startswith(u, "./")

is_local_ref(u) if startswith(u, "../")

# Path portion of a `uses:` value, i.e. everything before the @ref (or the whole
# value when there is no ref, as with a local sibling reference).
uses_path(u) := parts[0] if parts := split(u, "@")

# Every `uses:` in the document, paired with a human-readable location, gathered
# from workflow jobs (step- and job-level) and composite action steps alike.
action_uses contains entry if {
	some job_id, job in input.jobs
	some i, step in job.steps
	step.uses
	entry := {"uses": step.uses, "where": sprintf("job %q step %d", [job_id, i])}
}

action_uses contains entry if {
	some job_id, job in input.jobs
	job.uses
	entry := {"uses": job.uses, "where": sprintf("job %q", [job_id])}
}

action_uses contains entry if {
	some i, step in input.runs.steps
	step.uses
	entry := {"uses": step.uses, "where": sprintf("runs step %d", [i])}
}

# Every `run:` block, with its location, across both file kinds.
run_steps contains entry if {
	some job_id, job in input.jobs
	some i, step in job.steps
	step.run
	entry := {"run": step.run, "where": sprintf("job %q step %d", [job_id, i])}
}

run_steps contains entry if {
	some i, step in input.runs.steps
	step.run
	entry := {"run": step.run, "where": sprintf("runs step %d", [i])}
}
