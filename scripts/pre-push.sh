#!/bin/sh
# There is no CI on everyday work, so this hook runs every check before anything leaves the machine.
set -e

zero=0000000000000000000000000000000000000000
changed=""
while read -r local_ref local_sha remote_ref remote_sha; do
  [ "$local_sha" = "$zero" ] && continue
  if [ "$remote_sha" = "$zero" ]; then
    base=$(git merge-base "$local_sha" origin/main 2>/dev/null || git rev-list --max-parents=0 "$local_sha" | tail -1)
  else
    base=$remote_sha
  fi
  changed="$changed
$(git diff --name-only "$base" "$local_sha")"
done
changed=$(printf '%s\n' "$changed" | sed '/^$/d' | sort -u)

if [ -z "$changed" ]; then
  echo "pre-push: nothing to check"
  exit 0
fi
if ! printf '%s\n' "$changed" | grep -qv '\.md$'; then
  echo "pre-push: only Markdown changed, skipping checks"
  exit 0
fi

run() { echo "pre-push: $*"; "$@"; }
run bun run check:version
run bun install --frozen-lockfile
run bun run typecheck
run bun run lint
run bun run test
run bun run build
run bun run check:package
run bun run check:publish
run bun run check:size

# GPU checks need a real adapter, so they only run when rendering code changes.
if printf '%s\n' "$changed" | grep -qE '^(packages/liquid-glass/src/(gpu|core)/|scripts/gpu-smoke\.mjs|packages/liquid-glass/package\.json|bun\.lock)'; then
  run bun run check:gpu
  run bun run check:shader
  run bun run test:gpu
fi
echo "pre-push: all checks passed"
