# SPDX-FileCopyrightText: The ci Authors
# SPDX-License-Identifier: 0BSD

# Every pull-request gate runs the DCO check: a job using the shared metio/ci/dco
# action (or the local ./dco while a repo dogfoods it). The Signed-off-by trailer
# is org policy; leaving the check off a repo's PR gate would let unsigned commits
# merge. Because every repo already runs policy-check, this rule turns "no DCO" on
# a PR gate into a failed gate across the org. The gate is the pull_request
# workflow holding the `Verify` aggregate job; other pull_request workflows, such
# as a standalone REUSE or leaks check, sit beside it. Reusable workflows
# (workflow_call - they carry no PR gate of their own), non-PR workflows (release,
# schedule), and composite actions are exempt.
package main

import rego.v1

has_dco_job if {
	some entry in action_uses
	uses_path(entry.uses) in {"metio/ci/dco", "./dco"}
}

deny contains msg if {
	is_workflow
	workflow_triggers.pull_request
	not is_reusable_workflow
	is_pr_gate
	not has_dco_job
	msg := "pull_request workflow has no DCO gate; add a job using metio/ci/dco (sign commits with git commit --signoff; see the ci README)"
}

is_pr_gate if {
	some _, job in input.jobs
	job.name == "Verify"
}
