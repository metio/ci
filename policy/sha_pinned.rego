# SPDX-FileCopyrightText: The ci Authors
# SPDX-License-Identifier: 0BSD

# Every action must be pinned to a full commit SHA — first-party metio/ci/*
# actions included. A tag or branch ref is mutable, so `uses: actions/checkout@v7`
# lets the ref's owner change what runs in our pipeline after it was reviewed;
# Renovate keeps the pins current so the pin costs no manual work. Only local
# (`./…`) refs — our own code in the same checkout, with nothing for Renovate to
# pin — and docker (`docker://…`) images, which carry their own digest, are exempt.
package main

import rego.v1

deny contains msg if {
	some entry in action_uses
	not is_local_ref(entry.uses)
	not startswith(entry.uses, "docker://")
	not is_sha_pinned(entry.uses)
	msg := sprintf("%s: %q is not pinned to a 40-char commit SHA (a tag or branch ref is mutable)", [entry.where, entry.uses])
}

is_sha_pinned(u) if {
	parts := split(u, "@")
	count(parts) == 2
	regex.match(`^[0-9a-f]{40}$`, parts[1])
}
