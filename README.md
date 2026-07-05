<!--
SPDX-FileCopyrightText: The ci Authors
SPDX-License-Identifier: 0BSD
-->
# ci

Shared GitHub Actions CI for the `metio` organization: one reusable workflow per
language or build tool, so every project gets the same gates from one place.

## Reusable workflows

| Workflow | For |
|---|---|
| [`golang.yml`](.github/workflows/golang.yml) | Go projects — build, race tests, vet, staticcheck, gosec, gofumpt, govulncheck, and (auto-detected) arch-go and envtest |

More languages/tools follow the same shape.

### Golang

The Go pipeline is **zero-config**: a `detect` job inspects the repo and the
optional gates skip themselves, so a controller with envtest-backed tests and a
plain library use the identical call.

```yaml
# .github/workflows/verify.yml in a Go project
# SPDX-License-Identifier: 0BSD
name: Verify
on:
  pull_request:
    branches: [main]
permissions:
  contents: read
jobs:
  go:
    name: Golang          # checks then read "Golang / test", "Golang / lint", …
    uses: metio/ci/.github/workflows/golang.yml@<sha>

  # … the project's own non-Go jobs (reuse, yaml, docs, container image, dco) …

  verify:
    name: Verify
    needs: [go]            # plus the project's other jobs
    if: always()
    runs-on: ubuntu-latest
    steps:
      - env:
          NEEDS: ${{ toJSON(needs) }}
        run: |
          bad=$(echo "$NEEDS" | jq -r 'to_entries[] | select(.value.result != "success" and .value.result != "skipped") | "\(.key)=\(.value.result)"')
          [ -z "$bad" ] || { echo "::error::$bad"; exit 1; }
```

What `detect` decides, with no inputs:

- **envtest** — on when any `*_test.go` imports
  `sigs.k8s.io/controller-runtime/pkg/envtest`. The `test` job then runs over the
  newest Kubernetes minors envtest supports (discovered at runtime) with
  `KUBEBUILDER_ASSETS` set; off elsewhere, tests run once.
- **arch-go** — the `architecture` job runs only when an `arch-go.yml` is present;
  otherwise it skips cleanly (no runner spun up).

Inputs (`go-version`, `runs-on`) exist for the rare override; most callers need
none.

## Actions

Composite actions for release pipelines — call them directly from a repo's
release workflow.

### `calver`

The org's single version calculator (see [Versioning](#versioning)). Named for
the scheme so another scheme could be added alongside it later:

```yaml
- id: version
  uses: metio/ci/calver@<sha>
  # with: { prefix: v }       # "v" prefix for the default shape (e.g. Terraform-provider tags)
  # with: { library: true }   # imported Go module → v1.YYYYMMDD.SSSSS
- run: echo "${{ steps.version.outputs.version }}"   # 2026.6.20143022, or v1.20260620.52222 in library mode
```

### `detect-repo-type`

Classifies the repo and emits `library` (true for an imported Go library — a Go
module with no `package main`), which you pass straight to `calver`. So a release
workflow is one shape for every repo:

```yaml
- id: kind
  uses: metio/ci/detect-repo-type@<sha>
- id: version
  uses: metio/ci/calver@<sha>
  with:
    library: ${{ steps.kind.outputs.library }}
```

### `needs-release`

Decides whether a release is warranted — `true` on a first release (no prior
tag) or when commits since the last release touched the given paths, so a
scheduled run no-ops on a quiet period. Needs a full-history checkout:

```yaml
- uses: actions/checkout@<sha>
  with:
    fetch-depth: 0
- id: gate
  uses: metio/ci/needs-release@<sha>
  with:
    paths: go.mod main.go internal api Dockerfile
- if: steps.gate.outputs.needed == 'true'
  run: echo "releasing ${{ steps.gate.outputs.last }} → next"
```

In a monorepo releasing several units with prefixed tags (`myapp-2026.7.1…`),
scope the boundary to one unit's tags with `tag-match` — otherwise another
unit's newer tag hides this unit's pending changes:

```yaml
- id: gate
  uses: metio/ci/needs-release@<sha>
  with:
    paths: units/myapp
    tag-match: myapp-*
```

### `release-notes`

Installs git-cliff and renders release notes for a version using the org-wide
git-cliff config, writing them to a file for `gh release create --notes-file`:

```yaml
- id: notes
  uses: metio/ci/release-notes@<sha>
  with:
    version: ${{ steps.version.outputs.version }}
    previous: ${{ steps.gate.outputs.last }}   # empty on the first release
- run: gh release create "$VERSION" --notes-file "${{ steps.notes.outputs.file }}"
```

The git-cliff version and the config pin live in the action (Renovate bumps
both), so consumers just bump the action ref — no per-repo git-cliff wiring. This
repo's own `release.yml` uses it.

For one unit of a monorepo, scope the notes to the unit's files
(`include-paths`) and its tag lineage (`tag-pattern`) so another unit's
commits and tags never leak into this unit's changelog:

```yaml
- id: notes
  uses: metio/ci/release-notes@<sha>
  with:
    version: myapp-${{ steps.version.outputs.version }}
    previous: ${{ steps.gate.outputs.last }}
    include-paths: units/myapp/**
    tag-pattern: ^myapp-
```

#### Serialize release runs (required)

A release's notes cover the range since the previous tag, and that lower bound is
read (via [`needs-release`](#needs-release)) when the run starts — before the run
creates its own tag. Two merges in quick succession would each read the bound
before either has tagged, so both releases get nearly identical, overlapping
notes. `concurrency` is a per-workflow key, so it can't live in these actions —
**every release workflow that uses `release-notes` must add it itself:**

```yaml
# top level in release.yml, alongside `on:` / `permissions:`
concurrency:
  group: ${{ github.workflow }}
  cancel-in-progress: false
```

Queueing (never cancelling the in-flight run) lets the earlier release finish and
tag first, so the next run reads that tag and its notes start there. Moving the
notes step later does not fix this — if two runs' release jobs interleave, the
later-triggered one can still tag first and overlap; serializing the runs is what
guarantees ordering. Trade-off: with `cancel-in-progress: false`, three merges
inside one run's duration keep only the newest queued run (GitHub cancels the
middle one), so that one calendar version is skipped — no commits are lost from
the changelog, there's just no separate release for it.

### `cosign-sign-blob`

Installs cosign and keyless-signs a file, writing `<file>.bundle` (e.g. the
checksums). Needs `permissions: { id-token: write }`:

```yaml
- uses: metio/ci/cosign-sign-blob@<sha>
  with:
    file: dist/SHA256SUMS
```

### `container-release`

Builds and pushes a multi-arch image (SBOM + provenance + OCI labels) and signs
it with cosign keyless. Needs `permissions: { id-token: write, packages: write, contents: read }`:

```yaml
- id: image
  uses: metio/ci/container-release@<sha>
  with:
    image: ghcr.io/metio/jaas
    version: ${{ steps.version.outputs.version }}
```

## One required check per layer

Each workflow ends in **one** aggregate job — `Verify` for the PR gate (build,
unit + integration tests, lint, security, docs, container scan) and, where a repo
has it, `System Tests` for the real-cluster end-to-end layer. Mark **only** those
aggregates required in branch protection, then turn on auto-merge. Each runs
`if: always()`, `needs` every other job in its workflow, and fails unless each is
`success` or `skipped`. Because each is a single, fixed-name check:

- a skipped optional gate doesn't block merge;
- the envtest matrix's per-version job names can change freely;
- adding or removing jobs never touches branch protection.

That's the zero-maintenance auto-merge gate.

## Convention policies

The workflows and actions in this repo are checked against [conftest](https://www.conftest.dev/)
policies (Rego) in [`policy/`](policy) — the org conventions a YAML linter can't
know. The `policy` job in `verify.yml` runs them on every PR: `conftest verify`
runs the policies' own unit tests, then `conftest test` checks the shipped files.
Run the same locally from the dev shell with `conftest verify --policy policy`.

Each rule is a `deny`, so a violation fails the gate and blocks the merge:

- **SHA-pinned actions** — every `uses:` is a 40-char commit SHA (Renovate keeps
  it current); a mutable tag or branch ref lets the ref's owner change what runs
  after review. Local `./` and `docker://` refs are exempt.
- **No local action refs in reusable workflows** — a `uses: ./name` in a reusable
  workflow resolves against the *caller's* checkout, where the sibling is absent;
  reusable workflows must use the absolute `metio/ci/<name>@<sha>` form.
- **No untrusted run interpolation** — attacker-influenced contexts
  (`github.event.*`, `github.head_ref`, `github.base_ref`) are never expanded
  straight into a `run:` shell; route them through `env:` and reference the
  variable.
- **Workflow permissions** — every workflow declares a top-level `permissions:`
  block instead of inheriting the broad default token scope.
- **Release concurrency** — a release workflow using [`release-notes`](#release-notes)
  declares a top-level `concurrency` block, so two near-simultaneous runs can't
  read the same previous tag and emit overlapping notes.
- **Job timeouts** — every job declares `timeout-minutes`, so a hung step can't
  hold a runner for GitHub's 360-minute default. Jobs that call a reusable
  workflow are exempt (GitHub rejects `timeout-minutes` there).

### Run the policies in another repo

The [`policy-check`](policy-check) composite action carries the policies with it,
so any metio repo gets the same checks with two lines — check out the repo, then
run the action:

```yaml
# in a project's verify.yml
jobs:
  policy:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@<sha>
      - uses: metio/ci/policy-check@<sha>
        # with: { paths: .github/workflows }   # default: workflows + every action.yml
```

It installs conftest, runs the policy unit tests, then checks the repo's
`.github/workflows` and every `action.yml`/`action.yaml`. Add the `policy` job to
the repo's [`Verify`](#one-required-check-per-layer) aggregate so a violation
blocks the merge. The policies live at the action's pinned ref, so bumping the
`policy-check` pin (Renovate does this) updates the rules too.

## Versioning

The [`calver`](#calver) action is the org's single version calculator:
`YYYY.M.D` with the UTC time-of-day appended to the day (e.g. `2026.6.20143022`).
Second precision lifts the one-release-per-day ceiling of a date-only scheme, and
the three leading-zero-free components keep it valid semver, so container images,
Helm charts, and Terraform providers can all consume it.

**Imported Go libraries** can't use that shape: a CalVer major (`2026`) is ≥ 2, so
Go's module rules would force a `/v2026` suffix in the import path that changes
every year. CalVer's **library mode** keeps them under one scheme anyway —
`v1.YYYYMMDD.SSSSS` (e.g. `v1.20260620.52222`): the major is pinned at `1` (a
valid `v1.x.y` module, no path suffix), the padded date sits in the minor so
versions stay ordered, and seconds-since-midnight fills the patch for second
precision with no leading zero. Every release is therefore a *minor* bump within
`v1`, which Renovate offers (and can auto-merge) downstream without it ever being
gated as a major update. The trade-off: pinning the major at `1` gives up
semver's breaking-change signal, so consumers should pin versions rather than
assume `v1.x` is non-breaking.

Consume these workflows and actions pinned to a commit SHA — first-party
`metio/ci/*` refs included, exactly like any third-party action — with Renovate
keeping the pins current. A mutable `@main` ref would let a change run in a
consumer's pipeline before it was reviewed; the SHA pin plus Renovate is the
zero-manual-work path. The examples above abbreviate the ref as `@<sha>` for
brevity.

## License

[0BSD](LICENSES/0BSD.txt), REUSE-compliant.
