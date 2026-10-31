Accounts and passkeys live inside openGym (no LDAP/SSO identity). The portal
permission decides who reaches the page — keep `visitors` off unless you want
anonymous sign-up. Data folder: app data dir, plain files.

## Notable settings

- **Exercise media** — the 6,554 stills + 6,554 animation clips ship inside the
  pinned upstream source tarball (`catalogue/media/`, ~260 MB) and are served
  read-only by nginx at `<path>/exercise-media/`; nothing is fetched at
  install. They are (c) the dataset authors and used under the dataset's
  terms, not the app's AGPL (see the app's NOTICE.md).
- **Accounts** — the first account registered in the app becomes admin
  (`FIRST_USER_ADMIN=1`). The YunoHost permission on the URL (default:
  `all_users`) is a reachability gate, not the app identity; signup can be
  locked to invite codes inside openGym's admin settings.

## Updates

Updates bump `version` + `sources.main` (URL and sha256) together. Backups use
the standard YunoHost app backup: users, uploads, session secret and VAPID
keys are all plain files under the app data dir.

## Portal SSO walk-in login (config panel toggle, off by default)

App config panel → *Portal SSO walk-in login* → enable. Portal-authenticated
users visiting `https://<domain>/ynh-sso-login` land straight inside their
openGym profile; with "auto provision" on, the profile is created on first
visit through the app's own invite/register API (portal user → profile link
kept in /etc/opengym/sso/). Enabling the feature also switches the app's
`PASSWORD_LOGIN` on (upstream default is off); provisioned users share the
panel's "initial password" for the app's settings-proof step, so share it
with them once and have them add their own passkey afterwards. Profiles that
already exist (registered through the app's own login before the toggle was
on) are adopted by exact name match on first walk-in.

Security shape: the mint route answers only when SSOwat injected BOTH the
`YNH_USER` identity and the Basic-Auth proof for that exact URI (a dedicated
auth_header-enabled permission covering only /ynh-sso-login; the main
permission stays auth_header=false, so the SPA's Bearer calls are never
touched). The glue is package-side only (one nginx location, a lua file and
a small ACL watchdog unit under the app's names) — openGym's code is never
patched, so upstream upgrades cannot conflict with it. The app rewrites its
data files at mode 0600 on every save; a systemd path unit re-opens the ACL
mask the mint route needs right after each write. If a future upstream
release changes the session cookie format, the walk-in route starts failing
while passkey login keeps working; then check for a package update.

Remember: the FIRST account created — by walk-in or by hand — claims the
instance admin (`FIRST_USER_ADMIN`). To hand admin to a specific portal user,
have them register through the app's own login first; anyone who walks in
before that becomes the owner.

## Known limitations

- openGym has no LDAP mode; it never accepts proxy-header identity itself
  (upstream design). The portal SSO walk-in above works around this with a
  package-side mint route — inside the app, accounts and passkeys stay the
  app's own; portal login + one-time app login remains the fallback UX.
