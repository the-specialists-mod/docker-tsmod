#!/bin/sh
# Starts nginx (fast downloads of ts/) in the background and the TS dedicated server in front.
set -eu

TS=/hlds/ts

# User content over the stock install.
if [ -d /custom ] && [ -n "$(ls -A /custom 2>/dev/null)" ]; then
    echo "entrypoint: copying /custom over $TS"
    cp -a /custom/. "$TS"/
fi

sed "s/@HTTP_PORT@/$HTTP_PORT/" /etc/nginx/tsmod.conf > /tmp/nginx.conf
nginx -c /tmp/nginx.conf
for _ in 1 2 3 4 5 6 7 8 9 10; do
    curl -fsSI -o /dev/null "http://127.0.0.1:$HTTP_PORT/maps/$MAP.bsp" 2>/dev/null && break
    sleep 0.5
done
if ! curl -fsSI -o /dev/null "http://127.0.0.1:$HTTP_PORT/maps/$MAP.bsp"; then
    echo "entrypoint: nginx doesn't serve maps/$MAP.bsp on port $HTTP_PORT" >&2
    exit 1
fi

# The URL clients download from. FASTDL_URL as given, else http://PUBLIC_HOST:FASTDL_PORT/, with
# PUBLIC_HOST looked up from outside when it isn't set (the container only knows its own address).
url=$FASTDL_URL
if [ -z "$url" ]; then
    host=$PUBLIC_HOST
    if [ -z "$host" ]; then
        host=$(curl -fsS --max-time 5 "$PUBLIC_IP_URL" 2>/dev/null | tr -d '[:space:]') || host=
        [ -n "$host" ] && echo "entrypoint: public address $host (from $PUBLIC_IP_URL; set PUBLIC_HOST to choose it)"
    fi
    [ -n "$host" ] && url="http://$host:${FASTDL_PORT:-$HTTP_PORT}/"
fi
case $url in
    "" | */) ;;
    *) url="$url/" ;;
esac
# The engine ignores longer URLs.
if [ "${#url}" -gt 128 ]; then
    echo "entrypoint: sv_downloadurl is longer than 128 characters: $url" >&2
    exit 1
fi

if [ -n "$FASTDL_URL" ]; then
    # Somewhere else (a CDN, or a site proxying to this container): it has to have the same files.
    # Compare sizes: a site that answers every path with its HTML page also says 200.
    want=$(wc -c < "$TS/maps/$MAP.bsp")
    got=$(curl -fsSL --max-time 10 -o /dev/null -w '%{size_download}' "${url}maps/$MAP.bsp" 2>/dev/null) || got=
    if [ "$got" = "$want" ]; then
        echo "entrypoint: ${url}maps/$MAP.bsp is there"
    else
        echo "entrypoint: ${url}maps/$MAP.bsp isn't this server's $MAP.bsp (${got:-no answer}, want $want bytes): check that $url serves this server's ts/ files" >&2
    fi
fi
if [ -n "$url" ]; then
    # HTTP only: with sv_allow_dlfile 0 the engine sends no files through the game port.
    dlfile=$([ "$DOWNLOAD_FALLBACK" = 1 ] && echo 1 || echo 0)
    echo "entrypoint: downloads from $url (game port fallback: $([ "$dlfile" = 1 ] && echo on || echo off))"
else
    dlfile=1
    echo "entrypoint: no public address (set PUBLIC_HOST or FASTDL_URL): downloads go through the game port, slowly" >&2
fi
[ -z "$RCON_PASSWORD" ] && echo "entrypoint: RCON_PASSWORD is unset: rcon is off"

# Game cvars can't go on the command line (GoldSrc runs +cvar before the game library registers
# them), so they go in a cfg the game runs once each map has loaded. server.cfg runs first, so
# these environment settings win over it.
q() { printf '%s' "$1" | tr -d '"'; }
cat > "$TS/docker_server.cfg" <<EOF
// Written by entrypoint.sh at every start from the container's environment; put your own
// settings in server.cfg (or /custom/server.cfg), which runs first.
exec server.cfg

hostname "$(q "$SERVER_NAME")"
rcon_password "$(q "$RCON_PASSWORD")"
sv_password "$(q "$SV_PASSWORD")"
ts_bot_quota $BOTS
$([ -n "$GAMEPLAY" ] && printf 'ts_gameplay "%s"\n' "$(q "$GAMEPLAY")")

// Downloads: maps, models, sounds and sprites come from the container's HTTP server.
sv_allowdownload 1
sv_send_resources 1
sv_downloadurl "$(q "$url")"
sv_allow_dlfile $dlfile
EOF

export LD_LIBRARY_PATH=/hlds
# shellcheck disable=SC2086
exec ./hlds_linux -game ts -port "$PORT" +ip 0.0.0.0 +maxplayers "$MAXPLAYERS" \
    +servercfgfile docker_server.cfg +map "$MAP" $EXTRA_ARGS "$@"
