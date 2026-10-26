-- YunoHost SSO walk-in login for openGym (YunoHost package glue, not upstream code).
--
-- Mint route: reached only at /ynh-sso-login after SSOwat authenticated the
-- portal session. SSOwat strips any client-forged ynh_* / Authorization headers
-- and injects its own; we require BOTH the injected YNH_USER and the injected
-- Basic Authorization header (proof the `sso` permission — and only it —
-- matched), so a request that merely guesses the URL can never log in.
--
-- Already-known portal user  -> mint an openGym session cookie directly.
-- Unknown portal user        -> provision through openGym's own public API
--                                (admin invite + register), then mint.
-- The app's files are never modified or read-write here: we only READ the
-- session secret (data_dir/secret) and accounts (data_dir/db.json), both
-- granted to www-data via ACL by the package.

local cjson = require("cjson.safe")
local hmac  = require("openssl.hmac")

local SSO_ON           = __SSO_ON__
local AUTO_PROVISION   = __AUTO_PROVISION__
local API_PORT         = __API_PORT__
local ORIGIN           = "__ORIGIN__"
local COOKIE           = "__COOKIE__"
local SECRET_FILE      = "__SECRET_FILE__"
local DB_FILE          = "__DB_FILE__"
local MAP_FILE         = "__MAP_FILE__"
local USER_PASSWORD    = "__SSO_USER_PASSWORD__"
local REDIRECT         = "__REDIRECT__"

local SESSION_DAYS     = 90          -- matches the API default (SESSION_DAYS)
local B64CHARS         = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function b64url(s)
    local r = {}
    for i = 1, #s, 3 do
        local a, b, c = s:byte(i, i + 2)
        local n = (a or 0) * 65536 + (b or 0) * 256 + (c or 0)
        r[#r + 1] = B64CHARS:sub(math.floor(n / 262144) % 64 + 1, math.floor(n / 262144) % 64 + 1)
        r[#r + 1] = B64CHARS:sub(math.floor(n / 4096) % 64 + 1, math.floor(n / 4096) % 64 + 1)
        r[#r + 1] = b and B64CHARS:sub(math.floor(n / 64) % 64 + 1, math.floor(n / 64) % 64 + 1) or "="
        r[#r + 1] = c and B64CHARS:sub(n % 64 + 1, n % 64 + 1) or "="
    end
    return (table.concat(r):gsub("+", "-"):gsub("/", "_"):gsub("=$", ""))
end

local function read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local function deny(status, msg)
    ngx.status = status
    ngx.header["Content-Type"] = "text/plain; charset=utf-8"
    ngx.say(msg)
    return ngx.exit(status)
end

-- Minimal HTTP/1.1 over a cosocket (ngx.location.capture cannot run under
-- the HTTP/2 vhost this site is served on).
local function api(method, path, token, body)
    local sock = ngx.socket.tcp()
    sock:settimeout(4000)
    local ok, err = sock:connect("127.0.0.1", API_PORT)
    if not ok then return nil, err end
    body = body or ""
    local head = table.concat({
        method, " ", path, " HTTP/1.1\r\n",
        "Host: 127.0.0.1\r\n",
        "Accept: application/json\r\n",
        "Content-Type: application/json\r\n",
        "Origin: ", ORIGIN, "\r\n",
        "Sec-Fetch-Site: same-origin\r\n",
        "Connection: close\r\n",
    })
    if token then head = head .. "Cookie: " .. COOKIE .. "=" .. token .. "\r\n" end
    head = head .. "Content-Length: " .. #body .. "\r\n\r\n"
    local sent = sock:send(head)
    if not sent then sock:close(); return nil, "send failed" end
    if body ~= "" then sock:send(body) end
    local line = sock:receive("*l")
    if not line then sock:close(); return nil, "no response" end
    local status = tonumber(line:match("(%d%d%d)")) or 0
    local clen, chunked = nil, false
    while true do
        line = sock:receive("*l")
        if not line or line == "" then break end
        local v = line:match("^[Cc]ontent%-[Ll]ength:%s*(%d+)")
        if v then clen = tonumber(v) end
        if line:match("^[Tt]ransfer%-[Ee]ncoding:.*[Cc]hunked") then chunked = true end
    end
    local out
    if clen then
        out = sock:receive(clen) or ""
    elseif chunked then
        -- The API frames its JSON responses with chunked encoding.
        local parts = {}
        while true do
            local size_line = sock:receive("*l")
            local size = size_line and tonumber(size_line, 16)
            if not size or size <= 0 then break end
            parts[#parts + 1] = sock:receive(size) or ""
            sock:receive(2)  -- trailing CRLF
        end
        out = table.concat(parts)
    else
        out = sock:receive("*a") or ""
    end
    sock:close()
    return status, cjson.decode(out)
end

-- Session cookie value exactly as the API's own makeSession() signs it:
-- HMAC-SHA256 over "<uid>:<expiry_ms>:<sv>" with data_dir/secret, base64url.
local function token_for(secret, uid, sv)
    local exp = math.floor(ngx.now() * 1000) + SESSION_DAYS * 86400000
    local payload = uid .. ":" .. exp .. ":" .. (sv or 0)
    local mac = hmac.new(secret, "sha256"):final(payload)
    return payload .. "." .. b64url(mac)
end

-- db.json is rewritten wholesale by the API on every save; read defensively
-- with retries so a torn/absent file costs a retry, not a wrong decision.
local function load_db()
    -- No file at all = fresh instance with zero accounts: an empty db,
    -- not an error (the API below stays the single source of truth).
    if not read_file(DB_FILE) then return { users = {} } end
    for _ = 1, 3 do
        local s = read_file(DB_FILE)
        local t = s and cjson.decode(s)
        if type(t) == "table" then return t end
        ngx.sleep(0.05)
    end
    return nil
end

local function find_by(db, key, val)
    for _, u in ipairs(type(db.users) == "table" and db.users or {}) do
        if u[key] == val then return u end
    end
    return nil
end

local function load_map()
    local s = read_file(MAP_FILE)
    local t = s and cjson.decode(s)
    if type(t) ~= "table" then return {} end
    return t
end

local function save_map(map)
    local tmp = MAP_FILE .. "." .. tostring(ngx.worker.pid()) .. ".tmp"
    local f = io.open(tmp, "w")
    if not f then return false end
    f:write(cjson.encode(map))
    f:close()
    os.remove(MAP_FILE)
    return os.rename(tmp, MAP_FILE) and true or false
end

-- ------------------------------------------------------------------ main --

if SSO_ON ~= 1 then
    return deny(404, "SSO walk-in login is disabled (enable it in the app's config panel).")
end

local headers = ngx.req.get_headers()
local portal_user = headers["ynh_user"]
local auth = headers["authorization"] or ""
-- Both must be SSOwat-injected: the Basic header only ever appears on URIs
-- matched by the auth_header-enabled `sso` permission, i.e. a portal-authenticated
-- request for exactly this route.
if type(portal_user) ~= "string" or auth:sub(1, 6) ~= "Basic " then
    return deny(401, "This route only works through a YunoHost portal session.")
end
portal_user = portal_user:sub(1, 40)
if not portal_user:match("^[%w%._%-]+$") then
    return deny(400, "Invalid username.")
end

local secret = read_file(SECRET_FILE)
if secret then
    secret = secret:gsub("^%s+", ""):gsub("%s+$", "")
end
if not secret or secret == "" then
    return deny(503, "The app secret is not readable yet (openGym may not have started).")
end

local db = load_db()
if not db then
    return deny(503, "openGym accounts are unreadable right now; try again in a moment.")
end

local map = load_map()
local uid = type(map[portal_user]) == "string" and map[portal_user]:match("^[%w%-_]+$") or nil
local user = uid and find_by(db, "id", uid) or nil

-- A profile may predate the SSO feature (claimed through the app's own
-- login): adopt it by exact-name match and remember the binding.
if not user then
    user = find_by(db, "name", portal_user)
    if user then
        uid = user.id
        map[portal_user] = uid
        save_map(map)
    end
end

if user and user.disabled then
    return deny(403, "This openGym profile has been disabled by an administrator.")
end

if not user then
    if AUTO_PROVISION ~= 1 then
        return deny(403, "No openGym profile for this portal user yet, and automatic provisioning is off.")
    end

    -- Provisioning runs entirely through the app's public HTTP API:
    -- the instance admin mints an invite, then the account registers itself.
    local admin = find_by(db, "admin", true)
    if not admin then
        return deny(503, "The instance owner has not created their openGym profile yet. " ..
                        "Sign in once with the app's own login to claim admin, then retry.")
    end
    local admin_token = token_for(secret, admin.id, admin.sv)

    local status, res = api("POST", "/api/admin/invites/new", admin_token, cjson.encode({ note = "portal SSO" }))
    local code = status == 200 and res and res.invite and res.invite.code or nil
    if not code then
        return deny(503, "Could not create an invite code (HTTP " .. tostring(status) .. ").")
    end

    status, res = api("POST", "/api/register/password", nil,
        cjson.encode({ name = portal_user, password = USER_PASSWORD, code = code }))
    if status == 200 and res and res.user and res.user.id then
        uid = res.user.id
    elseif status == 409 then
        -- Raced with a parallel registration for the same name: adopt it.
        local u2 = find_by(load_db() or db, "name", portal_user)
        if u2 and not u2.disabled then uid = u2.id end
    end
    if not uid then
        return deny(503, "Could not provision the openGym profile (HTTP " .. tostring(status) .. ").")
    end

    map[portal_user] = uid
    save_map(map)
    user = find_by(load_db() or db, "id", uid)
end

local token = token_for(secret, uid, user and user.sv or 0)
ngx.header["Set-Cookie"] = COOKIE .. "=" .. token ..
    "; Path=/; Max-Age=" .. (SESSION_DAYS * 86400) .. "; HttpOnly; Secure; SameSite=Lax"
return ngx.redirect(REDIRECT, 302)
