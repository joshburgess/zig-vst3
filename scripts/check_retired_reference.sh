#!/usr/bin/env sh
set -eu

script_dir="$(CDPATH='' cd -- "$(dirname "$0")" && pwd)"
repository="${1:-$script_dir/..}"
pattern='[jJ][uU][cC][eE]'

git -C "$repository" rev-parse --git-dir >/dev/null

if git -C "$repository" ls-files -co --exclude-standard |
    grep -Eiq "$pattern"; then
    printf 'retired comparison reference found in a worktree path\n' >&2
    exit 1
fi

if git -C "$repository" grep --no-index -I -q -E "$pattern" -- .; then
    printf 'retired comparison reference found in worktree content\n' >&2
    exit 1
fi

if git -C "$repository" grep --cached -I -q -E "$pattern" --; then
    printf 'retired comparison reference found in index content\n' >&2
    exit 1
fi

if git -C "$repository" for-each-ref --format='%(refname)' |
    grep -Eiq "$pattern"; then
    printf 'retired comparison reference found in a Git ref name\n' >&2
    exit 1
fi

if git -C "$repository" for-each-ref --format='%(contents)' |
    grep -Eiq "$pattern"; then
    printf 'retired comparison reference found in Git ref content\n' >&2
    exit 1
fi

if git -C "$repository" log --all --format='%B' |
    grep -Eiq "$pattern"; then
    printf 'retired comparison reference found in commit text\n' >&2
    exit 1
fi

if git -C "$repository" log --all --name-only --format= |
    grep -Eiq "$pattern"; then
    printf 'retired comparison reference found in a historical path\n' >&2
    exit 1
fi

# Revision IDs contain no whitespace. One grep lets Git reuse object traversal.
# shellcheck disable=SC2046
set -- $(git -C "$repository" rev-list --all)
if [ "$#" -gt 0 ]; then
    set +e
    git -C "$repository" grep -I -q -E "$pattern" "$@" --
    result_code=$?
    set -e
    case "$result_code" in
        0)
            printf 'retired comparison reference found in reachable history\n' >&2
            exit 1
            ;;
        1) ;;
        *)
            printf 'retired comparison reference history scan failed\n' >&2
            exit "$result_code"
            ;;
    esac
fi

printf 'retired comparison reference scan passed\n'
