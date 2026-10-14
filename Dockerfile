# The Specialists 3.0 dedicated server: HLDS (steam_legacy) with ReHLDS, the Rust port's game
# library, and nginx serving the game files over HTTP for fast downloads (sv_downloadurl).

ARG DEBIAN=bookworm-slim

# --- HLDS from steamcmd, with the ReHLDS engine over it -------------------------------------
FROM debian:${DEBIAN} AS hlds
ARG REHLDS_VERSION=3.15.0.896
RUN dpkg --add-architecture i386 \
 && apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl unzip lib32gcc-s1 lib32stdc++6 \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /steamcmd
RUN curl -fsSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz | tar xz
# app_update 90 often stops part way ("state is 0x..."): run it until valve is there.
RUN for i in 1 2 3 4 5; do \
      ./steamcmd.sh +force_install_dir /hlds +login anonymous \
        +app_set_config 90 mod valve +app_update 90 -beta steam_legacy validate +quit; \
      [ -f /hlds/valve/liblist.gam ] && [ -f /hlds/hlds_linux ] && break; \
    done \
 && [ -f /hlds/valve/liblist.gam ]
RUN curl -fsSL -o /tmp/rehlds.zip \
      "https://github.com/rehlds/ReHLDS/releases/download/${REHLDS_VERSION}/rehlds-bin-${REHLDS_VERSION}.zip" \
 && unzip -q /tmp/rehlds.zip -d /tmp/rehlds \
 && cp -a /tmp/rehlds/bin/linux32/. /hlds/ \
 && chmod +x /hlds/hlds_linux /hlds/hltv \
 && rm -rf /tmp/rehlds /tmp/rehlds.zip /hlds/steamapps

# --- TS 3.0 content and the Rust port, installed by the launcher's command line -------------
FROM debian:${DEBIAN} AS ts
ARG LAUNCHER_VERSION=v0.7.0
# A Rust port release tag (the-specialists-mod/the-specialistsmod-rs), or "latest".
ARG PORT_VERSION=latest
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl libxcb1 libxkbcommon0 libxkbcommon-x11-0 \
 && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL -o /usr/local/bin/ts-launcher \
      "https://github.com/the-specialists-mod/tsmod-launcher/releases/download/${LAUNCHER_VERSION}/ts-launcher-${LAUNCHER_VERSION}-linux-x86_64.bin" \
 && chmod +x /usr/local/bin/ts-launcher
COPY --from=hlds /hlds /hlds
# --half-life on an HLDS root: ts-3-final.exe extracted into /hlds/ts, then the port's linux-i686
# libraries over it.
RUN if [ "$PORT_VERSION" = latest ]; then set -- --port; else set -- --port --port-version "$PORT_VERSION"; fi \
 && TSINSTALLER_HOME=/tmp/tsinstaller XDG_CACHE_HOME=/tmp/cache \
      ts-launcher install --root /hlds --half-life "$@" \
 && rm -rf /tmp/tsinstaller /tmp/cache \
 && [ -f /hlds/ts/dlls/ts_i386.so ]

# --- Runtime -------------------------------------------------------------------------------
FROM debian:${DEBIAN}
RUN dpkg --add-architecture i386 \
 && apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl lib32gcc-s1 lib32stdc++6 nginx-light tini \
 && rm -rf /var/lib/apt/lists/* \
 && useradd -m -u 1000 tsmod
COPY --from=ts --chown=tsmod:tsmod /hlds /hlds
COPY nginx.conf /etc/nginx/tsmod.conf
COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh
USER tsmod
# HLDS's Steam API looks for the client library here, and needs the app id (Half-Life, 70).
RUN mkdir -p /home/tsmod/.steam/sdk32 && ln -s /hlds/steamclient.so /home/tsmod/.steam/sdk32/steamclient.so \
 && echo 70 > /hlds/steam_appid.txt
WORKDIR /hlds

ENV PORT=27015 \
    HTTP_PORT=27080 \
    MAP=ts_dojo \
    MAXPLAYERS=16 \
    SERVER_NAME="The Specialists (Rust port)" \
    RCON_PASSWORD="" \
    SV_PASSWORD="" \
    BOTS=0 \
    PUBLIC_HOST="" \
    PUBLIC_IP_URL=https://api.ipify.org \
    FASTDL_PORT="" \
    FASTDL_URL="" \
    DOWNLOAD_FALLBACK=0 \
    EXTRA_ARGS=""

# /custom is copied over ts/ at start: maps, models, sounds, mapcycle.txt, motd.txt, server.cfg.
VOLUME ["/custom"]
EXPOSE 27015/udp 27015/tcp 27080/tcp
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
