<!-- app-description-start -->
openGym is a self-hosted gym and body-weight tracker: routines over a library of
1,300+ exercises with animated demos, guided workouts with rest timers and PR
detection, progression rules (linear, Greyskull, double progression), strength
balance ratios, body-weight charts and progress photos. Passkey (Face ID /
Touch ID / fingerprint) login, offline-capable PWA installable on the home
screen, data stored as plain files in a folder you own and back up.

This package runs openGym natively: the API as a systemd service under its own
user, the frontend as static files served by nginx — no Docker. Passkeys work
over the app's own accounts; YunoHost SSO deliberately does *not* provide the
identity (openGym has no LDAP mode), so access control on the portal side is
"who may reach the page", and accounts are created inside openGym.
<!-- app-description-end -->
