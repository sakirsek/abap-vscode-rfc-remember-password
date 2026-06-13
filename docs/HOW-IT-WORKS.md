# How it works

This patcher adds optional RFC password persistence around the official
extension's native logon. It does not perform the logon and it does not change
the native password prompt. It wraps the existing flow with four small,
auditable edits to `extension.js` plus one command registration in
`package.json`, all listed exactly in
[../patch/payloads.json](../patch/payloads.json).

## 1. The native flow (1.0.1+)

When you log on to an RFC destination, the official extension asks its bundled
language server to log on. The server, when it needs a password, asks the
extension to collect input. The extension shows a masked password box and sends
the entered password to the server over a short-lived local loopback socket. The
server then attempts the logon and reports a state back: `connected`,
`disconnected`, `pending`, or `cancelled`.

The password lives only in memory and is delivered once. There is no keychain,
no save, and no "forget". This project adds exactly those, without touching the
prompt.

## 2. Where we hook in

```
  you trigger a logon
          |
          v
  [native] ask the language server to log on
          |
          v
  [native] server asks the extension for the password
          |
          v
  promptLogonInput(e)                         <-- our edits 2 and 3
     |  saved password for e.id exists?
     |        yes ----> send it over the native socket, mark "used saved",
     |                  return without prompting              (edit 2)
     |        no  ----> native prompt runs unchanged;
     |                  we stash what you typed, pending success (edit 3)
          |
          v
  [native] server attempts the logon, reports the state
          |
          v
  handleLogonStateChanged(e)                  <-- our edit 4
     |  connected   ----> if a typed password is pending and none is saved,
     |                    ask "Remember?" and on Yes store it
     |  disconnected ----> drop the pending password; if we had just used a
     |                    saved one, delete it (self-heal)
```

Edit 1 runs once at activation and sets up the shared state plus the Forget
command. The native logic in both hooked functions still runs in full; our code
is added at the start and never removes or rewrites the original statements.

## 3. The shared state

At extension activation we create one small object on the JavaScript global
scope. It holds:

- a handle to VS Code SecretStorage (the OS keychain),
- a `pending` map: a password you just typed, held until we know the logon
  succeeded,
- a `usedSaved` set: destinations where we just auto-supplied a saved password,
  so we can self-heal if it turns out to be wrong,
- helper functions to get, save, and delete a secret, and to maintain a small
  index of which destinations have a saved password.

### Keychain key scheme

SecretStorage is a flat key/value store with no "list keys" API, so we keep our
own tiny index:

| Key | Value |
|---|---|
| `adt-rfc-ids` | a JSON array of the destination ids that have a saved password |
| `adt-rfc-pwd::<destinationId>` | the saved password for that destination |

The password value is the only sensitive data stored, and only in the OS
keychain. The index holds destination ids only, never a password.

## 4. The four edits

Each anchor below must occur exactly once or the patcher stops and changes
nothing. The full find/replace text is in
[../patch/payloads.json](../patch/payloads.json).

1. **Activation hook.** At the extension's `activate` entry we set up the shared
   state above and register the command `adt-vscode.forgetRfcPassword`. This
   command id is also the "already patched" marker: if it is present, the
   patcher refuses to run again.

2. **Prompt hook (auto-use).** At the start of the function that collects logon
   input, if a password is already saved for this destination we send it over
   the same loopback socket the extension already uses, mark the destination in
   `usedSaved`, and return without showing the prompt. If nothing is saved, the
   native prompt runs unchanged.

3. **Prompt hook (stash).** When you do type a password, we keep it in the
   `pending` map keyed by the destination id, and clear any `usedSaved` mark for
   it. Nothing is saved yet, because we do not know whether the password is
   correct.

4. **Logon-state hook.** When the server reports the result:
   - **connected** and a typed password is pending and nothing is saved yet: ask
     once whether to remember it, and on "Yes" store it in the keychain and add
     the destination to the index. Then clear the pending entry.
   - **disconnected**: drop any pending typed password (a failed password is
     never offered for saving) and, if we had just auto-supplied a saved
     password, delete that saved password (self-heal) so you are prompted again
     next time.

The ask and the keychain writes run without blocking the native flow, so logon
timing and behavior are unchanged.

## 5. The Forget command

`adt-vscode.forgetRfcPassword` reads the index of saved destinations, shows a
picker, and deletes the chosen destination's secret and index entry. It is
declared in the extension's `package.json` so it appears in the Command Palette
as **ABAP: Forget Saved RFC Password**.

## 6. Edge cases and why they are safe

- **A typed password that fails is never saved.** We only offer to save on a
  `connected` state, and only for a password that was just typed.
- **A transient disconnect does not delete a good saved password.** We delete a
  saved password only if it was the one we just auto-supplied (the `usedSaved`
  mark, which is one-shot and cleared on the next `connected`). A disconnect that
  was not preceded by an auto-supplied saved password deletes nothing.
- **Saying "No" simply does not save.** You may be asked again on a later fresh
  logon. Once you say "Yes", the saved password is auto-used and you are not
  asked again.
- **One logon at a time.** The flow assumes a user logs on to one destination at
  a time, which matches normal use. The keying is per destination id throughout.
- **Identity.** Each edit keys off the destination id that the extension already
  attaches to the logon request (`e.id`) and to the logon-state report
  (`e.destinationId`); these are the same id, which is what makes auto-use, save,
  and self-heal line up.

## 7. Safety properties

- **Exactly-once anchors.** Every edit location is verified to occur exactly
  once before anything is written. A mismatch (for example after an extension
  update changed the internals) makes the patcher stop and write nothing.
- **Guard.** The presence of `adt-vscode.forgetRfcPassword` means "already
  patched"; a second run is a no-op.
- **No backups, no revert.** Undo is reinstalling or updating the extension.
- **Success-gated save.** A password is only ever saved after a logon actually
  succeeds, and only if you say "Yes". A wrong password is never saved.
- **Wrapped, not rewritten.** Our code is added at the start of two functions
  and in a comment-free, try/guarded form; the original native statements are
  preserved verbatim. Every change is wrapped so that an unexpected error in our
  code cannot break the native logon.
- **Local only.** All storage is in the OS keychain on your machine.

## 8. What this patch does not do

- It does not perform the logon. The official extension does that.
- It does not change the native password prompt or any other UI, apart from the
  single "Remember?" question after a successful logon and the Forget command.
- It does not touch the extension's Java jar, decompile anything, or need a JDK.
- It does not send your password anywhere. Storage is the local OS keychain.

## 9. Limitations

- **Classic RFC logon only.** This targets the username/password RFC logon flow.
  Browser-based logon for HTTP/cloud (for example BTP ABAP environment) is a
  different path and is not affected.
- **Brittle by nature.** The patch edits an internal, minified bundle that SAP
  rebuilds on every release. A future version can change the internals so the
  patch no longer applies; the patcher then stops safely and changes nothing.
- **Keychain must be available.** On Linux, SecretStorage needs a working secret
  service (libsecret with a keyring such as GNOME Keyring) that is unlocked.
  Without it, VS Code cannot store secrets and nothing is saved.
