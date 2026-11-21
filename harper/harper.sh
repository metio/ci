#!/usr/bin/env bash
# SPDX-FileCopyrightText: The ci Authors
# SPDX-License-Identifier: 0BSD

# Lints the prose of the Markdown files git tracks under the given paths, or
# under docs and kb, or the whole tree when neither exists. Files git marks
# linguist-generated are skipped, since their prose is fixed where they are
# generated. Each finding prints as PATH:LINE:COLUMN: RULE: MESSAGE, and as a
# workflow annotation inside GitHub Actions.
#
# HARPER_IGNORE adds rules to skip. HARPER_FAIL=false reports findings and
# exits 0; anything else exits 1 on a finding. metio/toolchains runs the same
# rules in its ci-harper command, so a change here goes there as well.
set -euo pipefail

ignore="SpellCheck,UseTitleCase,SentenceCapitalization,SplitWords,OrthographicConsistency,ExpandConfiguration,CompoundNouns,MassNouns,Everyone${HARPER_IGNORE:+,${HARPER_IGNORE}}"

if [ "$#" -eq 0 ]; then
  for dir in docs kb; do
    if [ -d "${dir}" ]; then set -- "$@" "${dir}"; fi
  done
  if [ "$#" -eq 0 ]; then set -- .; fi
fi

level=error
if [ "${HARPER_FAIL:-true}" = false ]; then level=warning; fi

files=()
while IFS= read -r -d '' file && IFS= read -r -d '' _ && IFS= read -r -d '' generated; do
  case "${generated}" in
    set | true) ;;
    *) files+=("${file}") ;;
  esac
done < <(git ls-files -z -- "$@" | { grep -zE '\.(md|markdown)$' || true; } | git check-attr -z --stdin linguist-generated)
if [ "${#files[@]}" -eq 0 ]; then exit 0; fi

# harper reports one entry per input, in input order, and names each file by
# its base name only, so the paths are matched back by position.
errors=$(mktemp)
trap 'rm -f "${errors}"' EXIT
status=0
report=$(harper-cli lint --format json --ignore "${ignore}" "${files[@]}" 2> "${errors}") || status=$?
if ! printf '%s' "${report}" | jq -e --argjson n "${#files[@]}" 'type == "array" and length == $n' > /dev/null 2>&1; then
  cat "${errors}" >&2
  echo "[ERROR] harper-cli exited with ${status} and no report of every file" >&2
  exit 2
fi
lines=$(printf '%s' "${report}" | jq -r --args --arg level "${level}" --arg actions "${GITHUB_ACTIONS:-}" '
  [., $ARGS.positional] | transpose[] | .[1] as $path | .[0].lints[]
  | "\($path):\(.line):\(.column): \(.kind)::\(.rule): \(.message)",
    (select($actions != "") | "::\($level) file=\($path),line=\(.line),col=\(.column),title=\(.kind)::\(.rule)::\(.message)")
' "${files[@]}")
if [ -n "${lines}" ]; then printf '%s\n' "${lines}"; fi
findings=$(printf '%s' "${report}" | jq '[.[].lint_count] | add // 0')

if [ "${findings}" -gt 0 ]; then
  echo "[INFO] harper found ${findings} problems in the prose"
  if [ "${level}" = error ]; then exit 1; fi
fi
