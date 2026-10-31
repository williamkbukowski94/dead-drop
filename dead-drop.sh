#!/usr/bin/env bash
# Dead Drop: a local GPG symmetric-encryption message vault.
set -o nounset
set -o pipefail

APP_NAME='Dead Drop'
VAULT_DIR="${DEAD_DROP_DIR:-${HOME}/.dead-drop/messages}"
BOX_INNER=70
NEON=$'\033[38;5;42m'
TEXT=$'\033[38;5;114m'
RESET=$'\033[0m'
WHITE=$'\033[97m'
TEMP_FILES=()
FOUND_PATHS=()

cleanup() {
  ((${#TEMP_FILES[@]} == 0)) || rm -f -- "${TEMP_FILES[@]}"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

die() {
  printf '%s\n' "$1" >&2
  return 1
}

clear_screen() {
  if [[ -t 1 ]] && command -v clear >/dev/null 2>&1; then
    clear
  else
    printf '\033[2J\033[H'
  fi
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

box_open() {
  local title=$1 rule
  printf -v rule '%*s' "$((BOX_INNER + 2))" ''
  rule=${rule// /─}
  printf '%s┌%s┐%s\n' "$NEON" "$rule" "$RESET"
  box_line "$APP_NAME"
  box_line "$title"
  box_line ''
}

box_line() {
  local text=$1 clipped padded
  clipped=${text:0:$BOX_INNER}
  printf -v padded '%-*s' "$BOX_INNER" "$clipped"
  printf '%s│%s %s %s│%s\n' "$NEON" "$RESET" "$TEXT$padded$RESET" "$NEON" "$RESET"
}

box_wrap() {
  local text=$1 part
  while IFS= read -r part; do
    box_line "$part"
  done < <(printf '%s\n' "$text" | fold -w "$BOX_INNER")
}

box_close() {
  local rule
  printf -v rule '%*s' "$((BOX_INNER + 2))" ''
  rule=${rule// /─}
  printf '%s└%s┘%s\n' "$NEON" "$rule" "$RESET"
  printf '%*s%s bkw%s\n\n' "$((BOX_INNER - 1))" '' "$WHITE" "$RESET"
}

draw_main_menu() {
  clear_screen
  box_open 'Main menu'
  box_line '1) Create a message'
  box_line '2) Open a message'
  box_line '3) Delete a saved message'
  box_line '4) Quit'
  box_close
  printf '%sChoose [1-4]: %s' "$TEXT" "$RESET"
}

draw_expiration_menu() {
  clear_screen
  box_open 'Create a message — expiration'
  box_line 'Choose how long the message should remain readable:'
  box_line '1) 1 hour'
  box_line '2) 1 day'
  box_line '3) 7 days'
  box_line '4) 30 days'
  box_line '5) Never'
  box_line '6) Back to main menu'
  box_close
  printf '%sChoose [1-6]: %s' "$TEXT" "$RESET"
}

draw_open_menu() {
  clear_screen
  box_open 'Open a message'
  box_line 'Search encrypted message files across the filesystem.'
  box_line '1) Search by filename'
  box_line '2) List all .gpg files on the filesystem'
  box_line '3) Enter a full file path'
  box_line '4) Back to main menu'
  box_close
  printf '%sChoose [1-4]: %s' "$TEXT" "$RESET"
}

draw_delete_menu() {
  clear_screen
  box_open 'Delete a saved message'
  box_line 'Select one of the messages in the local Dead Drop vault.'
  box_line '1) Show saved messages'
  box_line '2) Back to main menu'
  box_close
  printf '%sChoose [1-2]: %s' "$TEXT" "$RESET"
}

pause() {
  printf '\n%sPress Enter to continue...%s' "$TEXT" "$RESET"
  IFS= read -r _ || true
}

create_message() {
  local choice line expiry expiry_label message_name target encrypted_tmp message_tmp name_pattern
  name_pattern='^[A-Za-z0-9][A-Za-z0-9._ -]{0,79}$'
  require_gpg || { pause; return; }
  while true; do
    draw_expiration_menu
    IFS= read -r choice || return
    case "$choice" in
      1) expiry=$(( $(date +%s) + 3600 )); expiry_label='1 hour'; break ;;
      2) expiry=$(( $(date +%s) + 86400 )); expiry_label='1 day'; break ;;
      3) expiry=$(( $(date +%s) + 604800 )); expiry_label='7 days'; break ;;
      4) expiry=$(( $(date +%s) + 2592000 )); expiry_label='30 days'; break ;;
      5) expiry=0; expiry_label='never'; break ;;
      6) clear_screen; return ;;
      *) clear_screen ;;
    esac
  done

  mkdir -p "$VAULT_DIR" || { die "Cannot create vault: $VAULT_DIR"; pause; return; }
  chmod 700 "$VAULT_DIR" 2>/dev/null || true
  while true; do
    clear_screen
    box_open 'Create a message — name'
    box_line "Expiration: $expiry_label"
    box_line 'Choose an easy-to-type filename (without the .gpg extension).'
    box_line 'Use letters, numbers, spaces, dots, dashes, or underscores.'
    box_line 'Names must start with a letter or number and be 1–80 characters.'
    box_close
    printf '%sMessage name: %s' "$TEXT" "$RESET"
    IFS= read -r message_name || return
    if [[ "$message_name" =~ $name_pattern ]]; then
      break
    fi
    printf '\n%sThat name is not valid. Try another name.%s\n' "$TEXT" "$RESET"
    pause
  done

  target="$VAULT_DIR/$message_name.gpg"
  local suffix=2
  while [[ -e "$target" ]]; do
    target="$VAULT_DIR/$message_name-$suffix.gpg"
    ((suffix+=1))
  done

  message_tmp=$(secure_temp) || { die 'Could not create a secure temporary file.'; pause; return; }
  encrypted_tmp=$(secure_temp) || { rm -f "$message_tmp"; die 'Could not create a secure temporary file.'; pause; return; }
  TEMP_FILES+=("$message_tmp" "$encrypted_tmp")
  clear_screen
  box_open 'Create a message — text'
  box_line "Name: ${target##*/}"
  box_line "Expiration: $expiry_label"
  box_line 'Type or paste your message below.'
  box_line 'Finish by entering .END on a line by itself.'
  box_close
  printf '%sMessage text follows. Enter .END to finish.%s\n\n' "$TEXT" "$RESET"
  {
    printf 'DEAD-DROP-V1\nEXPIRES=%s\n' "$expiry"
    while IFS= read -r line; do
      [[ "$line" == '.END' ]] && break
      printf '%s\n' "$line"
    done
  } > "$message_tmp"

  printf '\n%sEncrypting with GPG AES-256. GPG will ask for a passphrase.%s\n' "$TEXT" "$RESET"
  if ! gpg --no-symkey-cache --cipher-algo AES256 --symmetric --output "$encrypted_tmp" "$message_tmp"; then
    rm -f "$message_tmp" "$encrypted_tmp"
    die 'Encryption failed; no message was saved.'
    pause
    return
  fi
  chmod 600 "$encrypted_tmp"
  if ! mv "$encrypted_tmp" "$target"; then
    rm -f "$message_tmp" "$encrypted_tmp"
    die 'Could not save the encrypted message.'
    pause
    return
  fi
  rm -f "$message_tmp"
  clear_screen
  box_open 'Message created'
  box_line "Saved as: ${target##*/}"
  box_line "Expiration: $expiry_label"
  box_wrap "Full path: $target"
  box_line 'Copy the .gpg file to share it.'
  box_close
  pause
}

collect_gpg_files() {
  local pattern=$1 path
  FOUND_PATHS=()
  while IFS= read -r path; do
    FOUND_PATHS+=("$path")
  done < <(
    find / \( -path /proc -o -path /sys -o -path /dev -o -path /run \) -prune -o \
      -type f -iname "$pattern" -print 2>/dev/null | LC_ALL=C sort -f
  )
}

select_from_paths() {
  local title=$1 selected_number selection path i
  shift
  local -a paths=("$@")
  if ((${#paths[@]} == 0)); then
    clear_screen
    box_open "$title"
    box_line 'No matching .gpg files were found.'
    box_line 'Protected system folders may not be searchable.'
    box_close
    pause
    return 1
  fi
  clear_screen
  box_open "$title"
  box_line 'Choose a file by number; full paths are shown.'
  for i in "${!paths[@]}"; do
    box_wrap "$((i + 1))) ${paths[$i]}"
  done
  box_line ''
  box_line '0) Back'
  box_close
  printf '%sFile number: %s' "$TEXT" "$RESET"
  IFS= read -r selected_number || return 1
  if [[ "$selected_number" == '0' ]]; then
    clear_screen
    return 1
  fi
  if [[ "$selected_number" =~ ^[0-9]+$ ]] && ((selected_number >= 1 && selected_number <= ${#paths[@]})); then
    selection=${paths[$((selected_number - 1))]}
    open_message_file "$selection"
    return
  fi
  printf '\n%sThat is not a number in the list.%s\n' "$TEXT" "$RESET"
  pause
  return 1
}

search_filesystem() {
  local query pattern
  clear_screen
  box_open 'Search the filesystem'
  box_line 'Search by part of a message filename.'
  box_line 'The search looks for .gpg files under /.'
  box_close
  printf '%sFilename contains: %s' "$TEXT" "$RESET"
  IFS= read -r query || return
  [[ -n "$query" ]] || { clear_screen; return; }
  query=${query%.gpg}
  pattern="*${query}*.gpg"
  clear_screen
  box_open 'Searching the filesystem'
  box_line "Filename pattern: $pattern"
  box_line 'Scanning mounted filesystem locations...'
  box_close
  collect_gpg_files "$pattern"
  select_from_paths 'Search results' "${FOUND_PATHS[@]}"
}

list_filesystem_messages() {
  clear_screen
  box_open 'All .gpg files'
  box_line 'Scanning the filesystem for encrypted message files...'
  box_close
  collect_gpg_files '*.gpg'
  select_from_paths 'Filesystem message files' "${FOUND_PATHS[@]}"
}

open_path_prompt() {
  local file
  clear_screen
  box_open 'Open a message by path'
  box_line 'Enter the full path to a .gpg message file.'
  box_line 'You can also use a path relative to the current directory.'
  box_close
  printf '%sFile path: %s' "$TEXT" "$RESET"
  IFS= read -r file || return
  [[ -f "$file" ]] || { printf '\n%sThat file does not exist.%s\n' "$TEXT" "$RESET"; pause; return; }
  open_message_file "$file"
}

open_message_file() {
  local file=$1 decrypted header expiry now passphrase=''
  local message_line
  if ! require_gpg; then pause; return; fi
  decrypted=$(secure_temp) || { die 'Could not create a secure temporary file.'; pause; return; }
  TEMP_FILES+=("$decrypted")
  clear_screen
  box_open 'Open a message'
  box_wrap "File: $file"
  box_line 'Enter the message passphrase below.'
  box_line 'Your typing will be hidden.'
  box_close
  printf '%sMessage passphrase: %s' "$TEXT" "$RESET"
  if ! IFS= read -r -s passphrase; then
    printf '\n'
    unset passphrase
    return
  fi
  printf '\n'
  if ! gpg --batch --pinentry-mode loopback --passphrase-fd 3 --no-symkey-cache \
      --decrypt --output "$decrypted" "$file" 3<<<"$passphrase"; then
    unset passphrase
    clear_screen
    box_open 'Could not open message'
    box_line 'The file could not be decrypted with that passphrase.'
    box_line 'Confirm that it is a Dead Drop message and try again.'
    box_close
    pause
    return
  fi
  unset passphrase
  IFS= read -r header < "$decrypted" || true
  if [[ "$header" != 'DEAD-DROP-V1' ]]; then
    clear_screen
    box_open 'Unsupported file'
    box_line 'This encrypted file is not a Dead Drop message.'
    box_close
    pause
    return
  fi
  expiry=$(sed -n '2s/^EXPIRES=//p' "$decrypted")
  if [[ ! "$expiry" =~ ^[0-9]+$ ]]; then
    clear_screen
    box_open 'Invalid message'
    box_line 'The message has invalid expiration metadata.'
    box_close
    pause
    return
  fi
  now=$(date +%s)
  if (( expiry != 0 && now >= expiry )); then
    clear_screen
    box_open 'Message expired'
    box_line "Expired: $(format_date "$expiry")"
    box_line 'The message will not be displayed.'
    box_close
    pause
    return
  fi
  clear_screen
  box_open 'Message contents'
  box_wrap "File: $file"
  while IFS= read -r message_line || [[ -n "$message_line" ]]; do
    box_wrap "$message_line"
  done < <(tail -n +3 "$decrypted")
  if (( expiry == 0 )); then box_line 'Expires: never'; else box_wrap "Expires: $(format_date "$expiry")"; fi
  box_close
  pause
}

format_date() {
  if date -d "@$1" '+%Y-%m-%d %H:%M %Z' >/dev/null 2>&1; then
    date -d "@$1" '+%Y-%m-%d %H:%M %Z'
  else
    date -r "$1" '+%Y-%m-%d %H:%M %Z'
  fi
}

open_menu() {
  local choice
  while true; do
    draw_open_menu
    IFS= read -r choice || return
    clear_screen
    case "$choice" in
      1) search_filesystem ;;
      2) list_filesystem_messages ;;
      3) open_path_prompt ;;
      4) return ;;
      *) printf '%sChoose a number from 1 to 4.%s\n' "$TEXT" "$RESET"; pause ;;
    esac
  done
}

delete_menu() {
  local choice index answer target
  local -a files=()
  mkdir -p "$VAULT_DIR" || { die "Cannot access vault: $VAULT_DIR"; pause; return; }
  while true; do
    draw_delete_menu
    IFS= read -r choice || return
    clear_screen
    case "$choice" in
      1)
        shopt -s nullglob
        files=("$VAULT_DIR"/*.gpg)
        shopt -u nullglob
        if ((${#files[@]} == 0)); then
          box_open 'Delete a saved message'
          box_line 'The local vault has no saved messages.'
          box_close
          pause
          continue
        fi
        box_open 'Delete a saved message'
        for index in "${!files[@]}"; do
          box_wrap "$((index + 1))) ${files[$index]##*/}"
        done
        box_line '0) Back'
        box_close
        printf '%sMessage number: %s' "$TEXT" "$RESET"
        IFS= read -r index || return
        if [[ "$index" == '0' ]]; then continue; fi
        if [[ ! "$index" =~ ^[0-9]+$ ]] || ((index < 1 || index > ${#files[@]})); then
          printf '\n%sThat is not a number in the list.%s\n' "$TEXT" "$RESET"
          pause
          continue
        fi
        target=${files[$((index - 1))]}
        printf '%sDelete %s? [y/N]: %s' "$TEXT" "${target##*/}" "$RESET"
        IFS= read -r answer || return
        case "$answer" in
          y|Y) rm -- "$target" && printf '\n%sDeleted.%s\n' "$TEXT" "$RESET" ;;
          *) printf '\n%sCancelled.%s\n' "$TEXT" "$RESET" ;;
        esac
        pause
        ;;
      2) return ;;
      *) printf '%sChoose 1 or 2.%s\n' "$TEXT" "$RESET"; pause ;;
    esac
  done
}

quit_menu() {
  local choice
  clear_screen
  box_open 'Quit Dead Drop'
  box_line '1) Quit the program'
  box_line '2) Return to the main menu'
  box_close
  printf '%sChoose [1-2]: %s' "$TEXT" "$RESET"
  IFS= read -r choice || return 1
  [[ "$choice" == '1' ]]
}

main() {
  local choice
  mkdir -p "$VAULT_DIR" 2>/dev/null || true
  while true; do
    draw_main_menu
    IFS= read -r choice || break
    clear_screen
    case "$choice" in
      1) create_message ;;
      2) open_menu ;;
      3) delete_menu ;;
      4) if quit_menu; then clear_screen; return; fi ;;
      *) printf '%sChoose a number from 1 to 4.%s\n' "$TEXT" "$RESET"; pause ;;
    esac
  done
}

main "$@"
