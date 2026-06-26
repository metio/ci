# SPDX-FileCopyrightText: The ci Authors
# SPDX-License-Identifier: 0BSD

# Third-party actions must be pinned to a full commit SHA. A tag or branch ref is
# mutable, so `uses: actions/checkout@v7` lets the upstream owner change what runs
# in our pipeline after it was reviewed. Local (`./…`), docker (`docker://…`), and
# same-org (`metio/…`) refs are exempt: local code is ours, docker images carry
# their own digest, and the org pins its first-party actions to CalVer refs by
# policy (README "Versioning").
package main

import rego.v1

deny contains msg if {
	some entry in action_uses
	not is_local_ref(entry.uses)
	not startswith(entry.uses, "docker://")
	not startswith(entry.uses, "metio/")
	not is_sha_pinned(entry.uses)
	msg := sprintf("%s: %q is not pinned to a 40-char commit SHA (a tag or branch ref is mutable)", [entry.where, entry.uses])
}

is_sha_pinned(u) if {
	parts := split(u, "@")
	count(parts) == 2
	regex.match(`^[0-9a-f]{40}$`, parts[1])
}
