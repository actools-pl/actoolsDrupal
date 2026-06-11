#!/usr/bin/env bash
# =============================================================================
# tests/guards/live_closure.bash — shared engine for the P0-K anti-regression
# guards (live-authority guard + duplicate-function guard).
#
# build_live_closure <repo_root> fills the global CLOSURE array with every
# repo file reachable via `source` from actools.sh — the live install path.
# It handles the two source forms the live tree uses:
#
#   static : source "${INSTALL_DIR}/installer/dispatch.sh"
#   looped : for _hostmod in packages age ...; do
#              source "${INSTALL_DIR}/modules/host/${_hostmod}.sh"
#
# Source targets NOT anchored at ${INSTALL_DIR} ("$ENV_FILE", "$_PROFILE_FILE")
# are runtime data / dynamic profile selection, not repo modules — skipped.
#
# The traversal is transitive (installer/init.sh -> installer/profile.sh, ...).
# =============================================================================

build_live_closure() {
  local repo="$1"
  local -a queue=("actools.sh")
  local -A seen=()
  local f target var list item

  while ((${#queue[@]})); do
    f="${queue[0]}"; queue=("${queue[@]:1}")
    [[ -n "${seen[$f]:-}" ]] && continue
    [[ -f "$repo/$f" ]] || continue
    seen[$f]=1

    while IFS= read -r target; do
      [[ -z "$target" ]] && continue
      if [[ "$target" == *'${'* ]]; then
        # Loop-interpolated target, e.g. modules/host/${_hostmod}.sh:
        # expand it using the file's `for <var> in <list>; do` line.
        var="$(printf '%s' "$target" | sed -n -E 's/.*\$\{([A-Za-z_][A-Za-z0-9_]*)\}.*/\1/p')"
        [[ -z "$var" ]] && continue
        list="$(sed -n -E "s/^[[:space:]]*for[[:space:]]+${var}[[:space:]]+in[[:space:]]+([^;]+);[[:space:]]*do.*/\1/p" "$repo/$f" | head -1)"
        [[ -z "$list" ]] && continue
        for item in $list; do
          queue+=("${target//\$\{${var}\}/$item}")
        done
      else
        queue+=("$target")
      fi
    done < <(sed -n -E 's/^[[:space:]]*(source|\.)[[:space:]]+"\$\{INSTALL_DIR\}\/([^"]+)".*/\2/p' "$repo/$f")
  done

  CLOSURE=()
  while IFS= read -r f; do CLOSURE+=("$f"); done < <(printf '%s\n' "${!seen[@]}" | sort)
}

# in_closure <repo-relative path> — membership test against CLOSURE.
in_closure() {
  local x="$1" f
  for f in "${CLOSURE[@]}"; do [[ "$f" == "$x" ]] && return 0; done
  return 1
}

# count_live_defs <fn-name> — echoes "<count> <file(xN) ...>" counting shell
# function DEFINITIONS of <fn-name> across the live closure (uses $REPO).
count_live_defs() {
  local fn="$1" total=0 n f
  local -a where=()
  for f in "${CLOSURE[@]}"; do
    n=$(grep -cE "^[[:space:]]*(function[[:space:]]+)?${fn}[[:space:]]*\(\)" "$REPO/$f" 2>/dev/null || true)
    if (( n > 0 )); then
      total=$((total + n))
      where+=("${f}(x${n})")
    fi
  done
  echo "$total ${where[*]:-}"
}
