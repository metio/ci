<!--
SPDX-FileCopyrightText: The ci Authors
SPDX-License-Identifier: 0BSD
-->
# CLAUDE.md

Guidance for Claude Code (claude.ai/code) when working in this repository.

## Overview

`metio/ci` is the metio organization's shared GitHub Actions CI: **reusable
workflows** (one per language/build tool) and **composite actions** (release
pipeline building blocks), consumed by every other metio repo so the gates and
the versioning live in one place. There is no application code here.

## Layout

- `.github/workflows/golang.yml` — reusable Go pipeline (`workflow_call`).
- `calver/action.yml` — compute the next calendar version.
- `needs-release/action.yml` — decide whether a release is warranted.
- `detect-repo-type/action.yml` — classify a repo to drive the above.
- `release-notes/`, `container-release/`, `cosign-sign-blob/` — release-pipeline
  composite actions (git-cliff notes, multi-arch image + cosign, blob signing).
- `policy/` — conftest/Rego convention policies (`*.rego`) plus their unit tests
  (`*_test.rego`); see `## policy`.
- `policy-check/action.yml` — composite action that runs `policy/` over a
  caller's repo, so other org repos get the same checks.

Add more languages as sibling reusable workflows (`rust.yml`, `hugo.yml`, …) and
more pipeline steps as sibling composite actions, following the same shape.

## golang.yml

Zero-config: a `detect` job inspects the **caller's** checked-out repo and the
optional gates skip themselves via job-level `if`, so a controller with
envtest-backed tests and a plain library use the identical call (no `with:`).

- **envtest** is on when any `*_test.go` imports
  `sigs.k8s.io/controller-runtime/pkg/envtest`; the `test` job then runs a matrix
  over the newest Kubernetes minors `setup-envtest list` reports, discovered at
  runtime. Off → tests run once (matrix sentinel `["none"]`).
- **arch-go** runs only when `arch-go.yml` exists; the `architecture` job is
  `if`-gated on the detected flag, so it skips cleanly (no runner) otherwise.
- `lint-go` (vet, staticcheck, gosec, gofumpt) and `vulnerabilities`
  (govulncheck) always run — universal for any Go module.

**The `Verify` aggregate lives in the *caller*, not here.** A reusable
workflow only knows its own jobs; the single required check must `needs` the
caller's other jobs (reuse, docs, container image, …) too, so it can't be
centralized. Each repo's `verify.yml` ends in an `if: always()` aggregate named
`Verify` that fails unless every `needs` result is `success` or
`skipped`; that one job is the only required check (see README).

## Versioning (calver / detect-repo-type)

`calver` is the org's single version calculator, with two shapes — both valid,
monotonically increasing semver, computed from **one UTC timestamp** (so a
release near midnight can't take the date from one day and the time from the
next):

- **default** (apps, charts, Terraform providers, this repo): `YYYY.M.D` with the
  UTC time-of-day appended to the day, e.g. `2026.6.20143022`. Unpadded month/day
  (`%-m`/`%-d`) keep each component leading-zero-free.
- **library mode** (`library: true`, for imported Go modules): `v1.YYYYMMDD.SSSSS`,
  e.g. `v1.20260620.52222`.

**Why library mode exists and why it's built exactly this way** — an imported Go
module's major version is encoded in its import path for major ≥ 2 (`/vN`). A
CalVer major (`2026`) would force a `/v2026` suffix that changes yearly and breaks
every importer. So library mode pins the major at `1` (valid `v1.x.y`, no suffix):

- minor = **padded** `YYYYMMDD` (`date +%Y%m%d`). Padding is load-bearing:
  unpadded month/day make `202429` (Feb 9) sort below `2024116` (Jan 16) — a real
  ordering bug that earlier migadu-client.go tags hit before they padded.
- patch = **seconds-since-midnight** (`epoch % 86400`, 0–86399). `HHMMSS` would be
  a leading zero before 10:00 (`000005`) and thus invalid semver; seconds-since-
  midnight never is, and is monotonic within the day.

Every library release is therefore a *minor* bump within `v1`, which Renovate
offers (and can auto-merge) downstream and never gates as a major update.
Trade-off: pinning the major gives up semver's breaking-change signal, so library
consumers pin versions rather than trust `v1.x` to be non-breaking.

`detect-repo-type` picks the shape: a Go module (`go.mod`) with no `package main`
(excluding `vendor/`, `testdata/`) is an imported library → `library=true`;
anything else uses the default shape. An `override` input covers the rare library
that also ships a binary. Feed its `library` output straight into `calver`.

`needs-release` gates a scheduled release: `git describe --tags` finds the last
release, and it returns `needed=true` on a first release (no tag) or when commits
since the last tag touched the given `paths`. Callers must checkout with
`fetch-depth: 0` so tags and history are present.

## policy

`policy/` holds conftest/Rego policies encoding the org conventions a YAML linter
can't know — SHA-pinned `uses:`, no local action refs in reusable workflows, no
untrusted context interpolated into `run:`, a top-level `permissions:` block,
release `concurrency`, and per-job `timeout-minutes`. Each rule is a `deny`
(fail-the-gate) with a `*_test.rego` beside it; `conftest verify` runs those unit
tests and `conftest test` checks the files. Every input is one parsed YAML file,
so `lib.rego` classifies it (workflow vs composite action; the `on:` key folds to
the boolean `true` under the conftest YAML loader) and exposes its `uses:`/`run:`
steps. New rules go in their own `<name>.rego` + `<name>_test.rego`; keep the
shared fixtures in `fixtures_test.rego` convention-clean so the "good case" tests
stay meaningful.

The policies are consumed two ways: the `policy` job in `verify.yml` dogfoods the
`policy-check` action over this repo, and other org repos call
`metio/ci/policy-check@<sha>` to check themselves. `policy-check` finds the
policies beside itself via `$GITHUB_ACTION_PATH/../policy`, so they always match
the pinned ref — no second checkout, no ref drift.

## Conventions & traps

- **Pin every consumed action to a commit SHA** — first-party `metio/ci/*` refs
  included, like any third-party action — and let Renovate keep the pins current
  (zero manual work). Never track a mutable `@main`/tag ref. Same-repo `./` refs
  are the only exception: they're our own code in the same checkout, with nothing
  for Renovate to pin.
- **Never reference a sibling action as `./name` inside a reusable workflow** — a
  local path resolves against the *caller's* checkout, not this repo. Use the
  absolute `metio/ci/<name>@<ref>` form, and keep that ref aligned with how the
  workflow itself is consumed.
- **REUSE / 0BSD.** Every file carries an inline SPDX header (`#` for YAML, `<!-- -->`
  for Markdown); `REUSE.toml` + `LICENSES/0BSD.txt` cover the rest. New files need
  a declaration or CI's REUSE check fails.
- **Shell in actions**: pass workflow inputs through `env:` and reference them as
  shell variables (not `${{ }}` interpolated into the script) to avoid injection
  and keep actionlint/shellcheck clean; word-split deliberately with an explicit
  `# shellcheck disable=SC2086`.
- Validate workflow/action YAML with `actionlint` (it shells out to `shellcheck`
  for `run:` blocks). The repo has no language toolchain of its own; run linters
  from a metio Go repo's dev shell against the file until this repo has its own CI.
