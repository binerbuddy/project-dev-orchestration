# shellcheck shell=bash
# gh-pin.sh — pdo_gh_pin, sourced by bin/with-gh-user and bin/lib.sh (pdo_finalize).
#
# pdo_gh_pin <login>: make gh and git over HTTPS in this process (and its children) run as <login>,
# without touching gh's machine-wide active account.
#   - gh: GH_TOKEN is set to the login's token (`gh auth token -u LOGIN`).
#   - git over HTTPS: a credential helper for https://github.com is injected through
#     GIT_CONFIG_COUNT/KEY_<i>/VALUE_<i> (no git config file changes): the github.com helpers are
#     reset, then `gh auth git-credential` answers with GH_TOKEN. The entries are appended after
#     any GIT_CONFIG_* entries already in the environment. When those already set a github.com
#     credential helper (an outer IDENTITY_HOOK wrapper, a bot identity), it adds none and only
#     sets GH_TOKEN, so the outer wrapper's helper chain stays in charge.
#   - PDO_GH_PIN records the login, so a later pin can tell its own token from one a person set.
# Returns 1 (and changes nothing) when gh has no token for the login, 2 on a bad GIT_CONFIG_COUNT.
pdo_gh_pin() {
  local login="$1" tok n i k has_helper=0 helper
  tok="$(gh auth token -u "$login" 2>/dev/null)" && [[ -n "$tok" ]] || return 1
  n="${GIT_CONFIG_COUNT:-0}"
  [[ "$n" =~ ^[0-9]+$ ]] || return 2
  export GH_TOKEN="$tok" PDO_GH_PIN="$login"
  for ((i = 0; i < n; i++)); do
    k="GIT_CONFIG_KEY_$i"
    case "${!k:-}" in
      credential.helper|credential.https://github.com.helper|credential.https://github.com/*.helper) has_helper=1 ;;
    esac
  done
  if [[ $has_helper -eq 0 ]]; then
    printf -v helper '!%q auth git-credential' "$(command -v gh)"
    export "GIT_CONFIG_KEY_$n=credential.https://github.com.helper" "GIT_CONFIG_VALUE_$n="
    export "GIT_CONFIG_KEY_$((n + 1))=credential.https://github.com.helper" "GIT_CONFIG_VALUE_$((n + 1))=$helper"
    export GIT_CONFIG_COUNT=$((n + 2))
  fi
  return 0
}
