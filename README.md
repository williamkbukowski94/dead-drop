# Dead Drop

Dead Drop is a small Bash terminal application for creating password-protected message files with GPG. Messages use GPG symmetric encryption with AES-256. The encrypted `.gpg` file can be copied or shared; the recipient needs GPG, this script, and the passphrase.

## Requirements

- Bash
- GnuPG (`gpg`)
- `date`, `mktemp`, `sed`, and other standard Unix utilities

## Run

```bash
chmod +x dead-drop.sh
./dead-drop.sh
```

## Install as `dropdead`

Install the latest public version for the current user with:

```bash
curl -fsSL https://raw.githubusercontent.com/williamkbukowski94/dead-drop/main/dead-setup | bash
```

This installs `dropdead` and the `dead-setup` updater into `~/.local/bin`. Add that directory to your `PATH` if it is not already there. Then start the app with:

```bash
dropdead
```

Update the installed program with `dead-setup update`, or remove the commands with `dead-setup uninstall`. This is a per-user install and does not require `sudo`. You can also run `./dead-setup` from a local checkout to install that checkout's version.

The menu lets you create, open, and delete saved messages. New messages are stored in `~/.dead-drop/messages` with owner-only directory permissions. Set `DEAD_DROP_DIR` to use a different local vault location. To open a message shared by someone else, choose **Open a message** and enter its file path.

The terminal interface uses a consistent neon-green frame, clears the screen when moving between menu choices, and displays a small `bkw` mark beneath each panel. When creating a message, choose its expiration and a filename; if that name already exists, Dead Drop adds a number to avoid overwriting it. The **Open a message** menu can search `.gpg` filenames across mounted filesystem locations, list all `.gpg` files it can find, or open a path directly. Results show full paths and are selected by number. The search skips virtual system folders such as `/proc`, `/sys`, `/dev`, and `/run`, and inaccessible folders are silently skipped.

When creating a message, select an expiration period, type or paste the text, then enter `.END` on its own line. GPG prompts you to set the passphrase. Keep that passphrase separate from the encrypted file when sharing.

## Expiration limitation

Expiration is checked by Dead Drop after decryption and before displaying the message. It is not cryptographically enforced: anyone with the encrypted file and passphrase can decrypt it directly with GPG, bypassing the expiration check. Deleting a local file also cannot remove copies that were already shared.
