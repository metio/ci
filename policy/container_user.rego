# SPDX-FileCopyrightText: The ci Authors
# SPDX-License-Identifier: 0BSD

# A container image must not run its process as root. Only the FINAL stage is
# checked: build stages install toolchains and legitimately run as root, and what
# ships is the last one.
#
# The rule exists because the failure is silent and arrives sideways. A base image
# carries a default user, so a Containerfile that never says USER inherits
# whatever the base decided — and changing base changes the answer. A portal that
# moved from a distroless `:nonroot` image to a Temurin one gained root without a
# line of its Containerfile changing, and nothing in the build or the tests could
# have noticed.
package main

import rego.v1

is_containerfile if {
	some entry in input
	entry.Cmd == "from"
}

# The stage that ships. Multi-stage builds number from zero, so the highest is
# the one whose filesystem becomes the image.
final_stage := max({entry.Stage | some entry in input; entry.Cmd == "from"})

final_stage_users contains value if {
	some entry in input
	entry.Cmd == "user"
	entry.Stage == final_stage
	value := lower(entry.Value[0])
}

# `root`, `0`, and either of those as the user half of `user:group`.
is_root_user(value) if value in {"root", "0"}

is_root_user(value) if startswith(value, "root:")

is_root_user(value) if startswith(value, "0:")

deny contains msg if {
	is_containerfile
	count(final_stage_users) == 0
	msg := "the final build stage declares no USER, so the image runs as whatever its base image defaults to — add a USER with a non-root uid"
}

deny contains msg if {
	is_containerfile
	some value in final_stage_users
	is_root_user(value)
	msg := sprintf("the final build stage runs as %q; run as a non-root uid instead", [value])
}
