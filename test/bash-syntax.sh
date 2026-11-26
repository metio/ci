#!/usr/bin/env bash
# SPDX-FileCopyrightText: The ci Authors
# SPDX-License-Identifier: 0BSD

# Parses every bash `run:` script of the actions and workflows, and every bash
# script git tracks, with the bash on PATH and with bash 3.2 in a container.
# macOS runners run `shell: bash` with /bin/bash 3.2, which rejects scripts a
# current bash accepts, such as a case pattern without its leading `(` inside
# `$( )`. Most reusable workflows take `runs-on`, so a script here may meet
# that bash.
#
# Before the real files, the check runs over test/fixtures/bash32, whose
# scripts bash 3.2 must reject and the bash on PATH must accept, so a check
# that went blind fails instead of passing.
#
# Needs yq (mikefarah) and docker or podman; CONTAINER_RUNTIME picks one.
set -euo pipefail

bash32_image=docker.io/library/bash:3.2
root=$(git rev-parse --show-toplevel)
cd "$root"

runtime=${CONTAINER_RUNTIME:-}
if [ -z "$runtime" ]; then
  if command -v docker > /dev/null; then runtime=docker; else runtime=podman; fi
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# extract DIR FILE... writes each bash run script of the given actions and
# workflows, and each given shell script, to its own file in DIR. Expressions
# become a plain word, as GitHub substitutes them before bash parses the script.
extract() {
  local dir=$1 file count i name
  shift
  mkdir -p "$dir"
  for file in "$@"; do
    name=$(printf '%s' "$file" | tr '/.' '__')
    case "$file" in
      *.sh)
        cp "$file" "${dir}/${name}.sh"
        continue
        ;;
    esac
    # Composite actions name their shell on every step; workflow steps without
    # one run with bash, as no workflow here sets defaults.run.shell.
    count=$(yq '[(.runs.steps[]?, .jobs[]?.steps[]?) | select(has("run"))] | length' "$file")
    for ((i = 0; i < count; i++)); do
      yq "[(.runs.steps[]?, .jobs[]?.steps[]?) | select(has(\"run\"))] | .[${i}]" "$file" > "${work}/step"
      case "$(yq '.shell // "bash"' "${work}/step")" in
        bash | "bash "*) ;;
        *) continue ;;
      esac
      {
        printf '# %s, step %d: %s\n' "$file" "$i" "$(yq '.name // .id // ""' "${work}/step")"
        yq '.run' "${work}/step" | sed 's/\${{[^}]*}}/EXPR/g'
      } > "${dir}/${name}-${i}.sh"
    done
  done
}

# check DIR prints one line per script of DIR and bash, the bash on PATH and
# bash 3.2: the bash's major.minor version, "ok" or "rejected", and the
# script's first line. A script that went missing exits non-zero rather than
# printing nothing.
# shellcheck disable=SC2016 # expanded by the bash that runs the check
check='set -eu
for script in "$1"/*.sh; do
  [ -f "$script" ] || exit 3
  if bash -n "$script" 2> /dev/null; then result=ok; else result=rejected; fi
  printf "%s\t%s\t%s\n" "${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}" "$result" "$(head -n 1 "$script")"
done'
parse() {
  local dir=$1
  bash -c "$check" check "$dir"
  # shellcheck disable=SC2016 # expanded inside the container
  tar -C "$dir" -c . | "$runtime" run --rm -i "$bash32_image" \
    sh -c 'dir=$(mktemp -d) && tar -C "$dir" -x && exec bash -c "$1" check "$dir"' sh "$check"
}

# count RESULTS VERSION OUTCOME counts the lines of RESULTS for that bash
# (3.2, or "current" for every other) and outcome (ok, rejected or any).
count() {
  printf '%s\n' "$1" | awk -F '\t' -v version="$2" -v outcome="$3" '
    NF >= 2 && (version == "3.2" ? $1 == "3.2" : $1 != "3.2") && (outcome == "any" || $2 == outcome) { n++ }
    END { print n + 0 }'
}

extract "${work}/fixtures" test/fixtures/bash32/*.yml
fixtures=$(find "${work}/fixtures" -name '*.sh' | wc -l)
results=$(parse "${work}/fixtures")
if [ "$fixtures" -eq 0 ] ||
  [ "$(count "$results" 3.2 rejected)" -ne "$fixtures" ] ||
  [ "$(count "$results" current ok)" -ne "$fixtures" ]; then
  echo "::error::bash 3.2 must reject each of the ${fixtures} fixture scripts and the bash on PATH accept them; they reported:"
  printf '%s\n' "$results"
  exit 1
fi
echo "bash 3.2 rejects all ${fixtures} fixture scripts, the bash on PATH accepts them"

files=()
while IFS= read -r file; do files+=("$file"); done < <(
  git ls-files -- '*/action.yml' '*/action.yaml' '.github/workflows/*.yml' '.github/workflows/*.yaml'
  git ls-files -- '*.sh' ':!:test/fixtures/*'
)
extract "${work}/scripts" "${files[@]}"
scripts=$(find "${work}/scripts" -name '*.sh' | wc -l)
results=$(parse "${work}/scripts")
if [ "$(count "$results" 3.2 any)" -ne "$scripts" ] || [ "$(count "$results" current any)" -ne "$scripts" ]; then
  echo "::error::each bash must report on all ${scripts} scripts; they reported:"
  printf '%s\n' "$results"
  exit 1
fi
if [ "$(count "$results" 3.2 rejected)" -ne 0 ] || [ "$(count "$results" current rejected)" -ne 0 ]; then
  printf '%s\n' "$results" | awk -F '\t' '$2 == "rejected" { print "::error::bash " $1 " rejects " $3 }'
  exit 1
fi
echo "bash ${BASH_VERSION} and bash 3.2 parse all ${scripts} bash scripts of ${#files[@]} files"
