#!/usr/bin/env bash
# =============================================================================
# tests/db/mock_docker.bash — the P0-M `docker` stub (contract/mock tests).
#
# The DB layer is STATEFUL — every function shells out to `docker` against a
# live MariaDB container — so there is no rendered output to golden-capture.
# Instead the contract tests interpose this stub as `docker` on PATH and
# assert the COMMANDS and SQL each function issues: behavior is pinned with
# no live DB and no docker daemon.
#
# install_mock_docker <dir>
#   Writes <dir>/bin/docker, exports MOCK_DOCKER_DIR=<dir>, and prepends
#   <dir>/bin to PATH. Each invocation of the stub:
#     * bumps the attempt counter in <dir>/count
#     * records its argv NUL-separated in <dir>/argv.N — args can contain
#       newlines (the multi-line `sh -c` bodies do), so NUL is the only safe
#       separator
#     * drains stdin (when not a tty) into <dir>/stdin.N — this is where the
#       heredoc SQL and the defaults-extra-file content show up
#     * exits 1 while N <= MOCK_DOCKER_FAIL_FIRST (default 0: never), else
#       exits MOCK_DOCKER_RC (default 0) — the knobs wait_db's polling and
#       check_db_creds' failure path are driven with
#
# mock_docker_calls <dir>      — echoes the number of invocations so far
# mock_docker_argv  <dir> <N>  — loads invocation N's argv into the global
#                                MOCK_ARGV array
# =============================================================================

install_mock_docker() {
  local dir="$1"
  mkdir -p "$dir/bin"
  cat > "$dir/bin/docker" <<'STUB'
#!/usr/bin/env bash
set -u
dir="${MOCK_DOCKER_DIR:?MOCK_DOCKER_DIR not set}"
n=$(( $(cat "$dir/count" 2>/dev/null || echo 0) + 1 ))
printf '%s' "$n" > "$dir/count"
printf '%s\0' "$@" > "$dir/argv.$n"
if [ ! -t 0 ]; then cat > "$dir/stdin.$n"; fi
if [ "$n" -le "${MOCK_DOCKER_FAIL_FIRST:-0}" ]; then exit 1; fi
exit "${MOCK_DOCKER_RC:-0}"
STUB
  chmod +x "$dir/bin/docker"
  export MOCK_DOCKER_DIR="$dir"
  PATH="$dir/bin:$PATH"
  export PATH
}

mock_docker_calls() {
  cat "$1/count" 2>/dev/null || echo 0
}

mock_docker_argv() {
  local dir="$1" n="$2" _a
  MOCK_ARGV=()
  while IFS= read -r -d '' _a; do MOCK_ARGV+=("$_a"); done < "$dir/argv.$n"
}
