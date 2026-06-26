# SPDX-FileCopyrightText: The ci Authors
# SPDX-License-Identifier: 0BSD

# Every workflow declares a top-level permissions: block. Without one the job
# inherits the repository default token scope, which is broader than any single
# workflow needs; an explicit least-privilege block is the baseline hardening.
# Composite actions have no permissions of their own, so the rule targets
# workflows only.
package main

import rego.v1

deny contains msg if {
	is_workflow
	not input.permissions
	msg := "workflow has no top-level permissions: block; declare least-privilege permissions explicitly"
}
