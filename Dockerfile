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

# --- Optional extra content (see the ts stage) ----------------------------------------------
FROM scratch AS content
# --- RCBot (the-specialists-mod/tsmod-rcbot-rs), the port's tsmod_rcbot bot plugin ----------
# No releases yet, so it's built here (on the runtime's Debian, for its glibc). RCBOT_REF must pin
# the same port release (plugin API version) as PORT_VERSION: bed1b0c = port v3.0.6.
FROM debian:${DEBIAN} AS rcbot-build
ARG RCBOT_REF=bed1b0ce5562101d3bd1f320a840c98af1f31602
# goldsrc-sys (the port's) generates its bindings from the FWGS headers; the port's release commit.
ARG FWGS_REF=51353ff8d65e58300eeb2bd014867673f1f367c6
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl git gcc-multilib libclang-dev \
 && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL https://sh.rustup.rs | sh -s -- -y --profile minimal --target i686-unknown-linux-gnu
WORKDIR /src
RUN git clone --filter=blob:none https://github.com/FWGS/xash3d-fwgs xash3d-fwgs \
 && git -C xash3d-fwgs checkout -q "$FWGS_REF" \
 && git -C xash3d-fwgs submodule update --init 3rdparty/library_suffix \
 && git clone --filter=blob:none https://github.com/the-specialists-mod/tsmod-rcbot-rs rcbot \
 && git -C rcbot checkout -q "$RCBOT_REF"
RUN cd rcbot \
 && /root/.cargo/bin/cargo build --release -p tsmod-rcbot --target i686-unknown-linux-gnu \
 && mkdir -p /out/dlls /out/tsmod \
 && cp target/i686-unknown-linux-gnu/release/libtsmod_rcbot.so /out/dlls/tsmod_rcbot_i386.so \
 && strip /out/dlls/tsmod_rcbot_i386.so \
 && cp -r data/rcbot /out/tsmod/rcbot

# --- TS 3.0 content and the Rust port, installed by the launcher's command line -------------
FROM debian:${DEBIAN} AS ts
ARG LAUNCHER_VERSION=v0.11.0
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
# Extra content baked in over ts/: empty unless built with --build-context content=<dir>, e.g. a
# map pack. A case-aliases.txt in it ("referenced path<TAB>actual path" lines) gets symlinks, since
# maps made on Windows often spell a file differently from its name and Linux is case-sensitive.
COPY --from=content / /hlds/ts/
RUN cd /hlds/ts \
 && if [ -f case-aliases.txt ]; then \
      tab=$(printf '\t'); \
      while IFS="$tab" read -r ref actual; do \
        [ -e "$ref" ] || [ ! -e "$actual" ] && continue; \
        mkdir -p "$(dirname "$ref")" && ln -s "/hlds/ts/$actual" "$ref"; \
      done < case-aliases.txt; \
    fi \
 && rm -f case-aliases.txt MISSING_RESOURCES.md

# --- Metamod-R and AMX Mod X, with the Rust port's tsx/tsfun/hamsandwich modules ---------------
# AMXX_MODULES_VERSION must be built against PORT_VERSION's plugin API (tsmod-amxx-rs v0.1.0 =
# port v3.0.6). Metamod sits between the engine and the game library; the entrypoint's AMXX
# setting chooses which one liblist.gam names.
FROM debian:${DEBIAN} AS amxx
ARG METAMOD_R_VERSION=1.3.0.149
ARG AMXX_VERSION=1.10.0-git5487
ARG AMXX_MODULES_VERSION=v0.1.0
# amxxpc, the plugin compiler, is 32-bit.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl unzip lib32stdc++6 \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /out/addons
RUN curl -fsSL -o /tmp/mm.zip \
      "https://github.com/rehlds/Metamod-R/releases/download/${METAMOD_R_VERSION}/metamod-bin-${METAMOD_R_VERSION}.zip" \
 && unzip -q /tmp/mm.zip 'addons/metamod/*' -d /tmp/mm \
 && mkdir metamod && cp /tmp/mm/addons/metamod/metamod_i386.so /tmp/mm/addons/metamod/config.ini metamod/ \
 && printf '\ngamedll dlls/ts_i386.so\n' >> metamod/config.ini \
 && echo 'linux addons/amxmodx/dlls/amxmodx_mm_i386.so' > metamod/plugins.ini \
 && curl -fsSL "https://www.amxmodx.org/amxxdrop/1.10/amxmodx-${AMXX_VERSION}-base-linux.tar.gz" \
      | tar xz --no-same-owner -C /tmp \
 && cp -a /tmp/addons/amxmodx . \
 && curl -fsSL -o /tmp/mods.zip \
      "https://github.com/the-specialists-mod/tsmod-amxx-rs/releases/download/${AMXX_MODULES_VERSION}/tsmod-amxx-rs-${AMXX_MODULES_VERSION}-linux-i686.zip" \
 && unzip -qo /tmp/mods.zip 'addons/*' -d /out \
 # The stock maps.ini lists no maps, which leaves mapchooser and the maps menu empty; without
 # it they use the server's mapcycle.txt.
 && rm amxmodx/configs/maps.ini \
 && [ -f amxmodx/modules/tsx_amxx_i386.so ] && [ -f amxmodx/plugins/mapchooser.amxx ] \
 && rm -rf /tmp/*
# Plugins of this repo (plugins/*.sma), compiled and enabled.
COPY plugins /tmp/plugins
RUN sc=amxmodx/scripting \
 && printf '\n; docker-tsmod plugins\n' >> amxmodx/configs/plugins.ini \
 && for f in /tmp/plugins/*.sma; do \
      n=$(basename "$f" .sma); \
      LD_LIBRARY_PATH=$sc $sc/amxxpc "$f" -i$sc/include -oamxmodx/plugins/$n.amxx \
        || exit 1; \
      echo "$n.amxx" >> amxmodx/configs/plugins.ini; \
    done \
 && rm -rf /tmp/plugins

FROM ts AS ts-amxx
COPY --from=amxx /out/addons /hlds/ts/addons
# Metamod-R tells plugins the game library is dlls/ts_i686.so (its known-games name for TS) even
# when config.ini's gamedll loads ts_i386.so, and tsx looks the port's plugin API up there. That
# name holds TS 3.0's original library, which nothing loads: make it the port's.
RUN ln -sf ts_i386.so /hlds/ts/dlls/ts_i686.so
COPY --from=rcbot-build /out /hlds/ts/

# --- Runtime -------------------------------------------------------------------------------
FROM debian:${DEBIAN}
RUN dpkg --add-architecture i386 \
 && apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl lib32gcc-s1 lib32stdc++6 nginx-light tini \
 && rm -rf /var/lib/apt/lists/* \
 && useradd -m -u 1000 tsmod
COPY --from=ts-amxx --chown=tsmod:tsmod /hlds /hlds
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
    BOTS=8 \
    GAMEPLAY="" \
    AMXX=1 \
    BOT_BACKEND="" \
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
