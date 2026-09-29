#!/usr/bin/env sh
set -eu

script_dir="$(CDPATH='' cd -- "$(dirname "$0")" && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/zig-vst3-reference-check.XXXXXX")"
retired_name="$(printf '\152\165\143\145')"
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

initialize_repository() {
    repository="$1"
    mkdir -p "$repository"
    git -C "$repository" init -q
    git -C "$repository" config user.name "Repository Check"
    git -C "$repository" config user.email "repository-check@example.test"
    printf 'clean\n' >"$repository/tracked.txt"
    git -C "$repository" add tracked.txt
    git -C "$repository" commit -qm "Initial content"
}

expect_rejection() {
    repository="$1"
    category="$2"
    if "$script_dir/check_retired_reference.sh" "$repository" \
        >"$test_root/$category.stdout" \
        2>"$test_root/$category.stderr"; then
        printf 'reference checker accepted %s\n' "$category" >&2
        exit 1
    fi
}

clean_repository="$test_root/clean"
initialize_repository "$clean_repository"
"$script_dir/check_retired_reference.sh" "$clean_repository" >/dev/null

worktree_repository="$test_root/worktree"
initialize_repository "$worktree_repository"
printf '%s\n' "$retired_name" >"$worktree_repository/untracked.txt"
expect_rejection "$worktree_repository" "worktree content"

index_repository="$test_root/index"
initialize_repository "$index_repository"
printf '%s\n' "$retired_name" >"$index_repository/tracked.txt"
git -C "$index_repository" add tracked.txt
printf 'clean\n' >"$index_repository/tracked.txt"
expect_rejection "$index_repository" "index content"

content_repository="$test_root/historical-content"
initialize_repository "$content_repository"
printf '%s\n' "$retired_name" >"$content_repository/tracked.txt"
git -C "$content_repository" add tracked.txt
git -C "$content_repository" commit -qm "Add comparison"
printf 'clean\n' >"$content_repository/tracked.txt"
git -C "$content_repository" add tracked.txt
git -C "$content_repository" commit -qm "Remove comparison"
expect_rejection "$content_repository" "historical content"

message_repository="$test_root/commit-message"
initialize_repository "$message_repository"
printf 'changed\n' >"$message_repository/tracked.txt"
git -C "$message_repository" add tracked.txt
git -C "$message_repository" commit -qm "Mention $retired_name"
expect_rejection "$message_repository" "commit message"

path_repository="$test_root/historical-path"
initialize_repository "$path_repository"
printf 'clean\n' >"$path_repository/$retired_name.txt"
git -C "$path_repository" add "$retired_name.txt"
git -C "$path_repository" commit -qm "Add comparison file"
git -C "$path_repository" rm -q "$retired_name.txt"
git -C "$path_repository" commit -qm "Remove comparison file"
expect_rejection "$path_repository" "historical path"

tag_repository="$test_root/tag"
initialize_repository "$tag_repository"
git -C "$tag_repository" tag -am "Mention $retired_name" comparison
expect_rejection "$tag_repository" "tag message"

ref_repository="$test_root/ref"
initialize_repository "$ref_repository"
git -C "$ref_repository" branch "comparison-$retired_name"
expect_rejection "$ref_repository" "ref name"

printf 'retired comparison reference checker tests passed\n'
