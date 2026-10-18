#!/usr/bin/env bash
# Recreates the AMX Mod X + metamod test roots for the TS Rust port:
#   ~/games/amxx_rehlds_linux  (ReHLDS 3.15 linux32, primary)
#   ~/games/amxx_rehlds_win    (ReHLDS 3.15 win32 under Wine, secondary)
#   ~/games/amxx_rehlds_linux64 (goldsrc-net/buildchain's 64-bit ReHLDS, Metamod-R and AMX Mod X)
#
# Idempotent: downloads are fetched once (sha256-pinned), extracted fresh, and each root is
# rebuilt from scratch every run (logs in the roots are lost; pass KEEP_LOGS=1 to keep
# ts/addons/amxmodx/logs and ts/logs).
#
# Engine files are hardlinked (cp -al) from the xtask roots ~/games/hlds_linux / hlds_win, which
# are never written to. Every small text file the engine may rewrite is copied (link broken),
# and the ReHLDS release binaries are real copies, so nothing written in the new roots can reach
# the originals.
#
# Usage: setup.sh [linux] [win] [linux64]   (default: linux win)
# Env:   MM=metamod-r (default) | metamod-p     which metamod to install
#        PORT_REPO, TS_DIR, GAMES               override paths
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REF=${REF:-$HOME/dev/hl/ref}
DL=$REF/downloads
EX=$REF/extracted
GAMES=${GAMES:-$HOME/games}
PORT_REPO=${PORT_REPO:-$HOME/dev/hl/rust-hlmod-the-specialists}
TS_DIR=${TS_DIR:-$HOME/dev/hl/ts_custom}
MM=${MM:-metamod-r}
AMXX_VER=1.10.0-git5487
MMR_VER=1.3.0.149
MMP_VER=1.21p109
BUILDCHAIN_VER=v1.0.9

# name|url|sha256
DOWNLOADS=(
  "amxmodx-$AMXX_VER-linux|https://www.amxmodx.org/amxxdrop/1.10/amxmodx-$AMXX_VER-base-linux.tar.gz|d82d1d65c907f358c48bdebc07e20084e7e8c4f4d0e95af275e8b43f32815c7e"
  "amxmodx-$AMXX_VER-windows|https://www.amxmodx.org/amxxdrop/1.10/amxmodx-$AMXX_VER-base-windows.zip|ca13b474741f5f0b035507969cb853b7eac9052614402114801e21c4dc2f2ebd"
  "metamod-r-$MMR_VER|https://github.com/rehlds/Metamod-R/releases/download/$MMR_VER/metamod-bin-$MMR_VER.zip|ede7f59c4e0220afe8c02aa348a130cce527f87d36ffdb674e37a501ce57be94"
  "metamod-p-$MMP_VER-linux|https://github.com/Bots-United/metamod-p/releases/download/v$MMP_VER/metamod-p-v$MMP_VER-linux_ubuntu1804.tar.xz|3b77d804cd5687ee18a8535ec02d085e42c9d0da1c12a0683c6aeb25e88d3e1e"
  "metamod-p-$MMP_VER-win32|https://github.com/Bots-United/metamod-p/releases/download/v$MMP_VER/metamod-p-v$MMP_VER-win32.tar.xz|564838d9a42032ee3bc44eeb2616896e0789c3ce8d7a033d81f3f795b67e31ed"
  "buildchain-$BUILDCHAIN_VER-linux-amd64|https://github.com/goldsrc-net/buildchain/releases/download/$BUILDCHAIN_VER/hlds-dropin-linux-amd64.zip|9845e1a9f58efd95dfe8f784588ea523b082548f7c9e5ceca70ffe705a1d070f"
)
REHLDS_ZIP=$GAMES/rehlds_release/rehlds-bin-3.15.0.896.zip
REHLDS_SHA=997baeb7ef3842dab3e034d82dc651ebfe560c23b158adce660a6b97976b4e2b

say() { printf '== %s\n' "$*"; }
die() { printf 'setup.sh: %s\n' "$*" >&2; exit 1; }

fetch_and_extract() {
  local spec name url sha file
  for spec in "${DOWNLOADS[@]}"; do
    IFS='|' read -r name url sha <<<"$spec"
    file=$DL/$name/${url##*/}
    if [[ ! -f $file ]]; then
      mkdir -p "$DL/$name"
      [[ -z $(ls -A "$DL/$name") ]] || die "$DL/$name is not empty but lacks ${url##*/}"
      say "download $url"
      curl -fsSL --max-time 600 -o "$file" "$url"
    fi
    echo "$sha  $file" | sha256sum -c --quiet - || die "sha256 mismatch: $file"
    # Reject absolute or parent-relative member paths before extracting.
    case $file in
      *.zip) ! unzip -Z1 "$file" | grep -qE '^/|(^|/)\.\.(/|$)' || die "unsafe paths in $file" ;;
      *)     ! tar tf "$file" | grep -qE '^/|(^|/)\.\.(/|$)' || die "unsafe paths in $file" ;;
    esac
    rm -rf "${EX:?}/$name"; mkdir -p "$EX/$name"
    case $file in
      *.zip) unzip -q "$file" -d "$EX/$name" ;;
      *)     tar xf "$file" -C "$EX/$name" --no-same-owner ;;
    esac
  done
  echo "$REHLDS_SHA  $REHLDS_ZIP" | sha256sum -c --quiet - || die "sha256 mismatch: $REHLDS_ZIP"
  rm -rf "$EX/rehlds-3.15.0.896"; mkdir -p "$EX/rehlds-3.15.0.896"
  unzip -q "$REHLDS_ZIP" 'bin/*' -d "$EX/rehlds-3.15.0.896"
}

# Replace a (possibly hardlinked) file with a private copy.
unlink_copy() { local f; for f; do cp -p "$f" "$f.amxx-tmp" && mv -f "$f.amxx-tmp" "$f"; done; }
# Install a real copy (remove first: never write through a hardlink).
put() { mkdir -p "$(dirname "$2")"; rm -f "$2"; cp "$1" "$2"; }

build_root() {
  local os=$1 src dest plat
  case $os in
    linux)   src=$GAMES/hlds_linux; dest=$GAMES/amxx_rehlds_linux;   plat=linux-i686 ;;
    win)     src=$GAMES/hlds_win;   dest=$GAMES/amxx_rehlds_win;     plat=windows-i686 ;;
    linux64) src=$GAMES/hlds_linux; dest=$GAMES/amxx_rehlds_linux64; plat=linux-x86_64 ;;
  esac
  case $dest in "$GAMES"/amxx_rehlds_linux|"$GAMES"/amxx_rehlds_win|"$GAMES"/amxx_rehlds_linux64) ;; *) die "refusing $dest" ;; esac
  [[ -d $src ]] || die "$src missing"
  [[ -f $PORT_REPO/dist/$plat/ts/liblist.gam ]] || die "no $PORT_REPO/dist/$plat (run: cargo xtask --release dist)"
  if pgrep -x hlds_linux >/dev/null || pgrep -x hlds.exe >/dev/null; then
    for p in $(pgrep -x hlds_linux; pgrep -x hlds.exe); do
      [[ $(readlink -f /proc/$p/cwd 2>/dev/null) == "$dest"* ]] && die "a server is running in $dest (pid $p): stop it first"
    done
  fi

  local keep=""
  if [[ ${KEEP_LOGS:-0} == 1 && -d $dest/ts ]]; then
    keep=$(mktemp -d)
    [[ -d $dest/ts/addons/amxmodx/logs ]] && cp -a "$dest/ts/addons/amxmodx/logs" "$keep/amxx"
    [[ -d $dest/ts/logs ]] && cp -a "$dest/ts/logs" "$keep/ts"
  fi
  say "$os: rebuild $dest from $src"
  rm -rf "$dest"; mkdir -p "$dest"

  # 1. Engine: hardlinks, minus the game dir, other mods, Steam metadata and 64-bit bits.
  local e n
  for e in "$src"/*; do
    n=${e##*/}
    case $n in ts|cstrike|steamapps|linux64|logs|qconsole.log|appcache|config|*.log|core|core.*) continue ;; esac
    cp -al "$e" "$dest/"
  done
  # Anything the engine may rewrite gets its own inode.
  find "$dest" -type f \( -iname '*.cfg' -o -iname '*.txt' -o -iname '*.log' -o -iname '*.ini' \
      -o -iname '*.vdf' -o -iname '*.hpk' -o -iname '*.dat' -o -iname '*.lst' -o -iname '*.gam' \
      -o -iname '*.inf' -o -iname '*.dt' -o -iname '*.rc' \) -print0 \
    | while IFS= read -r -d '' f; do unlink_copy "$f"; done

  # 2. ReHLDS 3.15.0.896 release binaries (real copies); for linux64 the drop-in's 64-bit engine,
  # with steamcmd's 64-bit steamclient.so (the drop-in's is the desktop client's, which needs X11).
  local rb=$EX/rehlds-3.15.0.896/bin bc=$EX/buildchain-$BUILDCHAIN_VER-linux-amd64
  if [[ $os == linux64 ]]; then
    for f in "$bc"/*.so "$bc/hlds_linux" "$bc/hltv"; do
      n=${f##*/}; [[ $n == steamclient.so ]] && continue; put "$f" "$dest/$n"
    done
    put "$src/linux64/steamclient.so" "$dest/steamclient.so"
    put "$bc/valve/dlls/director.so" "$dest/valve/dlls/director.so"
    chmod +x "$dest/hlds_linux" "$dest/hltv"
  elif [[ $os == linux ]]; then
    for f in engine_i486.so hlds_linux filesystem_stdio.so core.so proxy.so demoplayer.so hltv; do put "$rb/linux32/$f" "$dest/$f"; done
    put "$rb/linux32/valve/dlls/director.so" "$dest/valve/dlls/director.so"
    chmod +x "$dest/hlds_linux" "$dest/hltv"
  else
    for f in swds.dll hlds.exe core.dll proxy.dll demoplayer.dll hltv.exe; do put "$rb/win32/$f" "$dest/$f"; done
    put "$rb/win32/filesystem_stdio.dll" "$dest/FileSystem_Stdio.dll"
    put "$rb/win32/valve/dlls/director.dll" "$dest/valve/dlls/director.dll"
  fi

  # 3. Fresh ts/: TS content links (as xtask's link_ts_content), then the port's dist output.
  local ts=$dest/ts ext lname
  mkdir -p "$ts"
  for e in "$TS_DIR"/*; do
    n=${e##*/}; lname=${n,,}; ext=${lname##*.}; [[ $lname == *.* ]] || ext=""
    if [[ -d $e ]]; then
      case $lname in events|gfx|logos|maps|models|overviews|resource|sound|sprites) ln -s "$e" "$ts/$n" ;; esac
    else
      case $ext in
        wad|tga|bmp|tsa|scr|ico|res) ln -s "$e" "$ts/$n" ;;
        cfg|txt|rc) cp "$e" "$ts/$n" ;;
      esac
    fi
  done
  cp -r "$PORT_REPO/dist/$plat/ts/." "$ts/"
  local gamedll
  case $os in linux) gamedll=dlls/ts_i386.so ;; linux64) gamedll=dlls/ts_amd64.so ;; *) gamedll=dlls/mp.dll ;; esac

  # 4. metamod.
  local mmdir=$ts/addons/metamod mmlib
  mkdir -p "$mmdir/dlls"
  if [[ $os == linux64 ]]; then
    mmlib=addons/metamod/metamod_amd64.so
    cp "$bc/valve/addons/metamod/dlls/metamod_amd64.so" "$ts/$mmlib"
    cp "$bc/valve/addons/metamod/config.ini" "$mmdir/config.ini"
  elif [[ $MM == metamod-r ]]; then
    if [[ $os == linux ]]; then mmlib=addons/metamod/metamod_i386.so; else mmlib=addons/metamod/metamod.dll; fi
    cp "$EX/metamod-r-$MMR_VER/$mmlib" "$ts/$mmlib"
    cp "$EX/metamod-r-$MMR_VER/addons/metamod/config.ini" "$mmdir/config.ini"
  else
    if [[ $os == linux ]]; then
      mmlib=addons/metamod/dlls/metamod.so; cp "$EX/metamod-p-$MMP_VER-linux/$mmlib" "$ts/$mmlib"
    else
      mmlib=addons/metamod/dlls/metamod.dll; cp "$EX/metamod-p-$MMP_VER-win32/$mmlib" "$ts/$mmlib"
    fi
    : >"$mmdir/config.ini"
  fi
  # The real game library (metamod-r also knows "ts", but be explicit).
  printf '\n// Added by amxx-testenv/setup.sh\ngamedll %s\n' "$gamedll" >>"$mmdir/config.ini"
  cat >"$mmdir/plugins.ini" <<'EOF'
; metamod plugins (amxx-testenv/setup.sh)
linux addons/amxmodx/dlls/amxmodx_mm_i386.so
win32 addons\amxmodx\dlls\amxmodx_mm.dll
EOF
  [[ $os == linux64 ]] && sed -i 's|amxmodx_mm_i386\.so|amxmodx_mm_amd64.so|' "$mmdir/plugins.ini"
  # liblist.gam: point the engine at metamod.
  if [[ $os == linux* ]]; then
    sed -i "s|^gamedll_linux .*|gamedll_linux \"$mmlib\"|" "$ts/liblist.gam"
  else
    sed -i "s|^gamedll .*|gamedll \"${mmlib//\//\\\\}\"|" "$ts/liblist.gam"
  fi

  # 5. AMX Mod X.
  local apkg
  case $os in
    linux) apkg=$EX/amxmodx-$AMXX_VER-linux ;; linux64) apkg=$bc/valve ;; *) apkg=$EX/amxmodx-$AMXX_VER-windows ;;
  esac
  cp -r "$apkg/addons/amxmodx" "$ts/addons/"
  sed -i 's/^;\(fun\|engine\|fakemeta\)\b/\1/' "$ts/addons/amxmodx/configs/modules.ini"
  grep -qE '^(fun|engine|fakemeta)' "$ts/addons/amxmodx/configs/modules.ini" \
    || printf 'fun\nengine\nfakemeta\n' >>"$ts/addons/amxmodx/configs/modules.ini"
  # Test plugins: compile with the linux amxxpc (the .amxx bytecode is platform independent).
  local sc=$EX/amxmodx-$AMXX_VER-linux/addons/amxmodx/scripting p
  {
    printf '\n; amxx-testenv test plugins\n'
    for p in "$HERE"/plugins/*.sma; do
      [[ -e $p ]] || continue
      n=$(basename "$p" .sma)
      LD_LIBRARY_PATH=$sc "$sc/amxxpc" "$p" -i"$sc/include" -o"$ts/addons/amxmodx/plugins/$n.amxx" >"$EX/amxxpc-$n.log" 2>&1 \
        || { cat "$EX/amxxpc-$n.log" >&2; die "amxxpc failed on $p"; }
      # ENABLE_PLUGINS (space separated names) selects which are active; the rest are listed commented.
      if [[ " ${ENABLE_PLUGINS:-amxx_test} " == *" $n "* ]]; then echo "$n.amxx debug"; else echo ";$n.amxx debug"; fi
    done
  } >>"$ts/addons/amxmodx/configs/plugins.ini"

  if [[ -n $keep ]]; then
    [[ -d $keep/amxx ]] && cp -a "$keep/amxx/." "$ts/addons/amxmodx/logs/"
    [[ -d $keep/ts ]] && mkdir -p "$ts/logs" && cp -a "$keep/ts/." "$ts/logs/"
    rm -rf "$keep"
  fi
  du -sh --apparent-size "$dest" | sed 's/^/   apparent size /'
  du -sh "$dest" | sed 's/^/   (du, hardlinks to the source count once per tree) /'
}

roots=("$@"); [[ ${#roots[@]} -gt 0 ]] || roots=(linux win)
fetch_and_extract
for r in "${roots[@]}"; do
  case $r in linux|win|linux64) build_root "$r" ;; *) die "unknown root $r (linux|win|linux64)" ;; esac
done
if [[ " ${roots[*]} " == *" win "* ]]; then
  WP=${AMXX_WINEPREFIX:-$GAMES/wineprefix_amxx}
  if [[ ! -f $WP/system.reg ]]; then
    say "create Wine prefix $WP (own prefix: xtask runs 'wineserver -k' on ~/games/wineprefix)"
    WINEPREFIX=$WP WINEDLLOVERRIDES="mscoree,mshtml=" WINEDEBUG=-all wineboot --init >/dev/null 2>&1
    WINEPREFIX=$WP wineserver -w
  fi
fi
say "done"
