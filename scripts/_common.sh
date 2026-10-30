#!/bin/bash

#=================================================
# COMMON VARIABLES AND CUSTOM HELPERS
#=================================================

# SSO mint lua lives under /etc/$app so the app's own tree stays untouched (see conf/ynh_sso_login.lua).
sso_lua="/etc/$app/sso/ynh_sso_login.lua"

# Panel answers arrive as same-named shell vars; the ${key:-setting} fallback stops stale values on config-panel apply.
_opengym_sso_vars() {
    local raw
    raw="${sso_enabled:-$(ynh_app_setting_get --key=sso_enabled)}"
    case "$raw" in 1|yes|true|on) sso_on=1 ;; *) sso_on=0 ;; esac
    raw="${auto_provision:-$(ynh_app_setting_get --key=auto_provision)}"
    case "$raw" in 1|yes|true|on) auto_provision=1 ;; *) auto_provision=0 ;; esac
    sso_user_password="${sso_user_password:-$(ynh_app_setting_get --key=sso_user_password)}"
    [ -z "$sso_user_password" ] && sso_user_password="$(ynh_string_random --length=24)" \
        && ynh_app_setting_set --key=sso_user_password --value="$sso_user_password"
    api_port="$port"
    secret_file="$data_dir/secret"
    db_file="$data_dir/db.json"
    map_file="/etc/$app/sso/ynh_sso_map.json"
    origin="https://$(ynh_app_setting_get --key=domain)"
    # ORIGIN is always https (passkeys require it), so the API's secure-origin cookie name __Host-gymsid is the right one.
    cookie="__Host-gymsid"
    local cur_path
    cur_path="$(ynh_app_setting_get --key=path)"
    redirect="${cur_path%/}/"
}

# Renders the mint-route lua and grants nginx read-only access to secret + accounts; never write into data_dir — the map lives under /etc/$app/sso.
_opengym_sso_setup() {
    mkdir -p "/etc/$app/sso"
    chown root:www-data "/etc/$app/sso"
    chmod 770 "/etc/$app/sso"
    _opengym_sso_vars
    ynh_config_add --template="ynh_sso_login.lua" --destination="$sso_lua"
    chown root:root "$sso_lua"
    chmod 644 "$sso_lua"
    # www-data must traverse data_dir (0750) and read the 0600 secret/db.json.
    # The API's 0600 file creates park the ACL mask at --- (ACL entries go ineffective), so open m::r-- too; the default ACL covers db.json's later tmp+rename rewrites.
    setfacl -m u:www-data:--x "$data_dir" 2>/dev/null || \
        ynh_print_warn "setfacl failed — SSO mint route will 503 until data_dir is readable"
    setfacl -d -m u:www-data:r--,m::r-- "$data_dir" 2>/dev/null || true
    [ -f "$data_dir/secret" ] && setfacl -m u:www-data:r--,m::r-- "$data_dir/secret" 2>/dev/null || true
    [ -f "$data_dir/db.json" ] && setfacl -m u:www-data:r--,m::r-- "$data_dir/db.json" 2>/dev/null || true

    # Watchdog: the API recreates db.json/secret at 0600 on every save, breaking the ACL mask again — a path unit repairs it after each write.
    ynh_config_add --template="sso-acl.service" --destination="/etc/systemd/system/$app-sso-acl.service"
    ynh_config_add --template="sso-acl.path" --destination="/etc/systemd/system/$app-sso-acl.path"
    systemctl daemon-reload
    systemctl enable --now "$app-sso-acl.path"

    # Upstream ships the password path off; enable it while SSO is on, then leave it so provisioned profiles keep a fallback way in.
    local env_file
    env_file="$(ynh_app_setting_get --key=install_dir)/env"
    if [ "$sso_on" = "1" ] && ! grep -qx 'PASSWORD_LOGIN=1' "$env_file" 2>/dev/null; then
        echo 'PASSWORD_LOGIN=1' >> "$env_file"
        if systemctl is-active --quiet "$app"; then
            ynh_systemctl --service="$app" --action=restart --log_path=systemd --timeout=60
        fi
    fi
}

