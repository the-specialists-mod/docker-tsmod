# The Specialists 3.0 dedicated server: HLDS (steam_legacy) with ReHLDS, the Rust port's game
# library, and nginx serving the game files over HTTP for fast downloads (sv_downloadurl).
#
# ARCH=i386 (the default) runs the 32-bit engine. ARCH=amd64 runs a 64-bit one: ReHLDS, Metamod-R
# and AMX Mod X from goldsrc-net/buildchain's 64-bit build, with the port's and RCBot's x86_64
# libraries.

ARG DEBIAN=bookworm-slim
ARG ARCH=i386

# --- HLDS from steamcmd, with the ReHLDS engine over it -------------------------------------
FROM debian:${DEBIAN} AS steamcmd
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

FROM steamcmd AS hlds-i386
ARG REHLDS_VERSION=3.15.0.896
RUN curl -fsSL -o /tmp/rehlds.zip \
      "https://github.com/rehlds/ReHLDS/releases/download/${REHLDS_VERSION}/rehlds-bin-${REHLDS_VERSION}.zip" \
 && unzip -q /tmp/rehlds.zip -d /tmp/rehlds \
 && cp -a /tmp/rehlds/bin/linux32/. /hlds/ \
 && chmod +x /hlds/hlds_linux /hlds/hltv \
 && rm -rf /tmp/rehlds /tmp/rehlds.zip /hlds/steamapps

# buildchain's drop-in: a 64-bit ReHLDS engine, hlds_linux, hltv and the Steam libraries they load
# (steamcmd's are 32-bit). Its Metamod-R and AMX Mod X go in the amxx stage.
FROM steamcmd AS buildchain
ARG BUILDCHAIN_VERSION=v1.0.9
RUN curl -fsSL -o /tmp/dropin.zip \
      "https://github.com/goldsrc-net/buildchain/releases/download/${BUILDCHAIN_VERSION}/hlds-dropin-linux-amd64.zip" \
 && mkdir /dropin && unzip -q /tmp/dropin.zip -d /dropin && rm /tmp/dropin.zip \
 && [ -f /dropin/engine_i486.so ] && [ -f /dropin/valve/addons/metamod/dlls/metamod_amd64.so ]

# The drop-in's steamclient.so is the desktop client's (it links X11, GL, PipeWire): the server
# uses steamcmd's 64-bit one.
FROM steamcmd AS hlds-amd64
COPY --from=buildchain /dropin /tmp/dropin
RUN find /tmp/dropin -maxdepth 1 -type f \( -name '*.so' -o -name hlds_linux -o -name hltv \) \
      ! -name steamclient.so -exec cp {} /hlds/ \; \
 && cp /steamcmd/linux64/steamclient.so /hlds/steamclient.so \
 && chmod +x /hlds/hlds_linux /hlds/hltv \
 && rm -rf /tmp/dropin /hlds/steamapps

FROM hlds-${ARCH} AS hlds

# --- Optional extra content (see the ts stage) ----------------------------------------------
FROM scratch AS content
# --- RCBot (the-specialists-mod/tsmod-rcbot-rs), the port's tsmod_rcbot bot plugin ----------
# The release built for bookworm's glibc (2.36). RCBOT_VERSION must pin the same port release
# (plugin API version) as PORT_VERSION: v0.3.0 = port v3.0.8.
FROM debian:${DEBIAN} AS rcbot
ARG ARCH
ARG RCBOT_VERSION=v0.3.0
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*
RUN mkdir /out \
 && platform=$([ "$ARCH" = amd64 ] && echo linux-x86_64 || echo linux-i686) \
 && curl -fsSL "https://github.com/the-specialists-mod/tsmod-rcbot-rs/releases/download/${RCBOT_VERSION}/tsmod-rcbot-rs-${RCBOT_VERSION}-${platform}-glibc2.36.tar.gz" \
      | tar xz --no-same-owner -C /out ./ts \
 && [ -f "/out/ts/dlls/tsmod_rcbot_${ARCH}.so" ] && [ -d /out/ts/tsmod/rcbot ]

# --- TS 3.0 content and the Rust port, installed by the launcher's command line -------------
FROM debian:${DEBIAN} AS ts
ARG ARCH
ARG LAUNCHER_VERSION=v0.12.0
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
# The launcher installs the port's 32-bit libraries for Half-Life: the 64-bit engine loads the
# linux-x86_64 release's (ts_amd64.so), the same version.
RUN [ "$ARCH" = amd64 ] || exit 0; \
    tag=$PORT_VERSION; \
    if [ "$tag" = latest ]; then \
      tag=$(curl -fsSLI -o /dev/null -w '%{url_effective}' \
        https://github.com/the-specialists-mod/the-specialistsmod-rs/releases/latest); \
      tag=${tag##*/}; \
    fi; \
    curl -fsSL "https://github.com/the-specialists-mod/the-specialistsmod-rs/releases/download/${tag}/the-specialists-rs-${tag}-linux-x86_64.tar.gz" \
      | tar xz --no-same-owner -C /hlds ts/dlls ts/cl_dlls \
 && [ -f /hlds/ts/dlls/ts_amd64.so ]
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
# AMXX_MODULES_VERSION must be built against PORT_VERSION's plugin API (tsmod-amxx-rs v0.3.0 and
# v0.4.0 = port v3.0.8; v0.4.0 adds the x86_64 modules the 64-bit image uses). Metamod sits between the engine and the game library; the entrypoint's AMXX
# setting chooses which one liblist.gam names.
FROM debian:${DEBIAN} AS amxx-i386
ARG METAMOD_R_VERSION=1.3.0.149
ARG AMXX_VERSION=1.10.0-git5487
ARG AMXX_MODULES_VERSION=v0.4.0
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

FROM debian:${DEBIAN} AS amxx-amd64
ARG AMXX_MODULES_VERSION=v0.4.0
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl unzip \
 && rm -rf /var/lib/apt/lists/*
COPY --from=buildchain /dropin/valve/addons /tmp/addons
WORKDIR /out/addons
RUN mkdir metamod \
 && cp /tmp/addons/metamod/dlls/metamod_amd64.so /tmp/addons/metamod/config.ini metamod/ \
 && printf '\ngamedll dlls/ts_amd64.so\n' >> metamod/config.ini \
 && echo 'linux addons/amxmodx/dlls/amxmodx_mm_amd64.so' > metamod/plugins.ini \
 && cp -a /tmp/addons/amxmodx . \
 && rm amxmodx/configs/maps.ini \
 && curl -fsSL -o /tmp/mods.zip \
      "https://github.com/the-specialists-mod/tsmod-amxx-rs/releases/download/${AMXX_MODULES_VERSION}/tsmod-amxx-rs-${AMXX_MODULES_VERSION}-linux-x86_64.zip" \
 && unzip -qo /tmp/mods.zip 'addons/*' -d /out \
 && [ -f amxmodx/modules/tsx_amxx_amd64.so ] && [ -f amxmodx/plugins/mapchooser.amxx ] \
 && rm -rf /tmp/*

FROM amxx-${ARCH} AS amxx
WORKDIR /out/addons
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
ARG ARCH
COPY --from=amxx /out/addons /hlds/ts/addons
# Metamod-R tells plugins the game library is dlls/ts_i686.so (its known-games name for TS, in the
# 64-bit build too) even when config.ini's gamedll loads ts_i386.so, and tsx looks the port's
# plugin API up there. That name holds TS 3.0's original library, which nothing loads: make it the
# port's.
RUN ln -sf "ts_${ARCH}.so" /hlds/ts/dlls/ts_i686.so
COPY --from=rcbot /out/ts /hlds/ts/

# --- Runtime -------------------------------------------------------------------------------
FROM debian:${DEBIAN}
ARG ARCH
RUN if [ "$ARCH" = i386 ]; then set -- lib32gcc-s1 lib32stdc++6; dpkg --add-architecture i386; fi \
 && apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl nginx-light tini "$@" \
 && rm -rf /var/lib/apt/lists/* \
 && useradd -m -u 1000 tsmod \
 && mkdir /data && chown tsmod:tsmod /data
COPY --from=ts-amxx --chown=tsmod:tsmod /hlds /hlds
COPY nginx.conf /etc/nginx/tsmod.conf
COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh
USER tsmod
# HLDS's Steam API looks for the client library here, and needs the app id (Half-Life, 70).
RUN sdk=$([ "$ARCH" = amd64 ] && echo sdk64 || echo sdk32) \
 && mkdir -p "/home/tsmod/.steam/$sdk" && ln -s /hlds/steamclient.so "/home/tsmod/.steam/$sdk/steamclient.so" \
 && echo 70 > /hlds/steam_appid.txt
WORKDIR /hlds

ENV LIB_ARCH=${ARCH} \
    PORT=27015 \
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
# /data keeps what the server writes: bans and RCBot's data (what its bots learn).
VOLUME ["/custom", "/data"]
EXPOSE 27015/udp 27015/tcp 27080/tcp
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
