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
| [`baseline.yml`](.github/workflows/baseline.yml) | Every repository — secret scanning with [`leaks`](#leaks), the [DCO](#developer-certificate-of-origin) gate, REUSE compliance and the [convention policies](#convention-policies) |
| [`golang.yml`](.github/workflows/golang.yml) | Go projects — build, race tests, vet, staticcheck, gosec, gofumpt, govulncheck, and (auto-detected) arch-go and envtest |
| [`frontend.yml`](.github/workflows/frontend.yml) | Vite/React (Node) projects — build, browser + coverage, lint, knip, a11y (light + dark), lighthouse, and the shared lint gate; each gate auto-detected from `package.json` scripts |
| [`clojure.yml`](.github/workflows/clojure.yml) | Clojure projects — test, clj-kondo, eastwood + splint, cljfmt, and clj-watson vulnerabilities, all through `deps.edn` aliases |
| [`maven.yml`](.github/workflows/maven.yml) | Maven (JVM) projects — the POM-driven build plus a javadoc gate, with the local repository cached |
| [`maven-central-release.yml`](.github/workflows/maven-central-release.yml) | Maven Central releases — the change and quota gates, the signed deploy, and the GitHub release |

More languages/tools follow the same shape.

### Baseline

The checks every repository runs, whatever its language. Each repository calls
the workflow from one job and gates on a second one named `Baseline`, so branch
protection requires the same check everywhere while the jobs behind it change
here:

```yaml
name: Baseline
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
permissions:
  contents: read
jobs:
  checks:
    uses: metio/ci/.github/workflows/baseline.yml@<sha>
  baseline:
    name: Baseline
    needs: [checks]
    if: always()
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - env:
          RESULT: ${{ needs.checks.result }}
        run: '[ "$RESULT" = success ] || { echo "::error::the baseline checks ended in $RESULT"; exit 1; }'
```

It runs [`leaks`](#leaks), `reuse lint` and the [convention policies](#convention-policies) on every
push and pull request, and [`dco`](#developer-certificate-of-origin)
on pull requests that a person opened.

### Golang

The Go pipeline is **zero-config**: every job installs the calling repo's
toolchain with the [`breto`](#breto) action from its `.breto.edn`, so CI runs the
exact versions the metio/toolchains groups pin — identical to a local
`breto env` — and a `detect` job skips the architecture gate when there's no
`arch-go.yml`. A controller with envtest-backed tests and a plain library use the
identical call. The repo must ship a `.breto.edn` naming `@go` (see below).

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

`@go` provides every tool: `go`, `staticcheck`, `gosec`, `gofumpt`, `govulncheck`,
`arch-go` and `modernize`. A controller adds `@envtest`, which sets
`KUBEBUILDER_ASSETS`, so the envtest suite runs offline against the pinned
Kubernetes; the multi-version envtest
matrix is gone (its coverage lives in the kind smoke gate). The one thing `detect`
still decides: the `architecture` job runs only when an `arch-go.yml` is present;
otherwise it skips cleanly. The sole input, `runs-on`, exists for the rare runner
override.

### Frontend

The Vite/React pipeline is **breto-driven and convention-based**: every job installs
the calling repo's `.breto.edn` with the [`breto`](#breto) action, and a `detect` job reads the repo's
`package.json` scripts (and `lighthouserc.json`) to skip the gates a project
doesn't define — so one workflow fits projects that ship different subsets. The
repo must ship a `.breto.edn` naming `node` and `@lint`, and depend on `playwright`
for the vitest browser and a11y gates, whose jobs install the browsers named by the
`browsers` input (`chromium` by default).

```yaml
# .github/workflows/verify.yml in a Vite/React project
name: Verify
on:
  pull_request:
    branches: [main]
permissions:
  contents: read
jobs:
  frontend:
    name: Frontend        # checks then read "Frontend / build", "Frontend / lint", …
    uses: metio/ci/.github/workflows/frontend.yml@<sha>
    with:                 # both optional, both default sensibly
      node-options: --dns-result-order=ipv4first    # e.g. a prerender that binds localhost
      build-command: PLINKY_LOCALE=en npm run build # e.g. a single-locale bundle-size build

  # … the project's own repo-specific jobs …

  verify:
    name: Verify
    needs: [frontend]     # plus the project's other jobs
    if: always()
    runs-on: ubuntu-latest
    steps:
      - env:
          NEEDS: ${{ toJSON(needs) }}
        run: |
          bad=$(echo "$NEEDS" | jq -r 'to_entries[] | select(.value.result != "success" and .value.result != "skipped") | "\(.key)=\(.value.result)"')
          [ -z "$bad" ] || { echo "::error::$bad"; exit 1; }
```

Each gate keys off the script (or file) that enables it: `build` (typecheck +
test + build + `size`), `browser` (`test:browser`), `coverage` (`coverage`),
`lint` (`lint`), `knip` (`knip`), `accessibility-light` / `-dark` (`a11y:light` /
`a11y:dark`), and `lighthouse` (a `lighthouserc.json`) — plus the always-on shared
lint gate (`repository-lint`, which runs `breto run ci-lint`). Three inputs cover the
repo-specific bits: `node-options` (sets `NODE_OPTIONS` for every job), `build-command`
(the build/size and lighthouse invocation, e.g. a single-locale build for a per-visitor
bundle-size measurement) and `browsers`, alongside the shared `runs-on`.

### Maven

The Maven pipeline is **breto-driven and POM-driven**: the JDK and Maven come
from the calling repo's `.breto.edn`, and the gates themselves are the build. A
metio Java project inherits `wtf.metio.maven:maven-parent`, which configures the
static-analysis battery (checkstyle, pmd, spotbugs, dependency analysis, pitest)
into the `verify` lifecycle — so a plugin is added and tuned in the POM, where
Renovate maintains its version, rather than as another tool call in CI.

```yaml
# .github/workflows/verify.yml in a Maven project
# SPDX-License-Identifier: 0BSD
name: Verify
on:
  pull_request:
    branches: [main]
permissions:
  contents: read
jobs:
  maven:
    name: Maven           # checks then read "Maven / build", "Maven / javadoc"
    uses: metio/ci/.github/workflows/maven.yml@<sha>

  # … the project's own non-Maven jobs (reuse, yaml, markdown, dco, policy …) …

  verify:
    name: Verify
    needs: [maven]        # plus the project's other jobs
    if: always()
    runs-on: ubuntu-latest
    steps:
      - env:
          NEEDS: ${{ toJSON(needs) }}
        run: |
          bad=$(echo "$NEEDS" | jq -r 'to_entries[] | select(.value.result != "success" and .value.result != "skipped") | "\(.key)=\(.value.result)"')
          [ -z "$bad" ] || { echo "::error::$bad"; exit 1; }
```

The `build` job runs `mvn verify`; the `javadoc` job compiles the sources and
renders the Javadoc, because the javadoc plugin otherwise runs only in the
`release` profile and a broken doc comment would surface at release time. Both
jobs cache `~/.m2/repository` keyed on the POMs. Four optional inputs cover the
variation: `goals` (default `verify`), `maven-args` (default
`--batch-mode --no-transfer-progress`), `javadoc` (set `false` for a project
with no Java sources), and the shared `runs-on`.

### Maven Central release

`maven-central-release.yml` releases a project inheriting `maven-parent` on its
monthly slot (see [`central-quota`](#central-quota)). The `gate` job asks
[`needs-release`](#needs-release) whether `paths` changed since the last release
and `central-quota` whether the month's budget has room; only then does the
`central` job set the calendar version, sign and deploy through the `release`
profile, and the `github` job create the release that `central-quota` counts.

```yaml
# .github/workflows/release.yml in a Maven project
name: Release
on:
  schedule:
    - cron: 23 4 3 * *    # the repo's day of the month
  workflow_dispatch:
permissions:
  contents: write
concurrency:
  group: ${{ github.workflow }}
  cancel-in-progress: false
jobs:
  release:
    uses: metio/ci/.github/workflows/maven-central-release.yml@<sha>
    with:
      paths: src/main/java pom.xml
    secrets: inherit
```

The caller provides the secrets `MAVEN_CENTRAL_USERNAME`, `MAVEN_CENTRAL_TOKEN`,
`GPG_SECRET_KEY_BASE64` and `GPG_SECRET_KEY_PASSWORD`. `deploy-args` adds
arguments to the deploy, such as `--projects a --also-make` to publish only part
of a reactor.

## Actions

Composite actions for release pipelines — call them directly from a repo's
release workflow.

### `breto`

Installs [breto](https://github.com/metio/breto) from its signed release, installs
the packages of the project's `.breto.edn` and puts the project's tools and
variables on `PATH` and in the environment of the later steps:

```yaml
- uses: actions/checkout@<sha>
- uses: metio/ci/breto@<sha>
  with:
    registries: github:metio/toolchains
- run: breto run ci-lint
```

`version` picks the breto release (default `latest`), `project` the directory
holding the `.breto.edn` (default `.`), and `cache: false` skips the Actions cache
of installed packages. `packages` installs the packages it lists, separated by
spaces, in place of the project's `.breto.edn`. `registries` adds registries after
breto's default metio/packages, one per line: a directory in the workspace,
`github:OWNER/REPO` or `gitlab:gitlab.com/GROUP/PROJECT` for a registry published as
signed releases, or a breto registry map for other hosts and signers:

```yaml
    registries: |
      github:metio/toolchains
      {:forgejo "codeberg.org/OWNER/REPO" :signature false}
```

### `babashka-executable`

Turns an uberjar into self-contained executables for Linux and macOS on amd64 and
arm64, by prepending the babashka binary of each platform to it. A babashka
executable carries no JVM, so it suits programs that babashka can run as they are;
programs that load Java libraries need a native image or a JVM instead. It uses the
version of `bb` on `PATH`, so install that first with [`breto`](#breto).

```yaml
- run: bb uberjar target/tool.jar -m tool.main
- id: executable
  uses: metio/ci/babashka-executable@<sha>
  with:
    name: tool
    jar: target/tool.jar
    version: ${{ steps.version.outputs.version }}
- uses: metio/ci/cosign-sign-blob@<sha>
  with:
    file: ${{ steps.executable.outputs.checksums }}
- run: gh release create "$VERSION" dist/*
```

### `leaks`

Scans the commits a change adds for secrets with
[betterleaks](https://github.com/betterleaks/betterleaks): the base..head range
of a pull request, the before..after range of a push, and the whole history on
any other event. The job checks the repository out with `fetch-depth: 0`:

```yaml
- uses: actions/checkout@<sha>
  with:
    fetch-depth: 0
    persist-credentials: false
- uses: metio/ci/leaks@<sha>
```

Findings are redacted from the log. A finding that is no secret, such as a test
fixture, goes into `.betterleaksignore` at the repository root as the fingerprint
betterleaks prints for it. `range` takes git log options in place of the range
the event implies, such as `--all`, and `path` names another repository in the
workspace to scan.

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

### `central-quota`

Maven Central meters publishing **per organization**: 7 releases a calendar
month on the free tier, averaged over a rolling three-month window (plus 1,167
files and 78 MB). That budget is shared by every metio repo publishing under the
`wtf.metio` namespace, so no single repo's workflow can tell whether one more
release fits. This action counts what the Central-publishing repos already
released this month and answers that question:

```yaml
- id: quota
  uses: metio/ci/central-quota@<sha>
- if: steps.gate.outputs.needed == 'true' && steps.quota.outputs.available == 'true'
  run: mvn deploy
```

The canonical repo list lives in the action's `repos` default — add a repo there
when it starts publishing, and every caller picks it up on the next pin bump.
Skipping costs nothing: [`needs-release`](#needs-release) measures against the
last *release*, not the last run, so a repo passed over in a full month still
sees its changes at its next slot.

#### The Maven release rhythm

Central-publishing repos do **not** release per merge. Each runs a monthly
scheduled workflow on its own day-of-month slot, gated on
[`needs-release`](#needs-release) (did anything change?) and `central-quota`
(is there budget?). Staggering the slots spreads the deployments through the
month instead of bursting them, and gives the repos other projects build on the
earliest slots, so a downstream repo's own slot already sees the new parent:

| Day | Repo |
|---|---|
| 1 | `maven-parent` |
| 2 | `devcontainer.java` |
| 3 | `reguloj` |
| 4 | `storage-units.java` |
| 5 | `memoization.java` |
| 6 | `javapoet-type-guesser` |
| 8 | `yosql` |

Seven slots fit a budget of seven, and in a typical month most repos have no
changes and skip themselves. The quota guard holds the line when manual
`workflow_dispatch` runs push a month past the limit. The limit is a three-month average, so an
occasional busy month (a security fix, a coordinated bump) is expected to be fine.

A repo earns a slot by deploying to Central from its release workflow, which is
not the same as having a `pom.xml`: `ilo` is a Maven project that ships native
binaries on its GitHub release.

This applies only to Maven Central. GitHub releases, container images, and Go
modules are unmetered, so those repos keep releasing on every qualifying push.

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
Run the same locally with `conftest verify --policy policy`, with conftest from
`breto install conftest`.

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
- **Non-root containers** — the final stage of every `Containerfile` and
  `Dockerfile` declares a `USER` that is neither `root` nor uid `0`; without
  one, the image runs as whatever its base image defaults to. An image that
  ships only data, or has to run as root, such as a development shell, states
  why in a label of its final stage instead:
  `LABEL wtf.metio.ci.root-allowed="data image, runs nothing"`. The reason
  must not be empty, and a label of an earlier stage does not count.

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

## Developer Certificate of Origin

Every commit must carry a `Signed-off-by:` trailer (`git commit --signoff`), so
each contribution records agreement to the [DCO](https://developercertificate.org/).
The [`dco`](dco) composite action enforces it over the pull request range, and
the [Baseline](#baseline) workflow runs it in every repository, so the required
`Baseline` check fails a pull request with an unsigned commit. Bots (Renovate,
Dependabot) can not sign off, so their pull requests skip it.

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

[0BSD](LICENSES/0BSD.txt).
