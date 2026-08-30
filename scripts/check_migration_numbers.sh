#!/usr/bin/env bash
# Fails if two different migration files share the same leading number -
# exactly the failure mode that hit this repo once already: two branches
# each independently picked "the next free number" (0049-0053), unaware
# of each other, and only the manual merge conflict caught it. Run on
# every PR against supabase/migrations/**, checked out at the PR's merge
# ref (GitHub's default for pull_request triggers), so a collision
# between this branch's new migration and one already merged on the base
# branch shows up here before it ever reaches a human to untangle.
#
# 0002 is the one intentional exception: 0002_roles_step1_enum.sql and
# 0002_roles_step2_policies.sql share a number on purpose (see the
# README) because Postgres won't let a new enum value be used in the
# same transaction that created it, so the migration had to be split into
# two files that are still meant to run back-to-back as one logical step.

set -euo pipefail

cd "$(dirname "$0")/.."

allowlist=("0002")

declare -A seen
failed=0

for path in supabase/migrations/*.sql; do
  filename="$(basename "$path")"
  number="${filename%%_*}"

  if [[ ! "$number" =~ ^[0-9]{4}$ ]]; then
    echo "::error file=$path::Migration filename doesn't start with a 4-digit number: $filename"
    failed=1
    continue
  fi

  is_allowed=0
  for allowed in "${allowlist[@]}"; do
    if [[ "$number" == "$allowed" ]]; then
      is_allowed=1
    fi
  done
  if [[ "$is_allowed" == 1 ]]; then
    continue
  fi

  if [[ -n "${seen[$number]:-}" ]]; then
    echo "::error file=$path::Migration number $number is used by both ${seen[$number]} and $filename - rename one of them to the next free number."
    failed=1
  else
    seen[$number]="$filename"
  fi
done

if [[ "$failed" == 1 ]]; then
  echo
  echo "Found colliding migration numbers - see errors above."
  exit 1
fi

echo "No colliding migration numbers found."
