#!/usr/bin/env bash
set -euo pipefail

# ci-upload-benchmarks-s3.sh
#
# SUMMARY
#
#   This uploads raw criterion benchmark results to S3 for later analysis via
#   Athena.
#
#   It should only be run in CI as we want to ensure that the benchmark
#   environment is consistent.

if !(${CI:-false}); then
  echo "Aborted: this script is for use in CI, bencmark analysis depends on a consistent bench environment" >&2
  exit 1
fi

escape() {
  echo $1 | sed "s#/#%2F#"
}

S3_BUCKET=${S3_BUCKET:-test-artifacts.vector.dev}
BENCHES_VERSION="1" # bump if S3 schema changes
ENVIRONMENT_VERSION="1" # bump if bench environment changes
VECTOR_THREADS=${VECTOR_THREADS:-$(nproc)}
LIBC="gnu"

git_branch=$(git branch --show-current)
git_rev_count=$(git rev-list --count HEAD)
git_sha=$(git rev-parse HEAD)
machine=$(uname --machine)
operating_system=$(uname --kernel-name)
year=$(date +"%Y")
month=$(date +"%m")
day=$(date +"%d")
timestamp=$(date +"%s")

IFS=$'\n'
for baseline in $(find target/criterion -type d -name new) ; do
  IFS=$'\t' read -r group_id function_id value_str < <(cat $baseline/benchmark.json | jq --raw-output '[.group_id, .function_id, .value_str] | @tsv')

  object_name="$(echo "s3://$S3_BUCKET/benches/\
benches_version=${BENCHES_VERSION}/\
environment_version=${ENVIRONMENT_VERSION}/\
group=$(escape "${group_id}")/\
function=$(escape "${function_id}")/\
value=$(escape "${value_str}")/\
branch=${git_branch}/\
machine=${machine}/\
operating_system=${operating_system}/\
libc=${LIBC}/\
threads=${VECTOR_THREADS}/\
year=${year}/\
month=${month}/\
day=${day}/\
rev_count=${git_rev_count}/\
sha=${git_sha}/\
timestamp=${timestamp}/\
raw.csv" | tr '[:upper:]' '[:lower:]'
)"

  # drop first three columns since we use these as partition keys
  cat $baseline/raw.csv | cut --delimiter=, --complement --fields=1-3 | aws s3 cp - $object_name
done
