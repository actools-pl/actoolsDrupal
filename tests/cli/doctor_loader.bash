#!/usr/bin/env bash
# =============================================================================
# tests/cli/doctor_loader.bash — P0-N loader for the live doctor command.
#
# load_doctor <install_dir>
#   Sources <install_dir>/cli/commands/doctor.sh into the calling shell with
#   INSTALL_DIR pointed at <install_dir> — exactly how the live CLI loads it
#   (cli/actools resolves INSTALL_DIR at :7, then sources doctor.sh at :90).
#   Fails loudly (rc 1) if run_doctor does not come out defined.
#
# The loader deliberately does NOT require db_exec_root: the focused test's
# resolution arms assert it BOTH ways — defined (≡ modules/db/core.sh) when
# the authority is present at ${INSTALL_DIR}/modules/db/core.sh, and absent
# when it is not (a minimal sandbox) — proving the definition genuinely comes
# from the module path, not from a hidden local copy. That pair is what makes
# doctor.sh's best-effort `source … || true` non-vacuous (a typo'd module
# path fails the defined-arm).
# =============================================================================

load_doctor() {
  local install_dir="$1"
  [[ -f "$install_dir/cli/commands/doctor.sh" ]] \
    || { echo "load_doctor: no doctor.sh under: $install_dir" >&2; return 1; }
  INSTALL_DIR="$install_dir"
  export INSTALL_DIR
  # shellcheck source=/dev/null
  source "$install_dir/cli/commands/doctor.sh"
  declare -F run_doctor >/dev/null \
    || { echo "load_doctor: run_doctor() not defined after sourcing doctor.sh" >&2; return 1; }
}
