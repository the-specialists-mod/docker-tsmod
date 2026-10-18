#!/usr/bin/env bash
# Stops the server started by run.sh in one amxx root (only that root's processes: matched by
# exact process name and working directory, never by pkill -f).
set -uo pipefail
os=${1:?usage: stop.sh linux|win|linux64}
case $os in
  linux) root=$HOME/games/amxx_rehlds_linux; name=hlds_linux ;;
  win)   root=$HOME/games/amxx_rehlds_win;   name=hlds.exe ;;
  linux64) root=$HOME/games/amxx_rehlds_linux64; name=hlds_linux ;;
  *) echo "unknown root $os" >&2; exit 1 ;;
esac
for p in $(pgrep -x "$name"); do
  [[ $(readlink -f /proc/$p/cwd 2>/dev/null) == "$root" ]] && { echo "kill $name pid $p"; kill "$p"; }
done
sleep 1
for p in $(pgrep -x "$name"); do
  [[ $(readlink -f /proc/$p/cwd 2>/dev/null) == "$root" ]] && kill -9 "$p"
done
if [[ $os == win ]]; then
  # Our own prefix only: never `wineserver -k` the shared ~/games/wineprefix xtask uses.
  WINEPREFIX=${AMXX_WINEPREFIX:-$HOME/games/wineprefix_amxx} wineserver -k 2>/dev/null
fi
rm -f "$root/server.pid"
