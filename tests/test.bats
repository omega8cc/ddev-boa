#!/usr/bin/env bats

# ddev-boa test suite (bats). Structure follows ddev/ddev-addon-template.
#
# Copyright (C) 2009-2026 Omega8.cc — noc@omega8.cc www.omega8.cc
# Free software under the GNU GPL, version 2 or later.
#
# The pull itself needs a live BOA server and SSH credentials, so CI tests the
# whole offline surface instead: the add-on installs and removes cleanly, the
# project restarts with it, and every command fails closed — loudly and fast —
# when the provider file is unconfigured or carries unsafe values.
#
# Local run, from the add-on root (needs bats-core, bats-assert, bats-file,
# bats-support):
#   bats ./tests/test.bats
# To exclude the release test:
#   bats ./tests/test.bats --filter-tags '!release'

setup() {
  set -eu -o pipefail

  export GITHUB_REPO=omega8cc/ddev-boa

  TEST_BREW_PREFIX="$(brew --prefix 2>/dev/null || true)"
  export BATS_LIB_PATH="${BATS_LIB_PATH}:${TEST_BREW_PREFIX}/lib:/usr/lib/bats"
  bats_load_library bats-assert
  bats_load_library bats-file
  bats_load_library bats-support

  export DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." >/dev/null 2>&1 && pwd)"
  export PROJNAME="test-$(basename "${GITHUB_REPO}")"
  mkdir -p "${HOME}/tmp"
  export TESTDIR="$(mktemp -d "${HOME}/tmp/${PROJNAME}.XXXXXX")"
  export DDEV_NONINTERACTIVE=true
  export DDEV_NO_INSTRUMENTATION=true
  ddev delete -Oy "${PROJNAME}" >/dev/null 2>&1 || true
  cd "${TESTDIR}"
  run ddev config --project-name="${PROJNAME}" --project-tld=ddev.site
  assert_success
  run ddev start -y
  assert_success
}

health_checks() {
  # The three project files land where DDEV expects them.
  assert_file_exist .ddev/providers/boa.yaml
  assert_file_exist .ddev/commands/host/boa-aliases
  assert_file_exist .ddev/commands/host/boa-config

  # Unconfigured commands fail closed with a message that says what to set.
  run ddev boa-aliases
  assert_failure
  assert_output --partial "set BOA_SSH_USER and BOA_HOST"

  run ddev boa-config
  assert_failure
  assert_output --partial "set BOA_SSH_USER, BOA_HOST and BOA_ALIAS"

  # An unconfigured pull dies in the provider's own validation, before any
  # network step (fast; DDEV surfaces only its own failure line, the
  # provider's message goes to the hidden auth stderr).
  run ddev pull boa -y
  assert_failure
  assert_output --partial "Pull failed"

  # The injection guard: unsafe characters in the provider file are refused.
  sed -i.bak -e 's/^\([[:space:]]*BOA_SSH_USER:\).*/\1 "bad;user"/' \
    -e 's/^\([[:space:]]*BOA_HOST:\).*/\1 "boa.example.com"/' \
    .ddev/providers/boa.yaml
  run ddev boa-aliases
  assert_failure
  assert_output --partial "invalid characters"
  mv .ddev/providers/boa.yaml.bak .ddev/providers/boa.yaml
}

teardown() {
  set -eu -o pipefail
  ddev delete -Oy "${PROJNAME}" >/dev/null 2>&1
  if [ -n "${GITHUB_ENV:-}" ]; then
    [ -e "${GITHUB_ENV:-}" ] && echo "TESTDIR=${HOME}/tmp/${PROJNAME}" >> "${GITHUB_ENV}"
  else
    [ "${TESTDIR}" != "" ] && rm -rf "${TESTDIR}"
  fi
}

@test "install from directory" {
  set -eu -o pipefail
  echo "# ddev add-on get ${DIR} with project ${PROJNAME} in $(pwd)" >&3
  run ddev add-on get "${DIR}"
  assert_success
  run ddev restart -y
  assert_success
  health_checks
}

@test "add-on removes cleanly" {
  set -eu -o pipefail
  run ddev add-on get "${DIR}"
  assert_success
  run ddev add-on remove ddev-boa
  assert_success
  assert_file_not_exist .ddev/providers/boa.yaml
  assert_file_not_exist .ddev/commands/host/boa-aliases
  assert_file_not_exist .ddev/commands/host/boa-config
  run ddev restart -y
  assert_success
}

# bats test_tags=release
@test "install from release" {
  set -eu -o pipefail
  echo "# ddev add-on get ${GITHUB_REPO} with project ${PROJNAME} in $(pwd)" >&3
  run ddev add-on get "${GITHUB_REPO}"
  assert_success
  run ddev restart -y
  assert_success
  health_checks
}
