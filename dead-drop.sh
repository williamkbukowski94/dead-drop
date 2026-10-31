#!/usr/bin/env bash
# Dead Drop: a small, local GPG symmetric-encryption message vault.
set -o nounset
set -o pipefail

APP_NAME='Dead Drop'
VAULT_DIR="${DEAD_DROP_DIR:-${HOME}/.dead-drop/messages}"

die() {
  printf '%s\n' "$1" >&2
  return 1
}

require_gpg() {
  command -v gpg >/dev/null 2>&1 || die 'GPG is required. Install GnuPG and try again.'
}

secure_temp() {
  local path
  path=$(mktemp "${TMPDIR:-/tmp}/dead-drop.XXXXXXXX") || return 1
  chmod 600 "$path"
  printf '%s' "$path"
}

pause() {
  printf '\nPress Enter to continue...'
  IFS= read -r _ || true
}

list_vault_messages() {
  local -a files=()
  local file
  shopt -s nullglob
  files=("$VAULT_DIR"/*.gpg)
  shopt -u nullglob
  if ((${#files[@]} == 0)); then
    printf 'No messages in %s\n' "$VAULT_DIR"
    return 1
  fi
  for file in "${files[@]}"; do
    printf '  %s\n' "${file##*/}"
  done
}

choose_expiration() {
  local choice
  printf '\nExpiration options:\n  1) 1 hour\n  2) 1 day\n  3) 7 days\n  4) 30 days\n  5) Never\n'
  printf 'Choose [1-5]: '
  IFS= read -r choice || return 1
  case "$choice" in
    1) EXPIRY=$(( $(date +%s) + 3600 )); EXPIRY_LABEL='1 hour' ;;
    2) EXPIRY=$(( $(date +%s) + 86400 )); EXPIRY_LABEL='1 day' ;;
    3) EXPIRY=$(( $(date +%s) + 604800 )); EXPIRY_LABEL='7 days' ;;
    4) EXPIRY=$(( $(date +%s) + 2592000 )); EXPIRY_LABEL='30 days' ;;
    5) EXPIRY=0; EXPIRY_LABEL='never' ;;
    *) printf 'Please choose a number from 1 to 5.\n'; return 1 ;;
  esac
}

create_message() {
  local encrypted_tmp message_tmp filename target line
  require_gpg || return
  mkdir -p "$VAULT_DIR" || { die "Cannot create vault: $VAULT_DIR"; return; }
  chmod 700 "$VAULT_DIR" 2>/dev/null || true

  while ! choose_expiration; do :; done
  encrypted_tmp=$(secure_temp) || { die 'Could not create a secure temporary file.'; return; }
  message_tmp=$(secure_temp) || { rm -f "$encrypted_tmp"; die 'Could not create a secure temporary file.'; return; }
  trap 'rm -f "$encrypted_tmp" "$message_tmp"' RETURN

  printf 'Type or paste your message below. Enter a single line containing .END to finish.\n\n'
  {
    printf 'DEAD-DROP-V1\nEXPIRES=%s\n' "$EXPIRY"
    while IFS= read -r line; do
      [[ "$line" == '.END' ]] && break
      printf '%s\n' "$line"
    done
  } > "$message_tmp"

  filename="message-$(date '+%Y%m%d-%H%M%S').gpg"
  target="$VAULT_DIR/$filename"
  local n=1
  while [[ -e "$target" ]]; do
    target="$VAULT_DIR/message-$(date '+%Y%m%d-%H%M%S')-$n.gpg"
    ((n+=1))
  done
  printf '\nEncrypting with GPG AES-256. GPG will ask you to set a passphrase.\n'
  if ! gpg --no-symkey-cache --cipher-algo AES256 --symmetric --output "$encrypted_tmp" "$message_tmp"; then
    die 'Encryption failed; no message was saved.'
    return
  fi
  chmod 600 "$encrypted_tmp"
  mv "$encrypted_tmp" "$target" || { die 'Could not save the encrypted message.'; return; }
  printf '\nSaved: %s\nExpires: %s\nCopy the .gpg file to share it. The recipient needs this program and your passphrase.\n' "$target" "$EXPIRY_LABEL"
}

open_message() {
  local file decrypted header expiry now
  require_gpg || return
  printf '\nEnter a path to a .gpg file, or a filename in your vault.\n'
  if [[ -d "$VAULT_DIR" ]]; then list_vault_messages || true; fi
  printf 'File: '
  IFS= read -r file || return
  [[ -z "$file" ]] && return
  if [[ -f "$VAULT_DIR/$file" ]]; then file="$VAULT_DIR/$file"; fi
  [[ -f "$file" ]] || { die 'That file does not exist.'; return; }
  decrypted=$(secure_temp) || { die 'Could not create a secure temporary file.'; return; }
  trap 'rm -f "$decrypted"' RETURN
  printf '\nGPG will ask for the message passphrase.\n'
  if ! gpg --no-symkey-cache --decrypt --output "$decrypted" "$file"; then
    die 'Could not decrypt the message.'
    return
  fi
  IFS= read -r header < "$decrypted" || true
  [[ "$header" == 'DEAD-DROP-V1' ]] || { die 'This file is not a supported Dead Drop message.'; return; }
  expiry=$(sed -n '2s/^EXPIRES=//p' "$decrypted")
  [[ "$expiry" =~ ^[0-9]+$ ]] || { die 'The message has invalid expiration metadata.'; return; }
  now=$(date +%s)
  if (( expiry != 0 && now >= expiry )); then
    printf '\nThis message expired on %s and will not be displayed.\n' "$(format_date "$expiry")"
    return
  fi
  printf '\n----- Message -----\n'
  tail -n +3 "$decrypted"
  printf '%s\n' '-------------------'
  if (( expiry == 0 )); then printf 'Expires: never\n'; else printf 'Expires: %s\n' "$(format_date "$expiry")"; fi
}

format_date() {
  if date -d "@$1" '+%Y-%m-%d %H:%M %Z' >/dev/null 2>&1; then
    date -d "@$1" '+%Y-%m-%d %H:%M %Z'
  else
    date -r "$1" '+%Y-%m-%d %H:%M %Z'
  fi
}

delete_message() {
  local file answer
  mkdir -p "$VAULT_DIR" || return
  printf '\nMessages in %s:\n' "$VAULT_DIR"
  list_vault_messages || return
  printf 'Filename to delete: '
  IFS= read -r file || return
  [[ -n "$file" && "$file" != */* && "$file" == *.gpg ]] || { die 'Enter a .gpg filename from the list.'; return; }
  [[ -f "$VAULT_DIR/$file" ]] || { die 'That message was not found.'; return; }
  printf 'Delete %s? [y/N]: ' "$file"
  IFS= read -r answer || return
  case "$answer" in
    y|Y) rm -- "$VAULT_DIR/$file" && printf 'Deleted.\n' ;;
    *) printf 'Cancelled.\n' ;;
  esac
}

main() {
  local choice
  while true; do
    printf '\n%s\n  1) Create a message\n  2) Open a message\n  3) Delete a saved message\n  4) Quit\n' "$APP_NAME"
    printf 'Choose [1-4]: '
    IFS= read -r choice || break
    case "$choice" in
      1) create_message; pause ;;
      2) open_message; pause ;;
      3) delete_message; pause ;;
      4) break ;;
      *) printf 'Please choose a number from 1 to 4.\n' ;;
    esac
  done
}

main "$@"
