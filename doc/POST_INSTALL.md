# openGym (openGym)

## Post-install notes

openGym is available at `https://__DOMAIN____PATH__` — gated behind YunoHost's SSO,
so only users of your portal can reach the page. Accounts themselves are managed
**inside openGym** (it has its own passkey/password login; it does not use LDAP
and upstream deliberately rejects proxy-header identity — see docs/SELF_HOSTING.md).
Practically: you sign in to the portal, then create your openGym profile once.

The first account created becomes the **admin** (`FIRST_USER_ADMIN=1` is set).
Open the app, register, and register a passkey (Face ID / fingerprint) if your
browser/device supports it — that is the intended daily login.

To limit who may sign up: Settings → Admin → enable invite-only codes. The URL
being SSO-gated already restricts it to portal users.

### Exercise media

Nothing to fetch: the 6,554 exercise stills (.webp) and 6,554 animation clips
(.mp4) ship inside the pinned upstream source tarball (`catalogue/media/`,
~260 MB) and are served read-only by nginx at `__PATH__/exercise-media/`.
Upgrades refresh them with the source. They remain © the dataset authors —
see the app's NOTICE.md.

### Backup

`yunohost backup create --apps __APP__` covers everything user-specific:
accounts, sessions, uploads and the session secret live in the app's data dir.
The media and the frontend build are deliberately *not* archived — restore
re-extracts them from the pinned source tarball.
