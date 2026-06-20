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
    uses: metio/ci/.github/workflows/golang.yml@main

  # … the project's own non-Go jobs (reuse, yaml, docs, container image, dco) …

  all-tests-pass:
    name: All Tests Pass
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
  uses: metio/ci/calver@main
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
  uses: metio/ci/detect-repo-type@main
- id: version
  uses: metio/ci/calver@main
  with:
    library: ${{ steps.kind.outputs.library }}
```

### `needs-release`

Decides whether a release is warranted — `true` on a first release (no prior
tag) or when commits since the last release touched the given paths, so a
scheduled run no-ops on a quiet period. Needs a full-history checkout:

```yaml
- uses: actions/checkout@v5
  with:
    fetch-depth: 0
- id: gate
  uses: metio/ci/needs-release@main
  with:
    paths: go.mod main.go internal api Dockerfile
- if: steps.gate.outputs.needed == 'true'
  run: echo "releasing ${{ steps.gate.outputs.last }} → next"
```

### `release-notes`

Installs git-cliff and renders release notes for a version using the org-wide
git-cliff config, writing them to a file for `gh release create --notes-file`:

```yaml
- id: notes
  uses: metio/ci/release-notes@main
  with:
    version: ${{ steps.version.outputs.version }}
    previous: ${{ steps.gate.outputs.last }}   # empty on the first release
- run: gh release create "$VERSION" --notes-file "${{ steps.notes.outputs.file }}"
```

The git-cliff version and the config pin live in the action (Renovate bumps
both), so consumers just bump the action ref — no per-repo git-cliff wiring. This
repo's own `release.yml` uses it.

## One required check: `All Tests Pass`

Mark **only** the `all-tests-pass` job required in branch protection, then turn on
auto-merge. It runs `if: always()`, `needs` every other job, and fails unless each
is `success` or `skipped`. Because it's the single, fixed-name check:

- a skipped optional gate doesn't block merge;
- the envtest matrix's per-version job names can change freely;
- adding or removing jobs never touches branch protection.

That's the zero-maintenance auto-merge gate.

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

Until the ci repo cuts its own releases, consume its workflows and actions at
`@main`; pin to a tag (or SHA) once releases land, with Renovate keeping the pin
current.

## License

[0BSD](LICENSES/0BSD.txt), REUSE-compliant.
