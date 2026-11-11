#!/usr/bin/env bash
# Loads the live-server credentials into the calling script's own process. Source it; do not run it.
#
#   source "$(dirname "${BASH_SOURCE[0]}")/hass_creds.sh"; hass_load_creds || exit 2
#
# Exports FENTON_HASS_TOKEN, FENTON_HASS_USERNAME, FENTON_HASS_PASSWORD and FENTON_HASS_SERVER. Nothing is exported into the
# user's shell: the credentials exist only in the process that sources this file and its children.
#
# - A value already in the environment wins.
# - Otherwise the four keys are read from ${FENTON_HASS_CREDS_FILE:-$HOME/.config/fenton-hass/env}.
# - The file must be owned by you, not readable by group or others (mode 600), in a folder that is not group- or
#   world-writable, and outside any repository.
# - Only those four keys are read, as `KEY=value` or `export KEY=value`, optionally quoted. The file is never sourced or
#   evaluated, so a line such as `FENTON_HASS_PASSWORD=$(cmd)` is just a value and nothing runs.
# - A value is never printed. Messages name the key or the path, never the value.
#
# Returns 0 on success (including "no file and nothing to load"), 1 when the file is refused.

_HASS_CRED_KEYS="FENTON_HASS_TOKEN FENTON_HASS_USERNAME FENTON_HASS_PASSWORD FENTON_HASS_SERVER"
_HASS_CREDS_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

# Prints the owner uid and the octal mode of a file (macOS and Linux stat differ).
_hass_stat() {
  if stat -f '%u %Lp' "$1" 2>/dev/null; then return 0; fi
  stat -c '%u %a' "$1"
}

# True when the real path of $1 is under this repository or inside any git work tree.
_hass_in_repo() {
  local dir real
  dir="$(cd "$(dirname "$1")" 2>/dev/null && pwd -P)" || return 1
  real="$dir/$(basename "$1")"
  case "$real" in "$_HASS_CREDS_REPO"/*) return 0 ;; esac
  git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

_hass_load_creds() {
  local _k _missing="" _file _st _uid _mode _line _key _val _first _last
  for _k in $_HASS_CRED_KEYS; do
    [[ -n "${!_k:-}" ]] || _missing="$_missing $_k"
  done
  [[ -n "$_missing" ]] || return 0
  _file="${FENTON_HASS_CREDS_FILE:-$HOME/.config/fenton-hass/env}"
  [[ -e "$_file" ]] || return 0
  if [[ ! -f "$_file" ]]; then echo "hass_creds: $_file is not a regular file; refusing it" >&2; return 1; fi
  _st="$(_hass_stat "$_file")" || { echo "hass_creds: cannot stat $_file" >&2; return 1; }
  _uid="${_st%% *}"; _mode="${_st##* }"
  if [[ "$_uid" != "$(id -u)" ]]; then echo "hass_creds: $_file is not owned by you; refusing it" >&2; return 1; fi
  if (( (8#$_mode & 8#077) != 0 )); then
    echo "hass_creds: $_file is mode $_mode; refusing it (chmod 600 it)" >&2; return 1
  fi
  _st="$(_hass_stat "$(dirname "$_file")")" || { echo "hass_creds: cannot stat the folder of $_file" >&2; return 1; }
  _mode="${_st##* }"
  if (( (8#$_mode & 8#022) != 0 )); then
    echo "hass_creds: the folder of $_file is mode $_mode (group- or world-writable); refusing it" >&2; return 1
  fi
  if _hass_in_repo "$_file"; then
    echo "hass_creds: $_file is inside a git repository; refusing it (keep it at ~/.config/fenton-hass/env)" >&2; return 1
  fi
  while IFS= read -r _line || [[ -n "$_line" ]]; do
    _line="${_line#"${_line%%[![:space:]]*}"}"
    if [[ "$_line" == export[[:space:]]* ]]; then _line="${_line#export}"; _line="${_line#"${_line%%[![:space:]]*}"}"; fi
    [[ "$_line" == *=* ]] || continue
    _key="${_line%%=*}"
    case " $_HASS_CRED_KEYS " in *" $_key "*) ;; *) continue ;; esac
    [[ -z "${!_key:-}" ]] || continue  # the environment wins
    _val="${_line#*=}"
    _val="${_val%"${_val##*[![:space:]]}"}"
    if (( ${#_val} >= 2 )); then
      _first="${_val:0:1}"; _last="${_val: -1}"
      if [[ "$_first" == "$_last" && ( "$_first" == '"' || "$_first" == "'" ) ]]; then _val="${_val:1:${#_val}-2}"; fi
    fi
    if [[ -n "$_val" ]]; then export "$_key=$_val"; fi
  done < "$_file"
  return 0
}

# Loads the credentials. xtrace is switched off for the whole load (and restored on every path) so `bash -x` never traces a value.
hass_load_creds() {
  local _xtrace=0 _rc
  case "$-" in *x*) _xtrace=1; set +x ;; esac
  _hass_load_creds; _rc=$?
  if [[ $_xtrace == 1 ]]; then set -x; fi
  return $_rc
}

# Fails with a clear message unless a token or a password is set and FENTON_HASS_SERVER is set (a live run cannot sign in
# without a credential, and no server is compiled into the app, so a token launch without a server stays on the sign-in form).
hass_require_creds() {
  local _xtrace=0 _rc=0
  case "$-" in *x*) _xtrace=1; set +x ;; esac
  _hass_require_creds || _rc=$?
  if [[ $_xtrace == 1 ]]; then set -x; fi
  return $_rc
}
_hass_require_creds() {
  local _file="${FENTON_HASS_CREDS_FILE:-$HOME/.config/fenton-hass/env}"
  if [[ -z "${FENTON_HASS_TOKEN:-}" && -z "${FENTON_HASS_PASSWORD:-}" ]]; then
    echo "hass_creds: neither FENTON_HASS_TOKEN nor FENTON_HASS_PASSWORD is set (looked in the environment and $_file)" >&2
    return 1
  fi
  if [[ -z "${FENTON_HASS_SERVER:-}" ]]; then
    echo "hass_creds: FENTON_HASS_SERVER is not set (looked in the environment and $_file); add it to that file, see .agents/testing/apple/devices.md" >&2
    return 1
  fi
  return 0
}

# Prints which keys are set, yes or no, never a value.
hass_creds_status() {
  local _k
  for _k in $_HASS_CRED_KEYS; do
    if [[ -n "${!_k:-}" ]]; then echo "$_k: yes"; else echo "$_k: no"; fi
  done
}

# For the `--env` option of the live-server scripts: only `shell` is accepted, and it loads the credentials in-process.
hass_use_env_arg() {
  if [[ "${1:-}" != shell ]]; then
    echo "--env takes only 'shell' now: credentials load in-process from ~/.config/fenton-hass/env (tools/hass_creds.sh); a file is no longer sourced" >&2
    return 2
  fi
  hass_load_creds
}
