Accounts and passkeys live inside openGym (no LDAP/SSO identity). The portal
permission decides who reaches the page — keep `visitors` off unless you want
anonymous sign-up. Data folder: app data dir, plain files.

## Notable settings

- **Exercise media** — the installer can fetch the ~350 MB exercise
  photo/animation dataset once (prompt at install). Without it the app works
  but shows exercises without pictures. The media are (c) GymVisual and used
  under the dataset's terms, not the app's AGPL — which is why they are not
  shipped in this repository or fetched unconditionally.
- **Accounts** — the first account registered in the app becomes admin
  (`FIRST_USER_ADMIN=1`). The YunoHost permission on the URL (default:
  `all_users`) is a reachability gate, not the app identity; signup can be
  locked to invite codes inside openGym's admin settings.

## Updates

Updates bump `version` + `sources.main` (URL and sha256) together. Backups use
the standard YunoHost app backup: users, uploads, session secret and VAPID
keys are all plain files under the app data dir.

## Known limitations

- openGym has no LDAP mode; SSO does not authenticate into the app (by
  upstream design — it rejects proxy-header identity). Portal login + separate
  app login is the expected UX.
- The ~350 MB media fetch at install comes from the upstream dataset host; a
  failure there does not break the install (warns and continues).
