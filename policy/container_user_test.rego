# SPDX-FileCopyrightText: The ci Authors
# SPDX-License-Identifier: 0BSD

package main

import rego.v1

# conftest's dockerfile parser hands each instruction over as one entry, with
# Stage counting the FROM blocks from zero.
instruction(cmd, stage, value) := {
	"Cmd": cmd,
	"Flags": [],
	"JSON": false,
	"Stage": stage,
	"SubCmd": "",
	"Value": value,
}

test_flags_a_final_stage_without_a_user if {
	bad := [
		instruction("from", 0, ["docker.io/library/eclipse-temurin:25-jdk", "AS", "build"]),
		instruction("from", 1, ["docker.io/library/eclipse-temurin:25-jre"]),
		instruction("entrypoint", 1, ["java"]),
	]
	msgs := deny with input as bad
	some msg in msgs
	contains(msg, "declares no USER")
}

test_allows_a_non_root_user if {
	ok := [
		instruction("from", 0, ["docker.io/library/eclipse-temurin:25-jre"]),
		instruction("user", 0, ["65532:65532"]),
	]
	msgs := deny with input as ok
	every msg in msgs {
		not contains(msg, "USER")
	}
}

test_flags_an_explicit_root_user if {
	bad := [
		instruction("from", 0, ["docker.io/library/alpine"]),
		instruction("user", 0, ["root"]),
	]
	msgs := deny with input as bad
	some msg in msgs
	contains(msg, "runs as")
}

test_flags_uid_zero if {
	bad := [
		instruction("from", 0, ["docker.io/library/alpine"]),
		instruction("user", 0, ["0:0"]),
	]
	msgs := deny with input as bad
	some msg in msgs
	contains(msg, "runs as")
}

# A build stage running as root is ordinary — it installs things. Only the stage
# that ships is checked, and a USER in an earlier one does not satisfy it.
test_a_user_in_an_earlier_stage_does_not_count if {
	bad := [
		instruction("from", 0, ["docker.io/library/eclipse-temurin:25-jdk", "AS", "build"]),
		instruction("user", 0, ["65532"]),
		instruction("from", 1, ["docker.io/library/eclipse-temurin:25-jre"]),
	]
	msgs := deny with input as bad
	some msg in msgs
	contains(msg, "declares no USER")
}

test_ignores_a_workflow if {
	workflow := {"jobs": {"build": {"steps": [{"uses": "actions/checkout@sha"}]}}}
	msgs := deny with input as workflow
	every msg in msgs {
		not contains(msg, "USER")
	}
}
