# SPDX-FileCopyrightText: The ci Authors
# SPDX-License-Identifier: 0BSD

# In a repo whose toolchain is a nix flake (policy-check passes
# data.repo.has_flake when flake.nix exists at the repo root), workflow tools
# must come from the flake's devShell — not from setup actions, marketplace
# lint actions, or ad-hoc installers in run: blocks. Any of those pins a tool
# version outside flake.lock, and the "local shell == CI" guarantee silently
# erodes. Shared metio/ci composites (release-notes, policy-check,
# container-release) own their internal tool pins and stay allowed: one pin
# per tool, owned in exactly one place. Without the data flag these rules
# never fire, so repos without a flake are unaffected. The last rule is
# unconditional: a job that enters the devShell needs a step that installs
# nix first, flake flag or not.
package main

import rego.v1

repo_has_flake if data.repo.has_flake == true

# Actions that provision or bundle a tool the devShell should own instead.
# The nix installer itself and the store cache are the bootstrap that makes
# the devShell available, so they are deliberately not listed.
flake_bypassing_actions := {
	"actions/setup-go",
	"actions/setup-node",
	"actions/setup-python",
	"actions/setup-java",
	"azure/setup-helm",
	"sigstore/cosign-installer",
	"crate-ci/typos",
	"DavidAnson/markdownlint-cli2-action",
	"reviewdog/action-actionlint",
	"fsfe/reuse-action",
}

# Only workflows are checked (is_workflow), not composite action definitions: a
# composite action that installs a tool is a shared tool *provider* (e.g. the
# container-release / cosign-sign-blob actions install cosign for consumers), not
# a repo bypassing its own devShell. The rule governs how a repo runs its gates.
deny contains msg if {
	repo_has_flake
	is_workflow
	some entry in action_uses
	uses_path(entry.uses) in flake_bypassing_actions
	msg := sprintf("%s uses %q, which bypasses the flake devShell; add the tool to flake.nix and run it via `nix develop --command`", [entry.where, entry.uses])
}

# Ad-hoc installers in run: blocks — each pins a tool version flake.lock does
# not govern. Workflows only, for the same reason as above.
installer_patterns := {
	`pipx install`,
	`go install [^ ]+@`,
	`go run [^ ]+@`,
	`npm install (-g|--global)`,
	`brew install`,
}

deny contains msg if {
	repo_has_flake
	is_workflow
	some entry in run_steps
	some pattern in installer_patterns
	regex.match(pattern, entry.run)
	msg := sprintf("%s installs a tool outside the flake devShell (matched %q); add it to flake.nix instead", [entry.where, pattern])
}

# A step provides nix when it is the repo's nix-devshell composite (which also
# wires the store cache) or the raw installer.
provides_nix(step) if endswith(uses_path(step.uses), "nix-devshell")

provides_nix(step) if startswith(step.uses, "DeterminateSystems/nix-installer-action@")

# The nix-devshell repo dogfoods its own composite: its root action IS the
# installer, consumed via `uses: ./`. A bare local root reference provides nix.
provides_nix(step) if step.uses == "./"

job_provides_nix(job) if {
	some step in job.steps
	step.uses
	provides_nix(step)
}

deny contains msg if {
	is_workflow
	some job_id, job in input.jobs
	some step in job.steps
	step.run
	regex.match(`(nix develop|nix-shell|nix shell)`, step.run)
	not job_provides_nix(job)
	msg := sprintf("job %q enters the nix devShell but no step installs nix; add the nix-devshell composite (or the nix installer) before it", [job_id])
}
