# AMX Mod X + metamod test environment for the TS Rust port

Dedicated-server roots that run the TS Rust port (`~/dev/hl/rust-hlmod-the-specialists`)
under metamod + AMX Mod X 1.10, for end-to-end tests of AMXX modules/plugins (e.g. the Rust
tsx/tsfun modules in `~/dev/hl/tsmod-amxx-rs`). It lives in docker-tsmod (`amxx-testenv/`), with
`~/dev/hl/ref/amxx-testenv` a symlink to it: the xtasks of tsmod-amxx-rs and tsmod-amxx-rcbot
default to that path (`AMXX_TESTENV`). The roots are host directories, not containers.

| Root | Engine | Port library | Status |
|---|---|---|---|
| `~/games/amxx_rehlds_linux` | ReHLDS 3.15.0.896 release, linux32, on HLDS steam_legacy files | `dist/linux-i686/ts/dlls/ts_i386.so` | works (primary) |
| `~/games/amxx_rehlds_win` | ReHLDS 3.15.0.896 release, win32 under Wine 11.17 | `dist/windows-i686/ts/dlls/mp.dll` | works (secondary) |
| `~/games/amxx_rehlds_linux64` | goldsrc-net/buildchain v1.0.9 linux-amd64 drop-in (64-bit ReHLDS, Metamod-R, AMX Mod X fork), on HLDS steam_legacy files, steamcmd's `linux64/steamclient.so` | `dist/linux-x86_64/ts/dlls/ts_amd64.so` | works (`setup.sh linux64`, port 27317) |

Neither root touches the xtask roots (`~/games/hlds_linux`, `hlds_win`, `hlds25_*`, `xash*`).
The win root uses its own Wine prefix `~/games/wineprefix_amxx` (see Pitfalls).

## Files

| Path | What |
|---|---|
| `setup.sh` | (Re)creates the roots from the downloads. Idempotent: fetches once, verifies sha256, re-extracts, rebuilds each root from scratch |
| `run.sh` | Starts a server in the background (`run.sh linux\|win\|linux64 [--map M] [--bots N] [--port P] [--fg]`) |
| `stop.sh` | Stops that root's server (exact process name + cwd match; `wineserver -k` only on the private prefix) |
| `rcon.py` | GoldSrc rcon client; prints the redirected console output |
| `plugins/*.sma` | Test plugins (compiled and installed by setup.sh) |
| `evidence/` | Logs from the first runs (pdata, hamsandwich, Windows crash record; its minidump isn't in git, it's in `~/dev/hl/ref/amxx-testenv-crashdump/`) |

## Downloads (verified official sources)

Each download is in its own directory under `~/dev/hl/ref/downloads/`; setup.sh extracts them
into `~/dev/hl/ref/extracted/<name>/` after checking that no member path is absolute or has `..`.

| Package | Version | URL | sha256 |
|---|---|---|---|
| AMX Mod X base, Linux | 1.10.0-git5487 (`amxmodx-latest-base-linux` on 2026-10-12) | https://www.amxmodx.org/amxxdrop/1.10/amxmodx-1.10.0-git5487-base-linux.tar.gz | `d82d1d65c907f358c48bdebc07e20084e7e8c4f4d0e95af275e8b43f32815c7e` |
| AMX Mod X base, Windows | 1.10.0-git5487 | https://www.amxmodx.org/amxxdrop/1.10/amxmodx-1.10.0-git5487-base-windows.zip | `ca13b474741f5f0b035507969cb853b7eac9052614402114801e21c4dc2f2ebd` |
| Metamod-R (rehlds org) | 1.3.0.149 (latest release) | https://github.com/rehlds/Metamod-R/releases/download/1.3.0.149/metamod-bin-1.3.0.149.zip | `ede7f59c4e0220afe8c02aa348a130cce527f87d36ffdb674e37a501ce57be94` |
| metamod-p, Linux | v1.21p109 | https://github.com/Bots-United/metamod-p/releases/download/v1.21p109/metamod-p-v1.21p109-linux_ubuntu1804.tar.xz | `3b77d804cd5687ee18a8535ec02d085e42c9d0da1c12a0683c6aeb25e88d3e1e` |
| metamod-p, win32 | v1.21p109 | https://github.com/Bots-United/metamod-p/releases/download/v1.21p109/metamod-p-v1.21p109-win32.tar.xz | `564838d9a42032ee3bc44eeb2616896e0789c3ce8d7a033d81f3f795b67e31ed` |
| buildchain drop-in, linux-amd64 | v1.0.9 | https://github.com/goldsrc-net/buildchain/releases/download/v1.0.9/hlds-dropin-linux-amd64.zip | `9845e1a9f58efd95dfe8f784588ea523b082548f7c9e5ceca70ffe705a1d070f` |
| ReHLDS (already on disk) | 3.15.0.896 | `~/games/rehlds_release/rehlds-bin-3.15.0.896.zip` (github.com/rehlds/ReHLDS release) | `997baeb7ef3842dab3e034d82dc651ebfe560c23b158adce660a6b97976b4e2b` |

`github.com/jkivilin/metamod-p` now redirects to `github.com/Bots-United/metamod-p`; v1.21p109 is
the latest release there (it is p38+).

### Which metamod: Metamod-R (default)

Both load on ReHLDS with the port and run AMXX, Fun, Engine and FakeMeta (`meta list`: all RUN).
setup.sh installs Metamod-R by default because:

* it is the rehlds org's metamod, built for and tested with ReHLDS (the engine here);
* it ships both `metamod_i386.so` and `metamod.dll` in one zip, with a `config.ini` that takes a
  `gamedll` override (it also knows `ts` -> `ts_i386.so`/`mp.dll` itself);
* it is what ReHLDS/ReGameDLL server operators use with AMXX 1.10.

`MM=metamod-p ./setup.sh linux` installs metamod-p v1.21p109 instead (also checked: `meta version`
"Metamod v1.21p109 ... Patch: Metamod-P (mm-p) v109", AMXX + 3 modules RUN, 21 plugins running).

## Root layout (built by setup.sh)

```
~/games/amxx_rehlds_linux/
  hlds_linux engine_i486.so filesystem_stdio.so core.so proxy.so demoplayer.so hltv
                       <- real copies of the ReHLDS 3.15.0.896 release linux32 binaries
  valve/dlls/director.so  <- ReHLDS release copy
  *.so, valve/ ...     <- hardlinks (cp -al) of ~/games/hlds_linux (steam_legacy HLDS)
                          minus ts/ cstrike/ steamapps/ linux64/ and logs; every
                          .cfg/.txt/.ini/.vdf/.hpk/.dat/.lst/.gam/.inf/.dt/.rc is a private copy
  ts/                  <- fresh, like `cargo xtask install`:
    maps models sound sprites gfx events logos overviews resource, *.wad *.tga *.bmp ...
                       -> symlinks into ~/dev/hl/ts_custom
    *.cfg *.txt *.rc   <- copies from ts_custom
    liblist.gam delta.lst gameinfo.txt dlls/ cl_dlls/  <- copied from the port's
                          dist/linux-i686/ts (`cargo xtask --release dist`)
    liblist.gam        <- gamedll_linux "addons/metamod/metamod_i386.so"
    addons/metamod/metamod_i386.so, config.ini (+ "gamedll dlls/ts_i386.so"), plugins.ini
    addons/amxmodx/    <- AMXX base package; configs/modules.ini enables fun, engine, fakemeta;
                          configs/plugins.ini = stock plugins + the test plugins
~/games/amxx_rehlds_win/   same idea from ~/games/hlds_win; ReHLDS win32 swds.dll, hlds.exe,
                          FileSystem_Stdio.dll, ...; liblist gamedll "addons\metamod\metamod.dll";
                          config.ini "gamedll dlls/mp.dll"; AMXX Windows package (*.dll)
```

Disk: 60 MB (linux) / 48 MB (win) beyond the hardlinked originals, plus 384 MB for the Wine prefix.

Rebuild after a new port build: `cargo xtask --release dist` in the port repo, then
`./setup.sh linux` (or `win`, or both). setup.sh refuses to rebuild a root while its server runs.
Pass `KEEP_LOGS=1` to keep `ts/addons/amxmodx/logs` and `ts/logs` across the rebuild, and
`ENABLE_PLUGINS="amxx_test pdata_test"` to choose which test plugins are active in plugins.ini
(the rest are listed commented; default: `amxx_test`).

## Running

```sh
cd ~/dev/hl/ref/amxx-testenv       # or docker-tsmod/amxx-testenv
./run.sh linux                       # ts_dojo, 4 quota bots, port 27315, background
./run.sh win                         # same under Wine, port 27316 (Wine needs ~5 s to come up)
./run.sh linux --map ts_awaken --bots 2 --fg   # foreground, console on the terminal (linux)
python3 -I rcon.py meta list         # --port 27316 for win
python3 -I rcon.py amxx modules
python3 -I rcon.py amxx plugins
python3 -I rcon.py status
./stop.sh linux ; ./stop.sh win
```

The underlying commands (what run.sh executes, from the root dir):

```sh
# linux
LD_LIBRARY_PATH=$PWD ./hlds_linux -condebug -game ts -port 27315 +maxplayers 8 +sv_lan 1 \
    +ts_bot_quota 4 +servercfgfile amxx_server.cfg +map ts_dojo
# win
WINEPREFIX=~/games/wineprefix_amxx WINEDEBUG=-all wine hlds.exe -console -condebug -game ts \
    -port 27316 +maxplayers 8 +sv_lan 1 +ts_bot_quota 4 +servercfgfile amxx_server.cfg +map ts_dojo
```

run.sh writes `ts/amxx_server.cfg` (`exec server.cfg`, `rcon_password amxxtest`, `log on`,
`ts_bot_quota N`): game cvars must be set from the server config because GoldSrc runs
command-line `+cvar`s before GameInit (same as xtask). rcon password: `amxxtest`.

Stopping: `stop.sh` kills only `hlds_linux` / `hlds.exe` processes whose cwd is that root, found
with `pgrep -x`. Never use `pkill -f <pattern>`: the pattern also matches your own shell's command
line. Never `wineserver -k` without `WINEPREFIX=~/games/wineprefix_amxx`: the default/shared
prefix belongs to xtask's Windows roots.

## Logs

| What | Linux root | Win root |
|---|---|---|
| Server stdout/stderr (run.sh) | `server-stdout.log` | `server-stdout.log` (empty with `WINEDEBUG=-all`; Wine messages only) |
| Engine console (`-condebug`) | `ts/qconsole.log` | `qconsole.log` (root dir) |
| HL game log (`log on`) | `ts/logs/L*.log` (buffered: complete after the server stops) | `ts/logs/L*.log` |
| AMXX log (errors, admin actions) | `ts/addons/amxmodx/logs/L<date>.log` | same |
| AMXX runtime errors | `ts/addons/amxmodx/logs/error_<date>.log` (only when there are any) | same |
| `log_to_file` from plugins | `ts/addons/amxmodx/logs/<name>.log` | same |
| Crash minidump | - | `hlds_3.15.0.896-*_crash_*.mdmp` (breakpad, root dir) |

Expected, harmless lines in the AMXX log: `GameConfig CRC mismatch for game "*" ... library
"engine"` (AMXX's engine signatures vs. ReHLDS 3.15) and `[FAKEMETA] get/set_gamerules_* natives
have been disabled because g_pGameRules address could not be found` (the port has no
`g_pGameRules` symbol). On Windows, plugins marked `debug` in plugins.ini log
`performance issue. Function ... executed more than N ms` (log_to_file is slow under Wine).

## Installing a module or plugin

* Module (Linux): copy `<name>_amxx_i386.so` to `ts/addons/amxmodx/modules/`; Windows:
  `<name>_amxx.dll`. Add the name without suffix (e.g. `tsx`, `tsfun`) on its own line in
  `ts/addons/amxmodx/configs/modules.ini` (or let a plugin's `#pragma reqlib`/`AUTOLOAD`
  load it). Check with `rcon.py amxx modules` / `meta list`.
* Plugin: copy `<name>.amxx` to `ts/addons/amxmodx/plugins/` and add `<name>.amxx` (append
  ` debug` for line-numbered stack traces) to `ts/addons/amxmodx/configs/plugins.ini`. Then
  change map or restart; check `rcon.py amxx plugins`.
* setup.sh rebuilds the roots from scratch: put permanent test plugins in `plugins/*.sma` here
  (compiled on every setup run), or re-copy modules after setup.

## Compiling plugins (amxxpc)

The Linux package's compiler is a 32-bit ELF that dlopens `amxxpc32.so` by bare name, so it
needs its own directory on `LD_LIBRARY_PATH` (only lib32-glibc is required; `ldd` is clean):

```sh
S=~/dev/hl/ref/extracted/amxmodx-1.10.0-git5487-linux/addons/amxmodx/scripting
LD_LIBRARY_PATH=$S $S/amxxpc plugins/amxx_test.sma -i$S/include -o/tmp/amxx_test.amxx
```

The `.amxx` output works on both roots. `$S/include` has `tsx.inc`, `tsfun.inc`, `tsconst.inc`,
`tsstats.inc` (the AMXX TS addon's natives) for tsx/tsfun plugins.

## Test plugins and results (2026-10-12, port dist of 2026-10-12 02:11)

* `amxx_test.sma`: logs `plugin_init`, `plugin_cfg`, `client_putinserver`, `DeathMsg`; every
  10 s probes each player with `entity_get_vector(EV_VEC_origin)`, `get_user_health`,
  `get_user_frags`, and once `set_user_health(id, 123)` + read back. Server command
  `amxx_test_probe`. Result, both roots: bots get putinserver, set/get health = 123, origins
  sane, DeathMsg kills keep coming (19 kills in ~2 min on Linux). Linux AMXX formats
  `EV_FL_health` 123.0 as `122.9` with `%.1f`; the value is 123 (`get_user_health`=123, and
  Windows prints 123.0): an AMXX float formatting quirk, not the game.
* Stock admin plugins: all 20 load and run with no errors (`amx_who`, `amx_cvar`, `amx_help`,
  `amx_say`, `amx_kick` checked over rcon; the bot quota refills after `amx_kick`).
* `pdata_test.sma` (fakemeta `get_pdata_int(id, 100)` on every player, 20 s after map start, or
  server command `pdata_test`): **no crash, returns garbage** on both roots. The port's private
  data is an 8-byte generational slab handle (`crates/goldsrc/src/edict.rs`); offset 100
  (+5 dwords linuxdiff on Linux: byte 420) reads unrelated heap. Linux values for ids 1-4:
  `-392292992 (0xe89e1580)`, `2`, `346`, `0`; Windows: `0x5008e9c8`, `0x6c0064`, `0x74616d68`
  ("hmat"), `0x74616d68`. `get_pdata_int(id, 0, 0, 0)` = `203..206`: the slab index.
  `pev_valid(id)` = 2 (fakemeta sees private data).
* `ham_test.sma` (`RegisterHam(Ham_Spawn, "player", ...)` in plugin_init). AMXX's TS gamedata
  (`data/gamedata/common.games/virtual.games/ts/offsets-common.txt`) puts the vtable pointer at
  `base` = 0x60 on Linux, 0x0 on Windows, Ham_Spawn slot linux 9 / windows 7. Hamsandwich
  creates a temporary `player` (the port exports `player`) and reads `*(pdata + base)`:
  * Linux: reads 88 bytes past the 8-byte block, which happened to be 0, so it fails cleanly:
    `[HAMSANDWICH] Failed to retrieve vtable for "player", hook for "fw_spawn_post" not active.`
    then `Run time error 10: native error (native "RegisterHam")`; the server keeps running.
    This is luck: a nonzero heap word there would be used as a vtable and patched.
  * Windows: **server crash** inside RegisterHam. Wine `+seh`:
    `EXCEPTION_ACCESS_VIOLATION ... info[1]=00000000000000E7` with `edx=0xcb`: the slab index
    203 (0xCB, word 0 of the private data) taken as the vtable, slot 7 read at 0xCB+7*4 = 0xE7.
    Breakpad writes a minidump and the process exits; nothing in the AMXX logs after
    `calling RegisterHam`. Evidence in `evidence/win-ham/`.

## Pitfalls hit

1. `amxxpc` fails with `compiler failed to instantiate: amxxpc32.so: cannot open shared object
   file` unless its directory is on `LD_LIBRARY_PATH` (it dlopens the bare name).
2. ReHLDS writes `-condebug`'s `qconsole.log` into `ts/` on Linux but into the root dir on
   Windows (the xtask Linux root behaves the same: `~/games/hlds_linux/ts/qconsole.log`).
3. The HL game log (`ts/logs/L*.log`) is buffered: kill/`entered the game` lines appear only when
   the file is closed (stop or map change). The server also opens two log files per start
   (`Executing server.cfg` appears twice per start, the second time after AMXX's `amxx.cfg`;
   cause not investigated), the first holding just "Log file started/closed".
4. Hardlinked roots: the engine writes `steam_appid.txt` (and could write cfgs, `banned.cfg`,
   `listip.cfg`, `custom.hpk`) in place, which would change the original root's file too. setup.sh
   gives every such text file its own inode and installs binaries as real copies (rm, then cp).
   Verified: no file modified during a run has a link count > 1.
5. Wine: xtask runs `wineserver -k` on `~/games/wineprefix` after Windows checks, which would
   kill this env's server too; hence the private prefix `~/games/wineprefix_amxx` (created by
   setup.sh with `wineboot --init`, Mono/Gecko disabled).
6. Wine + Steam breakpad: Windows crashes don't show a dialog or Wine backtrace; the breakpad
   handler writes `hlds_*_crash_*.mdmp` in the root and exits. Use
   `WINEDEBUG=+seh,-dbghelp,-dbghelp_dwarf ./run.sh win` to get the exception record
   (code, faulting address, registers) in `server-stdout.log`. Plain `WINEDEBUG=err+seh` is
   buried in dbghelp DWARF `fixme` lines (the MinGW mp.dll has DWARF).
7. `run.sh win` returns before `hlds.exe` exists (Wine startup): poll with rcon
   (`rcon.py --timeout 1 status`) rather than `pgrep` right after starting.
8. hlds_linux runs fine with stdin at /dev/null; send console commands with rcon (the Wine
   console doesn't read piped stdin either).
9. The ReHLDS release `hlds_linux` prints `[S_API FAIL] SteamAPI_Init() failed` (no Steam client
   running): harmless, same as the xtask roots. It needs `~/.steam/sdk32/steamclient.so`
   (validation.md §1.1), already present.
10. `jkivilin/metamod-p` moved to `Bots-United/metamod-p` (GitHub redirect); use the new URLs.
