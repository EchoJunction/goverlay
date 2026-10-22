#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
export XDG_CONFIG_HOME="$HOME/.config" XDG_DATA_HOME="$HOME/.local/share"
export XDG_CACHE_HOME="$HOME/.cache" XDG_RUNTIME_DIR=/tmp/prism-runtime-user
mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_RUNTIME_DIR"
children=()
cleanup() {
  for child in "${children[@]}"; do kill "$child" 2>/dev/null || true; done
  wait 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

Xvfb "$DISPLAY" -screen 0 1280x800x24 -nolisten tcp > /tmp/xvfb.log 2>&1 &
children+=("$!")
ready=false
for ((i=0; i<100; i++)); do
  if xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; then ready=true; break; fi
  sleep .1
done
if [[ $ready != true ]]; then echo 'FAIL: Xvfb did not become ready'; exit 1; fi

mode=${1:-smoke}
if [[ $mode == app-tests || $mode == app-desktop ]]; then
  [[ -r /source/goverlay.lpi ]] || { echo 'FAIL: readonly source mount missing'; exit 1; }
  build=$(mktemp -d /build/source.XXXXXXXX)
  # Snapshot only this source repository, without Git metadata/build products.
  tar -C /source --exclude=.git --exclude=tests/prism/runtime \
    --exclude='*.o' --exclude='*.ppu' --exclude='*.or' --exclude='*.compiled' \
    --exclude='*/lib' --exclude='*/backup' --exclude=./goverlay --exclude=./pascube \
    --exclude=./bgmod --exclude=./bgmod-uninstaller --exclude=./bgmod-splash \
    --exclude=./data/bgmod/bgmod --exclude=./data/bgmod/bgmod-uninstaller \
    --exclude=./data/bgmod/bgmod-splash --exclude=./pascube_src/pascube \
    --exclude=./bgmod_splash_src/bgmod-splash \
    --exclude=logic_tests --exclude=gui_tests --exclude=prism_tests -cf - . | tar -C "$build" -xf -
  cd "$build"
  find . -type f \( -name '*.pas' -o -name '*.lpr' -o -name '*.lfm' -o -name '*.lpi' -o -name Makefile \) \
    -print0 | sort -z | xargs -0 sha256sum > /tmp/source-snapshot.sha256
  echo "Source snapshot digest: $(sha256sum /tmp/source-snapshot.sha256 | cut -d' ' -f1)"
  mkdir -p "$build/bin" "$build/lazarus-config"
  printf '#!/usr/bin/env bash\nexec /usr/bin/lazbuild --lazarusdir=/usr/lib/lazarus --pcp=%q "$@"\n' "$build/lazarus-config" > "$build/bin/lazbuild"
  chmod 700 "$build/bin/lazbuild"
  export PATH="$build/bin:$PATH"
  if [[ $mode == app-tests ]]; then
    pacman -Q fpc lazarus qt6pas
    # The existing test runner isolates HOME itself and expects default XDG paths.
    unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME
    make test-prism test-logic
    lazbuild tests/gui/gui_tests.lpi --ws=qt6
    QT_QPA_PLATFORM=offscreen ./tests/gui/gui_tests --suite=TPrismGuiTests
    echo 'PASS: production Prism parser, writer logic, and Prism editor GUI fixture tests in the container.'
    exit 0
  fi
  make goverlay
  ./goverlay > /tmp/goverlay-desktop.log 2>&1 & children+=("$!")
  mode=desktop
fi

case "$mode" in
  smoke)
    echo 'Runtime scope: isolated container, X11/Xvfb, Mesa software rendering; no Minecraft account/game verification.'
    pacman -Q prismlauncher mangohud jre21-openjdk mesa mesa-utils xorg-server-xvfb
    printf 'Browser assets: noVNC 1.6.0; websockify 0.13.0\n'
    prismlauncher --version
    /usr/lib/jvm/java-21-openjdk/bin/java -version 2>&1
    renderer=$(glxinfo -B)
    printf '%s\n' "$renderer"
    if ! grep -Eiq 'llvmpipe|softpipe|software rasterizer' <<< "$renderer"; then
      echo 'FAIL: renderer is not recognized as software'; exit 1
    fi
    for profile in A B; do
      cfg="$HOME/profiles/$profile/MangoHud.conf"
      mkdir -p "$(dirname "$cfg")"
      if [[ $profile == A ]]; then
        printf 'fps\nposition=top-left\nfont_size=18\n' > "$cfg"
      else
        printf 'fps\nframetime\nposition=bottom-right\nfont_size=30\n' > "$cfg"
      fi
      # Bound each probe, inspect only library mappings and the selected config key.
      timeout --kill-after=2 8 bash -c '
        export MANGOHUD_CONFIGFILE="$1"
        mangohud --dlsym glxgears >/tmp/mangohud-probe.log 2>&1 &
        probe=$!
        trap '\''kill "$probe" 2>/dev/null || true; wait "$probe" 2>/dev/null || true'\'' EXIT
        sleep 2
        kill -0 "$probe"
        grep -qi libMangoHud /proc/"$probe"/maps
        tr "\0" "\n" < /proc/"$probe"/environ | grep -Fx "MANGOHUD_CONFIGFILE=$1"
      ' probe "$cfg"
      echo "PASS: MangoHud OpenGL process maps and selector transport for fixture $profile (not visible Minecraft HUD proof)"
    done
    fixture="$HOME/prism-smoke"
    # A blank launcher fixture opens the first-run wizard; no account is seeded.
    set +e
    timeout --kill-after=2 6 prismlauncher --dir "$fixture" >/tmp/prism-startup.log 2>&1
    startup_status=$?
    set -e
    if [[ $startup_status != 124 || ! -d $fixture ]]; then
      echo "FAIL: Prism fixture startup status=$startup_status"; exit 1
    fi
    echo 'PASS: Prism remained alive in isolated first-run startup until bounded termination.'
    echo 'NOT TESTED: licensed Minecraft normal Play, visible A/B HUD, native host, Wayland, Flatpak, production binding/rollback.'
    ;;
  desktop)
    openbox >/tmp/openbox.log 2>&1 & children+=("$!")
    mkdir -p "$HOME/.vnc"
    # Credentials stay in container-owned state, never in arguments or normal logs.
    if [[ ! -s $HOME/.vnc/password ]]; then
      head -c 24 /dev/urandom | base64 > "$HOME/.vnc/password"
    fi
    chmod 600 "$HOME/.vnc/password"
    # x11vnc reads the plaintext password file directly; no command-line password.
    x11vnc -display "$DISPLAY" -rfbport 5900 -localhost -forever -shared \
      -passwdfile "$HOME/.vnc/password" >/tmp/vnc.log 2>&1 & children+=("$!")
    /opt/websockify/run --web /opt/novnc 6080 localhost:5900 >/tmp/websockify.log 2>&1 & children+=("$!")
    prismlauncher --dir "$XDG_DATA_HOME/PrismLauncher" >/tmp/prism-desktop.log 2>&1 & children+=("$!")
    echo 'Desktop started. Retrieve its VNC password using run.sh password. Sign in only through the isolated Prism UI.'
    wait -n "${children[@]}"
    ;;
  *) echo 'Expected smoke, desktop, app-tests or app-desktop' >&2; exit 2 ;;
esac
