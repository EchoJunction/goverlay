#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
[[ $(id -u) == 1000 && $HOME == /home/tester && -r /source/goverlay.lpi ]] || { echo 'Unexpected dev identity or source mount'; exit 1; }
export XDG_CONFIG_HOME="$HOME/.config" XDG_DATA_HOME="$HOME/.local/share"
export XDG_CACHE_HOME="$HOME/.cache" XDG_RUNTIME_DIR=/tmp/goverlay-dev-runtime
unset HOST_XDG_CONFIG_HOME HOST_XDG_DATA_HOME
mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_RUNTIME_DIR"
python /dev-tools/dev-seed.py
mode=${1:-desktop}
[[ $mode == build || $mode == test || $mode == desktop ]] || exit 2

snapshot() {
  tar -C /source --exclude=.git --exclude=AGENTS.md --exclude=CLAUDE.md --exclude=tests/prism/runtime \
    --exclude='*.o' --exclude='*.ppu' --exclude='*.or' --exclude='*.compiled' \
    --exclude='*.dbg' --exclude='*.res' --exclude='*.lps' --exclude='*/lib' --exclude='*/backup' \
    --exclude=./goverlay --exclude=./pascube --exclude=./bgmod --exclude=./bgmod-uninstaller \
    --exclude=./bgmod-splash --exclude=./start_goverlay.sh \
    --exclude=./data/bgmod/bgmod --exclude=./data/bgmod/bgmod-uninstaller --exclude=./data/bgmod/bgmod-splash \
    --exclude=./pascube_src/pascube --exclude=./bgmod_splash_src/bgmod-splash \
    --exclude=logic_tests --exclude=gui_tests --exclude=prism_tests -cf - . | tar -C "$1" -xf -
}
harness_manifest() {
  (cd /dev-tools; sha256sum dev.sh dev-entrypoint.sh dev-seed.py dev-compose.yaml dev_probe.lpr dev-check.py dev-transport.py dev-relay.py dev-tunnel.py)
}
source_manifest() {
  (cd "$1"; find . -type f -print0 | sort -z | xargs -0 sha256sum)
}
if [[ $mode == build ]]; then
  [[ ! -e /build/source || -f /build/.goverlay-dev-build-v1 ]] || { echo 'Unrecognized build volume'; exit 1; }
  printf '%s\n' 'synthetic dev build v1' > /build/.goverlay-dev-build-v1
  rm -rf -- /build/source
  mkdir /build/source
  snapshot /build/source
  source_manifest /build/source > /build/source.sha256
else
  [[ -f /build/.goverlay-dev-build-v1 && -x /build/source/goverlay && -f /build/manifest.txt ]] || {
    echo 'Build missing: run make dev-build with this DEV_STATE first.' >&2; exit 1; }
  check=$(mktemp -d /tmp/goverlay-dev-source.XXXXXXXX)
  trap 'rm -rf -- "$check"' EXIT
  snapshot "$check"
  source_manifest "$check" > /tmp/current-source.sha256
  [[ $(sha256sum /build/source.sha256 | cut -d' ' -f1) == $(sha256sum /tmp/current-source.sha256 | cut -d' ' -f1) ]] || { echo 'Source changed: run make dev-build first.' >&2; exit 1; }
  rm -rf -- "$check"
  trap - EXIT
  (cd /build/source; sha256sum -c /build/binary.sha256)
  harness_manifest > /tmp/current-harness.sha256
  [[ $(sha256sum /build/harness.sha256 | cut -d' ' -f1) == $(sha256sum /tmp/current-harness.sha256 | cut -d' ' -f1) ]] || { echo 'Harness changed: run make dev-build first.'; exit 1; }
fi
mkdir -p /build/bin /build/lazarus-config
printf '#!/usr/bin/env bash\nexec /usr/bin/lazbuild --lazarusdir=/usr/lib/lazarus --pcp=/build/lazarus-config "$@"\n' > /build/bin/lazbuild
chmod 700 /build/bin/lazbuild
export PATH="/build/bin:$PATH"
cd /build/source
if [[ $mode == build ]]; then
  make goverlay
  sha256sum goverlay > /build/binary.sha256
  harness_manifest > /build/harness.sha256
  {
    printf 'Source manifest SHA256: '; sha256sum /build/source.sha256 | cut -d' ' -f1
    printf 'Binary SHA256: '; cut -d' ' -f1 /build/binary.sha256
    printf 'Development harness SHA256: '; sha256sum /build/harness.sha256 | cut -d' ' -f1
    pacman -Q fpc lazarus qt6pas
  } > /build/manifest.txt
  cat /build/manifest.txt
  exit 0
fi

children=()
cleanup() {
  for child in "${children[@]}"; do kill "$child" 2>/dev/null || true; done
  wait 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT
Xvfb "$DISPLAY" -screen 0 1280x900x24 -nolisten tcp >/tmp/dev-xvfb.log 2>&1 & children+=("$!")
ready=false
for ((i=0; i<100; i++)); do
  if xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; then ready=true; break; fi
  sleep .1
done
[[ $ready == true ]] || { echo 'Xvfb failed'; exit 1; }
if [[ $mode == test ]]; then
  # Existing tests use their own HOME isolation. The dev probe below then uses
  # the persistent, explicitly marked synthetic dev HOME in two fresh processes.
  (unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME
   make test-prism test-logic
   lazbuild tests/gui/gui_tests.lpi --ws=qt6
   QT_QPA_PLATFORM=offscreen ./tests/gui/gui_tests --suite=TPrismGuiTests)
  cp /dev-tools/dev_probe.lpr tests/gui/dev_probe.lpr
  sed 's/gui_tests/dev_probe/g' tests/gui/gui_tests.lpi > tests/gui/dev_probe.lpi
  lazbuild tests/gui/dev_probe.lpi --ws=qt6
  GOVERLAY_TEST=1 QT_QPA_PLATFORM=offscreen timeout --kill-after=2 90 ./tests/gui/dev_probe write
  GOVERLAY_TEST=1 QT_QPA_PLATFORM=offscreen timeout --kill-after=2 90 ./tests/gui/dev_probe read
  exit 0
fi
openbox >/tmp/dev-openbox.log 2>&1 & children+=("$!")
mkdir -p "$HOME/.vnc"
if [[ ! -s $HOME/.vnc/dev-password ]]; then head -c 24 /dev/urandom | base64 > "$HOME/.vnc/dev-password"; fi
chmod 600 "$HOME/.vnc/dev-password"
x11vnc -display "$DISPLAY" -rfbport 5900 -localhost -forever -shared \
  -passwdfile "$HOME/.vnc/dev-password" >/tmp/dev-vnc.log 2>&1 & children+=("$!")
/opt/websockify/run --web /opt/novnc 6080 localhost:5900 >/tmp/dev-websockify.log 2>&1 & children+=("$!")
./goverlay >/tmp/dev-goverlay.log 2>&1 & children+=("$!")
sleep 1
kill -0 "${children[-1]}"
printf 'ready\n' > /tmp/dev-ready
echo 'Current-source GOverlay started; only synthetic dev HOME is mounted. Prism is not launched.'
wait -n "${children[@]}"
