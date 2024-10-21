#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "usage: branch [git-publish options]..."
    exit 1
fi

PULL_REQUEST=${PULL_REQUEST:-}

current_branch=$(git branch --show-current)
patches=$(mktemp -d)
trap "rm -rf $patches; git checkout $current_branch >& /dev/null" EXIT

branch=$1; shift
base_revision=${branch}_base

# export patches
git format-patch ${base_revision}..${branch} -o $patches

# create publish branch
git fetch -a upstream
git checkout -b $branch-publish || git checkout $branch-publish
git reset --hard upstream/master

# apply and check patches
if ! git am $patches/*; then
    git am --show-current-patch=diff
    git am --abort
    exit 1
fi
./scripts/checkpatch.pl $(git merge-base upstream/master HEAD)..HEAD

# check tags
if [ "$PULL_REQUEST" == "1" ]; then
    echo "--------------------------------------------------------"
    err=0
    for p in $patches/*; do
        if ! grep -q -i 'Reviewed-by:' $p > /dev/null; then
            echo ERROR: $p missing 'Reviewed-by:'
            err=1
        fi

        if ! grep -q -i 'Link:' $p > /dev/null; then
            echo ERROR: $p missing 'Link:'
            err=1
        fi
    done

    if [ $err == 1 ]; then
        echo "ERROR: missing reviews or link"
        echo "--------------------------------------------------------"
        exit 1
    fi
    echo "--------------------------------------------------------"
fi

# add GitHub CI on top
echo "--------------------------------------------------------"
git checkout -b $branch-github-ci || git checkout $branch-github-ci
git reset --hard $branch-publish
git merge ci --squash --ff
mv .github/workflows/build.yml build.yml
git rm -f .github/workflows/*
mkdir -p .github/workflows/
mv build.yml .github/workflows/
git add .github
git commit -a -m 'ci' --signoff
git push --force --set-upstream origin $branch-github-ci
echo "--------------------------------------------------------"

# Add Gitlab CI
if [ "$PULL_REQUEST" == "1" ]; then
    git checkout -b $branch-gitlab-ci || git checkout $branch-gitlab-ci
    git reset --hard $branch-publish
    git cherry-pick gitlab_ci_full~1
    git push --force --set-upstream gitlab $branch-gitlab-ci
    echo "--------------------------------------------------------"
fi

# publish (! pull request)
if [ "$PULL_REQUEST" != "1" ]; then
    git checkout $branch-publish
    if ! git publish --base upstream/master "$@"; then
        exit 1
    fi
    echo "--------------------------------------------------------"
fi

echo "CI for $branch:"
echo "- https://github.com/p-b-o/qemu/tree/$branch-github-ci"
if [ "$PULL_REQUEST" == "1" ]; then
    echo "- https://gitlab.com/pbo-linaro/qemu/-/tree/$branch-gitlab-ci"
fi
exit 0
