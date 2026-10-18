#!/usr/bin/env bash
# Starts a dedicated TS server with metamod + AMXX in one of the amxx test roots, in the
# background. Usage:
#   run.sh linux|win|linux64 [--map ts_dojo] [--bots 4] [--port 27315|27316|27317] [--fg]
# Output: <root>/server-stdout.log (stdout/stderr), <root>/qconsole.log (-condebug),
#         <root>/ts/logs/L*.log (log on), <root>/ts/addons/amxmodx/logs/*.log.
# rcon password: amxxtest (rcon.py --port P meta list).
# Stop: stop.sh linux|win|linux64
set -euo pipefail
os=${1:?usage: run.sh linux|win|linux64 [--map M] [--bots N] [--port P] [--fg]}; shift
map=ts_dojo bots=4 fg=0
case $os in
  linux) root=$HOME/games/amxx_rehlds_linux; port=27315 ;;
  win)   root=$HOME/games/amxx_rehlds_win;   port=27316 ;;
  linux64) root=$HOME/games/amxx_rehlds_linux64; port=27317 ;;
  *) echo "unknown root $os" >&2; exit 1 ;;
esac
while [[ $# -gt 0 ]]; do
  case $1 in
    --map) map=$2; shift 2 ;;
    --bots) bots=$2; shift 2 ;;
    --port) port=$2; shift 2 ;;
    --fg) fg=1; shift ;;
    *) echo "unknown option $1" >&2; exit 1 ;;
  esac
done
[[ -d $root/ts ]] || { echo "$root missing: run setup.sh $os" >&2; exit 1; }
# Game cvars must come from the server config: GoldSrc runs command-line +cvars before GameInit.
cat >"$root/ts/amxx_server.cfg" <<EOF
// Written by amxx-testenv/run.sh
exec server.cfg
rcon_password amxxtest
log on
mp_logecho 0
ts_bot_quota $bots
EOF
rm -f "$root/qconsole.log"
args=(-game ts -port "$port" +maxplayers 8 +sv_lan 1 +ts_bot_quota "$bots" +servercfgfile amxx_server.cfg +map "$map")
cd "$root"
if [[ $os == linux* ]]; then
  cmd=(env LD_LIBRARY_PATH="$root" ./hlds_linux -condebug "${args[@]}")
else
  export WINEPREFIX=${AMXX_WINEPREFIX:-$HOME/games/wineprefix_amxx} WINEDEBUG=${WINEDEBUG--all}
  cmd=(wine hlds.exe -console -condebug "${args[@]}")
fi
if [[ $fg == 1 ]]; then exec "${cmd[@]}"; fi
# stdin from /dev/null: hlds_linux's console then sees EOF; it keeps running (commands via rcon).
nohup "${cmd[@]}" </dev/null >"$root/server-stdout.log" 2>&1 &
echo "$!" >"$root/server.pid"
echo "started $os server pid $! on port $port (map $map, $bots bots); log $root/server-stdout.log"
