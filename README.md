# docker-tsmod

A Docker image for a [The Specialists](https://tsmod.org) 3.0 dedicated server:

- HLDS (`steam_legacy` branch, from steamcmd) running the [ReHLDS](https://github.com/rehlds/ReHLDS) engine,
- the TS 3.0 game files, extracted from `ts-3-final.exe` by the
  [launcher](https://github.com/the-specialists-mod/tsmod-launcher)'s command line,
- the [Rust port](https://github.com/the-specialists-mod/the-specialistsmod-rs)'s server library
  in place of the original one,
- [Metamod-R](https://github.com/rehlds/Metamod-R) and [AMX Mod X](https://www.amxmodx.org) 1.10,
  with the [Rust tsx, tsfun and hamsandwich modules](https://github.com/the-specialists-mod/tsmod-amxx-rs)
  in place of the stock ones (see [AMX Mod X](#amx-mod-x)),
- [RCBot](https://github.com/the-specialists-mod/tsmod-rcbot-rs), the port's `tsmod_rcbot` bot plugin,
- nginx serving the game files over HTTP. The server points players at it (`sv_downloadurl`)
  and sends nothing through the game port (`sv_allow_dlfile 0`), so maps, models and sounds
  download at full speed.

## Run

```sh
docker compose up -d --build
```

or without compose:

```sh
docker build -t tsmod .
docker run -d --name tsmod \
  -p 27015:27015/udp -p 27015:27015/tcp -p 27080:27080/tcp \
  -e PUBLIC_HOST=203.0.113.10 -e RCON_PASSWORD=secret -e BOTS=4 \
  -v "$PWD/custom:/custom:ro" -v tsmod-data:/data \
  tsmod
```

### 64-bit

`--build-arg ARCH=amd64` builds a 64-bit server instead:

```sh
docker build --build-arg ARCH=amd64 --build-arg PORT_VERSION=v3.0.8 -t tsmod:amd64 .
```

It runs the 64-bit ReHLDS engine, `hlds_linux` and Steam libraries, Metamod-R and AMX Mod X from
[goldsrc-net/buildchain](https://github.com/goldsrc-net/buildchain)'s drop-in
(`BUILDCHAIN_VERSION`, default `v1.0.9`), with the port's `ts_amd64.so` and RCBot's
`tsmod_rcbot_amd64.so` from their `linux-x86_64` releases, and tsx, tsfun and hamsandwich from
tsmod-amxx-rs's `linux-x86_64` release (`AMXX_MODULES_VERSION`, v0.4.0 or later).
The drop-in's `steamclient.so` is the desktop Steam client's (it needs X11 and GL), so the image
uses steamcmd's 64-bit one. The rest (steamcmd's HLDS, the TS content, the settings below) is the same as the 32-bit image, which
stays the default. The engine doesn't need 32-bit libraries then, and the image has none.

## AMX Mod X test environment

[`amxx-testenv/`](amxx-testenv/README.md) has the scripts that build the AMX Mod X test servers
the AMXX module repos (tsmod-amxx-rs, tsmod-amxx-rcbot) run their end-to-end tests on:
ReHLDS roots for Linux, Windows under Wine and 64-bit Linux (buildchain's drop-in, like
`ARCH=amd64` here), in `~/games`, not in containers. It isn't part of the image.

## Settings

| Variable | Default | |
|---|---|---|
| `SERVER_NAME` | `The Specialists (Rust port)` | `hostname` |
| `MAP` | `ts_dojo` | start map |
| `MAXPLAYERS` | `16` | |
| `PORT` | `27015` | game port (UDP; TCP for rcon) |
| `HTTP_PORT` | `27080` | fast download port |
| `PUBLIC_HOST` | looked up | host name or IP players reach the server on; `sv_downloadurl` becomes `http://PUBLIC_HOST:FASTDL_PORT/` |
| `PUBLIC_IP_URL` | `https://api.ipify.org` | where the public IP is looked up when `PUBLIC_HOST` is unset |
| `FASTDL_PORT` | `HTTP_PORT` | the host port the HTTP server is published on, if it differs |
| `FASTDL_URL` | | the full `sv_downloadurl`, e.g. `https://tsmod.org/content/`; wins over `PUBLIC_HOST` (see below) |
| `DOWNLOAD_FALLBACK` | `0` | `1` lets clients fall back to downloading through the game port when HTTP fails |
| `RCON_PASSWORD` | | empty turns rcon off |
| `SV_PASSWORD` | | join password |
| `BOTS` | `8` | the port's `ts_bot_quota` |
| `BOT_BACKEND` | | the port's `ts_bot_backend`: `rcbot` for RCBot's bots, `rcbot_amxx` for RCBot as an AMX Mod X plugin ([tsmod-amxx-rcbot](https://github.com/the-specialists-mod/tsmod-amxx-rcbot): the bot logic in Pawn, for admins who change it; needs `AMXX=1`, turns tsmod_rcbot off, and costs the server more CPU), `native` for TS's own; empty leaves it to `server.cfg` (native unless it says otherwise). Like `GAMEPLAY`, the first map loads once more with it |
| `AMXX` | `1` | `0` runs the game library without metamod and AMX Mod X |
| `GAMEPLAY` | | the port's `ts_gameplay`: `21` plays by TS 2.1's rules, `30` by 3.0's; empty leaves it to `server.cfg` (3.0 unless it says otherwise). The engine runs the server config after the first map has loaded, so in 2.1 mode that map loads once more under 2.1 before anyone joins. TS 3.0's original client can't join a 2.1 server, only the Rust port's |
| `EXTRA_ARGS` | | more `hlds_linux` arguments, e.g. `-pingboost 2 +sys_ticrate 1000` |

If `PORT` or `HTTP_PORT` change, publish the matching ports.

## Downloads

At start the entrypoint starts nginx, checks that it serves `maps/$MAP.bsp`, works out the
download URL and writes it into the server config. If no address can be found (no
`PUBLIC_HOST`, `FASTDL_URL`, or answer from `PUBLIC_IP_URL`), it says so and turns the game
port downloads back on so players can still join. The nginx log lines (`fastdl: ...`) in
`docker logs` show each file players fetch.

### Downloads from another site

`FASTDL_URL` can point anywhere that serves the server's `ts/` folder at that path, over
`http://` or `https://`, for example `https://tsmod.org/content/` (so `.../content/maps/ts_dojo.bsp`).
That can be a CDN or bucket you upload the files to, or a site that proxies the path to this
container's port 27080. Notes:

- The URL can be at most 128 characters (the engine ignores longer ones); a trailing `/` is added.
- Missing files must answer 404. A site that answers every path with its own page (as a
  single-page app does) breaks downloads, and the clients can't read such chunked HTML pages either.
- At start the entrypoint downloads `maps/$MAP.bsp` from the URL and compares its size with the
  local file. It warns if they differ but starts anyway.
- HTTPS works with Xash3D FWGS builds that have TLS: the current native Linux and 64-bit Windows
  builds, which check the certificate (tested against `https://tsmod.org/`). The old FWGS 0.21
  win32 build has no HTTPS support, so its players need an `http://` URL or `DOWNLOAD_FALLBACK=1`.
  Steam Half-Life downloads through Steam's HTTP client, which should handle HTTPS, but that
  hasn't been tested here.

Game cvars can't go on the command line (GoldSrc runs `+cvar` before the game library registers
them), so the entrypoint writes `ts/docker_server.cfg` at each start and points `servercfgfile`
at it. It runs `server.cfg` first, then sets:

```
exec banned.cfg
exec listip.cfg

hostname "..."
rcon_password "..."
sv_password "..."
ts_bot_quota 8

// Downloads: maps, models, sounds and sprites come from the container's HTTP server.
sv_allowdownload 1
sv_send_resources 1
sv_downloadurl "http://203.0.113.10:27080/"
sv_allow_dlfile 0
```

Build arguments: `ARCH` (`i386` or `amd64`, see [64-bit](#64-bit)), `PORT_VERSION` (a Rust port release tag, default `latest`), `LAUNCHER_VERSION`
(`v0.12.0`), `REHLDS_VERSION` (`3.15.0.896`), `METAMOD_R_VERSION` (`1.3.0.149`), `AMXX_VERSION`
(`1.10.0-git5487`), `AMXX_MODULES_VERSION` (`v0.4.0`), `AMXX_RCBOT_VERSION` (a tsmod-amxx-rcbot release, `v0.2.0`) and `RCBOT_VERSION` (a tsmod-rcbot-rs release, `v0.3.0`). The AMXX modules and RCBot talk to the port
through its plugin API, whose version has to match: `AMXX_MODULES_VERSION` v0.4.0, `AMXX_RCBOT_VERSION` v0.2.0 and `RCBOT_VERSION` v0.3.0
go with port v3.0.8, so build those with `--build-arg PORT_VERSION=v3.0.8` (with
`latest`, a newer port can change the API, and Docker may also reuse an older cached download).

## AMX Mod X

AMX Mod X runs with its stock plugins (`addons/amxmodx/configs/plugins.ini`), which include map
voting and management:

- `mapchooser`: a vote for the next map near the end of each map (`mp_timelimit`), from
  `mapcycle.txt`, with an option to extend the current one,
- `nextmap` and `timeleft`: `nextmap` and `timeleft` in chat,
- `mapsmenu`: `amx_mapmenu` (change map) and `amx_votemapmenu` (start a map vote) for admins,
- `adminvote`: `amx_votemap`, `amx_vote` and friends,
- `admincmd`: `amx_map`, `amx_kick`, `amx_ban`, ...

and this repo's `plugins/` (compiled at build time and enabled):

- `tsmsg` (TSMessages Plus by Shurik3n): colours TS's kill announcements ("is a killer",
  "Kung-Fu style!", ...) by kind and kill streak. Cvars `amx_tsmsgs 1` (on) and
  `amx_randommsgs 0` (random colours).

The stock `maps.ini` is removed, so these use `mapcycle.txt`. Admin commands work from the server
console and rcon (`rcon amx_map ts_dojo`); in-game admins go in `users.ini`, e.g. a
`custom/addons/amxmodx/configs/users.ini` with

```
"STEAM_0:1:12345" "" "abcdefghijklmnopqrstu" "ce"
```

`/custom` can also add plugins (`addons/amxmodx/plugins/*.amxx` and a `plugins.ini`) and enable
modules (`configs/modules.ini`). tsx, tsfun and hamsandwich are the Rust ports, which reach the
server through the port's plugin API instead of TS 2.x's memory offsets.


### Bans

`amx_ban`, `amx_banip` and `amx_addban` (and the engine's `banid`/`addip` with `writeid`/`writeip`)
write `banned.cfg` and `listip.cfg`, which the server config runs at every map. The entrypoint
keeps both files in `/data` (see [Stored data](#stored-data)).

## Stored data

`/data` is a volume for what the server writes, so it survives the container:

- `banned.cfg` and `listip.cfg`: the bans.
- `rcbot/`: RCBot's data folder (`ts/tsmod/rcbot` links to it): what its bots learn (the
  `botprofiles/` files, such as the kung fu combos in `.rkf`, and the weapon and team stats) and
  the waypoints. At each start the image's own RCBot files are copied in where they're newer than
  the volume's, so a new release's waypoints arrive without losing what the bots learned.

Docker gives `/data` an anonymous volume unless you mount one; name it (`-v tsmod-data:/data`, as
`compose.yaml` does) to keep it across containers. A bind mount must be writable by uid 1000.
Without a writable `/data` all of this is lost with the container.

## Custom content

Everything in `/custom` is copied over `ts/` when the container starts, so a `custom/` folder
like this adds maps and settings:

```
custom/
  maps/ts_mymap.bsp
  mapcycle.txt
  motd.txt
  server.cfg
```

The HTTP server only serves the files clients download (`maps/`, `models/`, `sound/`,
`sprites/`, `gfx/`, `overviews/`, `resource/` and `events/`, by extension, and `.wad` files at the top level).
Config files, libraries and logs answer 404.

### Baking content into the image

To ship a map pack inside the image instead of mounting it, build with a `content` build
context; its files go over `ts/` at build time:

```sh
docker buildx build --build-context content=../mappack -t tsmod .
```

If the folder has a `case-aliases.txt` (lines of `referenced path<TAB>actual path`), the build
symlinks each referenced spelling to the real file. Maps made on Windows often refer to
`models/LightenWoods/flag.mdl` when the file is `models/lightenwoods/flag.mdl`, which a Linux
server and the HTTP server can't find otherwise.
