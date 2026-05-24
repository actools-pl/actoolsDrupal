#!/usr/bin/env bats
# =============================================================================
# tests/installer/doctor_test.bats — Tests for cli/commands/doctor.sh
#
# `actools doctor` calls real docker, curl, and database commands — full
# happy-path testing requires a running stack and lives in the e2e
# workflow. These tests cover deterministic behaviour:
#   - The --deep gate returns the Pro-required notice
#   - The deep gate exits with code 2 (parity with audit --deep)
#   - The output helpers render correctly without colour
# =============================================================================

setup() {
  export INSTALL_DIR
  INSTALL_DIR="$(mktemp -d)"
  # Stage a no-op env file so doctor.sh can source it
  touch "${INSTALL_DIR}/actools.env"
  cp "${BATS_TEST_DIRNAME}/../../installer/output.sh" "${INSTALL_DIR}/installer/output.sh" 2>/dev/null || {
    mkdir -p "${INSTALL_DIR}/installer"
    cp "${BATS_TEST_DIRNAME}/../../installer/output.sh" "${INSTALL_DIR}/installer/output.sh"
  }
  mkdir -p "${INSTALL_DIR}/cli/commands"
  cp "${BATS_TEST_DIRNAME}/../../cli/commands/doctor.sh"      "${INSTALL_DIR}/cli/commands/doctor.sh"
  cp "${BATS_TEST_DIRNAME}/../../cli/commands/doctor_deep.sh" "${INSTALL_DIR}/cli/commands/doctor_deep.sh"

  export ACTOOLS_PLAIN=1
}

teardown() {
  rm -rf "$INSTALL_DIR"
}

@test "doctor --deep returns Pro-required notice" {
  source "${INSTALL_DIR}/cli/commands/doctor.sh"
  run run_doctor --deep
  [ "$status" -eq 2 ]
  [[ "$output" == *"requires Actools Pro"* ]]
  [[ "$output" == *"€49"* ]]
}

@test "doctor --deep mentions the upgrade URL" {
  source "${INSTALL_DIR}/cli/commands/doctor.sh"
  run run_doctor --deep
  [[ "$output" == *"actools.feesix.com/pro"* ]]
}

@test "doctor --deep names the free coverage" {
  source "${INSTALL_DIR}/cli/commands/doctor.sh"
  run run_doctor --deep
  [[ "$output" == *"site"* ]]
  [[ "$output" == *"TLS"* ]]
  [[ "$output" == *"containers"* ]]
  [[ "$output" == *"backups"* ]]
}

@test "doctor --deep names the Pro additions" {
  source "${INSTALL_DIR}/cli/commands/doctor.sh"
  run run_doctor --deep
  [[ "$output" == *"trend regression"* ]]
  [[ "$output" == *"drift"* ]]
  [[ "$output" == *"forecasting"* ]]
  [[ "$output" == *"Anomaly detection"* ]]
}

@test "doctor_deep returns exit code 2 (parity with audit --deep)" {
  source "${INSTALL_DIR}/cli/commands/doctor_deep.sh"
  run run_doctor_deep
  [ "$status" -eq 2 ]
}
