#!/bin/bash

source /usr/share/yunohost/helpers
# opengym-sso-link — make a YunoHost SSO account open openGym already signed in.
#
# No fork, no app changes. openGym's whole session is one HMAC-signed token
# (`uid:expiry:sv` keyed by the app's own ./data/secret). This script mints a
# long-lived token for a gym account and records it in an nginx map: a request
# carrying the Basic-auth header ssowat injects ONLY after a successful portal
# login gets rewritten to `Authorization: Bearer <token>` on its way to the
# API. Clients cannot forge it — ssowat clears any client-supplied Basic
# header before injecting the real one, and the portal cookie does the gate.
#
#   usage: opengym-sso-link <sso-username> [display name] [--user-id <existing uid>]
#
# Without --user-id a fresh gym account is created (or matched by display
# name). With --user-id, an existing account (e.g. your passkey one) is
# attached to the SSO user instead.
#
# Revocation: delete the user's line from the entries file, reload nginx
# (instant). Or `rm <data_dir>/secret` + restart opengym to invalidate every
# session instance-wide.
set -eu

APP=opengym
STORE=/var/lib/opengym-sso/entries
MAP=/etc/nginx/conf.d/zz-opengym-sso-map.conf
NODE=/opt/node_n/bin/node

[ "$(id -u)" = 0 ] || { echo "run as root" >&2; exit 1; }
[ "${1:-}" ] && [ "${1:-}" != "-h" ] && [ "${1:-}" != "--help" ] || {
    echo "usage: opengym-sso-link <sso-username> [display name] [--user-id <uid>]" >&2; exit 1; }

SSO_USER="$1"; shift
NAME="$SSO_USER"; GYM_UID=""
while [ $# -gt 0 ]; do
    case "$1" in
        --user-id) GYM_UID="${2:?}"; shift 2 ;;
        *) NAME="$1"; shift ;;
    esac
done

DATA=$(ynh_app_setting_get --app="$APP" --key=data_dir)
PORT=$(ynh_app_setting_get --app="$APP" --key=port)
[ -d "$DATA" ] || { echo "data dir $DATA missing — is $APP installed?" >&2; exit 1; }

# Require ssowat to inject the identity header for this app's permission.
python3 - "$APP" <<'EOF'
import sys, subprocess, yaml
app = sys.argv[1]
p = f"/etc/yunohost/apps/{app}/settings.yml"
s = yaml.safe_load(open(p))
perm = s["_permissions"]["main"]
if perm.get("auth_header") is not True:
    perm["auth_header"] = True
    yaml.safe_dump(s, open(p, "w"), default_flow_style=False, allow_unicode=True)
    subprocess.run(["yunohost", "tools", "regen-conf", "ssowat", "--force"], check=True)
    print("enabled ssowat auth_header injection for", app)
EOF

systemctl stop "$APP"

# Create (or reuse by name) the gym account. First account on the instance
# is marked admin here (the script bypasses FIRST_USER_ADMIN, which only
# fires on interactive registration).
if [ -z "$GYM_UID" ]; then
    GYM_UID=$(DATA="$DATA" NAME="$NAME" "$NODE" -e '
        const fs=require("fs"), crypto=require("crypto");
        const f=process.env.DATA+"/db.json";
        const db=fs.existsSync(f)?JSON.parse(fs.readFileSync(f,"utf8")):{users:[]};
        let u=db.users.find(u=>u.name===process.env.NAME);
        if(!u){
            u={id:crypto.randomBytes(12).toString("base64url"),name:process.env.NAME,created:new Date().toISOString()};
            if(db.users.length===0) u.admin=true;
            db.users.push(u);
            fs.writeFileSync(f+".tmp",JSON.stringify(db,null,1));
            fs.renameSync(f+".tmp",f);
        }
        console.log(u.id);')
else
    DATA="$DATA" UID_="$GYM_UID" "$NODE" -e '
        const fs=require("fs");
        const f=process.env.DATA+"/db.json";
        const db=JSON.parse(fs.readFileSync(f,"utf8"));
        const u=db.users.find(u=>u.id===process.env.UID_);
        if(!u){console.error("no such gym uid");process.exit(1)}
        if(db.users.length===1&&!u.admin){u.admin=true;fs.writeFileSync(f+".tmp",JSON.stringify(db,null,1));fs.renameSync(f+".tmp",f);}
        else if(!u.admin){console.error("warning: attaching to non-admin account on a multi-user instance")}'
fi

# Mint the long-lived session token with the app's own signing key.
TOKEN=$(DATA="$DATA" UID_="$GYM_UID" EXP=$(( $(date +%s%3N) + 3650*86400000 )) "$NODE" -e '
    const fs=require("fs"), crypto=require("crypto");
    const secret=fs.readFileSync(process.env.DATA+"/secret","utf8").trim();
    let sv=0;
    try{const db=JSON.parse(fs.readFileSync(process.env.DATA+"/db.json","utf8"));sv=(db.users.find(u=>u.id===process.env.UID_)||{}).sv||0}catch{}
    const p=process.env.UID_+":"+process.env.EXP+":"+sv;
    console.log(p+"."+crypto.createHmac("sha256",secret).update(p).digest("base64url"));')

# Record entry (one per SSO user; re-running replaces) and rebuild the map.
mkdir -p "$(dirname "$STORE")" && chmod 700 "$(dirname "$STORE")"
touch "$STORE" && chmod 600 "$STORE"
grep -v "^${SSO_USER}	" "$STORE" > "$STORE.new" || true
printf '%s\t%s\n' "$SSO_USER" "$TOKEN" >> "$STORE.new"
mv "$STORE.new" "$STORE"

{
    echo "# Managed by opengym-sso-link — ssowat-Basic -> openGym bearer map."
    echo '# Entries: /var/lib/opengym-sso/entries (user<TAB>token). Reload nginx after edits.'
    echo 'map $http_authorization $opengym_auth {'
    # Unmatched requests (incl. the mobile app's own Bearer tokens) pass
    # through untouched; empty would also strip the SPA's cookie sessions?
    # No — cookies are separate; emptying only drops unknown Authorization.
    echo '    default $http_authorization;'
    while IFS=$'\t' read -r u tok; do
        b64=$(printf '%s:-' "$u" | base64 -w0)
        printf '    "~^Basic %s$" "Bearer %s";\n' "$b64" "$tok"
    done < "$STORE"
    echo '}'
} > "$MAP.new"
install -m 644 "$MAP.new" "$MAP" && rm -f "$MAP.new"

chown "$APP:$APP" "$DATA/db.json"
systemctl start "$APP"
for _ in $(seq 1 20); do curl -fsS -m 2 "http://127.0.0.1:$PORT/api/health" >/dev/null 2>&1 && break; sleep 1; done

# Ensure the app's live nginx conf uses the map var (older renders pinned
# `Authorization "";`). Same replacement lives in the package's nginx.conf
# template, so future renders are correct on their own.
DOMAIN=$(ynh_app_setting_get --app="$APP" --key=domain)
NGX="/etc/nginx/conf.d/$DOMAIN.d/$APP.conf"
if [ -f "$NGX" ] && grep -q 'proxy_set_header Authorization "";' "$NGX"; then
    sed -i 's|proxy_set_header Authorization "";|proxy_set_header Authorization $opengym_auth;|' "$NGX"
fi

if nginx -t -q 2>/dev/null; then
    systemctl reload nginx
    echo "Linked SSO user '$SSO_USER' -> openGym '$NAME' (uid $GYM_UID)."
    echo "Signed in to the portal as $SSO_USER? openGym is already signed in."
else
    echo "WARNING: nginx config test failed after map write — reverting map, NOT reloading." >&2
    grep -v "^${SSO_USER}	" "$STORE" > "$STORE.tmp" || true; printf '%s\t%s\n' "$SSO_USER" "$TOKEN" >> "$STORE.tmp"
    nginx -t 2>&1 | tail -3
    exit 1
fi
