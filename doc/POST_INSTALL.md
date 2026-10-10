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

The install fetched the exercise photo/animation dataset (~350 MB) unless you
declined. If it was declined or failed, exercises work but show no media; to add
it later:

```bash
sudo -u __APP__ git clone --depth 1 https://github.com/hasaneyldrm/exercises-dataset /tmp/exds
sudo mkdir -p __INSTALL_DIR__/media/img __INSTALL_DIR__/media/gif
sudo cp /tmp/exds/images/*.jpg __INSTALL_DIR__/media/img/
sudo cp /tmp/exds/videos/*.gif __INSTALL_DIR__/media/gif/
sudo chown -R __APP__:__APP__ __INSTALL_DIR__/media
```

(Images/animations are © GymVisual, used under the dataset's terms — see the
app's NOTICE.md; the dataset is fetched from upstream, not redistributed.)

### Backup

`yunohost backup create --apps __APP__` covers everything: accounts, sessions,
uploads and the session secret live in the app's data dir.
