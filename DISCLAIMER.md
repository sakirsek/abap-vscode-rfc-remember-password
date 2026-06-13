# Disclaimer

Please read this before using the patcher.

## What this is

This project modifies your locally installed copy of SAP's official "ABAP
Development Tools for VS Code" extension to add optional persistence of the RFC
logon password. It is an independent, community project. It is not produced,
endorsed, reviewed, or supported by SAP. Nothing here is "approved" or
"certified" by SAP, and nothing here is a statement about what is or is not
permitted under your agreements with SAP. You are responsible for deciding
whether using it is appropriate in your environment.

## The security trade-off

The official extension deliberately does not remember the RFC password: it
re-prompts on every logon. That is a security decision by SAP. This patcher
re-enables persistence as an opt-in convenience, which moves that decision, and
its consequences, to you.

When you choose "Yes" to remember a password:

- It is stored through VS Code SecretStorage, which uses the operating system
  keychain (Windows Credential Manager, macOS Keychain, or libsecret on Linux).
- It is never written to a file in the repository or the workspace, and never
  stored in plain text by this project.
- Anyone who can unlock your OS user session and your keychain can potentially
  read secrets stored there, exactly as with other credentials your machine
  remembers. On a shared or poorly secured machine, do not enable persistence.

Persistence is opt-in and defaults to off: nothing is saved unless you explicitly
answer "Yes" after a successful logon. You can remove a saved password at any
time with the "ABAP: Forget Saved RFC Password" command, or remove all of them by
reinstalling the extension.

## No warranty

This software is provided "as is", without warranty of any kind, express or
implied. See [LICENSE](LICENSE) (MIT). The authors are not liable for any damage,
data loss, security incident, or other consequence arising from its use. By
running the patcher you accept full responsibility for the result.

## Brittleness by nature

The patch edits an internal, minified bundle that SAP rebuilds on every release.
A future extension update can change those internals so the patch no longer
applies. The patcher is built to stop safely and change nothing in that case,
but you should re-verify behavior after any extension update.

## Your data and systems

Use this only against systems you are authorized to access, and follow your
organization's security policy. If in doubt, do not enable password persistence.
