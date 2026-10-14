# docker-tsmod

A Docker image for a [The Specialists](https://tsmod.org) 3.0 dedicated server:

- HLDS (`steam_legacy` branch, from steamcmd) running the [ReHLDS](https://github.com/rehlds/ReHLDS) engine,
- the TS 3.0 game files, extracted from `ts-3-final.exe` by the
  [launcher](https://github.com/the-specialists-mod/tsmod-launcher)'s command line,
- the [Rust port](https://github.com/the-specialists-mod/the-specialistsmod-rs)'s server library
  in place of the original one,
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
  -v "$PWD/custom:/custom:ro" \
  tsmod
```

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
| `BOTS` | `0` | the port's `ts_bot_quota` |
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
hostname "..."
rcon_password "..."
sv_password "..."
ts_bot_quota 0

// Downloads: maps, models, sounds and sprites come from the container's HTTP server.
sv_allowdownload 1
sv_send_resources 1
sv_downloadurl "http://203.0.113.10:27080/"
sv_allow_dlfile 0
```

Build arguments: `PORT_VERSION` (a Rust port release tag, default `latest`), `LAUNCHER_VERSION`
(`v0.7.0`), `REHLDS_VERSION` (`3.15.0.896`).

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
