# SPDX-FileCopyrightText: The ci Authors
# SPDX-License-Identifier: 0BSD

# Every job declares timeout-minutes. A job with no timeout inherits GitHub's
# 360-minute default, so a hung step (a wedged network call, an interactive
# prompt) keeps a runner busy for six hours before it is killed. A job that calls
# a reusable workflow (`uses:` at job level) is exempt — GitHub rejects
# timeout-minutes there; the timeout belongs on the called workflow's own jobs.
package main

import rego.v1

deny contains msg if {
	is_workflow
	some job_id, job in input.jobs
	not job.uses
	not job["timeout-minutes"]
	msg := sprintf("job %q has no timeout-minutes; it would inherit GitHub's 360-minute default", [job_id])
}
