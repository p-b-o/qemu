#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later

set -euo pipefail

if [ $# -lt 2 ]; then
    echo "usage: branch_name series_message_ids..."
    exit 1
fi

branch=$1; shift

git diff --exit-code

current_branch=$(git branch --show-current)
trap "git checkout $current_branch >& /dev/null" EXIT

cat > changes << EOF
CI $branch:
- https://github.com/p-b-o/qemu/tree/$branch-github-ci
- https://gitlab.com/pbo-linaro/qemu/-/tree/$branch-gitlab-ci
---------------------------------
Changes:
EOF

for series in "$@"; do
    subject=$(b4 mbox --single-message $series -o - | grep "^Subject: " |
              head -n 1 | sed -e 's/^Subject: //')
    from=$(b4 mbox --single-message $series -o - | grep "^From: " |
           head -n 1 | sed -e 's/^From: //')
    link="Link: https://lore.kernel.org/qemu-devel/$series"
    echo "- $subject ($from)" >> changes
    echo "  $link" >> changes
done

echo '--------------------------------------------------'
cat changes
echo '--------------------------------------------------'

git branch -D ${branch}_base || true
git branch -D ${branch} || true
git checkout -b ${branch}_base
git reset --hard upstream/master

git checkout -b ${branch}

for series in "$@"; do
    echo '--------------------------------------------------'
    echo "Apply series $series"
    echo '--------------------------------------------------'
    b4 shazam --sloppy-trailers --add-link $series ||
        { git am --abort; exit 1; }
done

git checkout $current_branch
./pull_request_publish.sh $branch
