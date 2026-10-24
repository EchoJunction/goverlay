#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
action=${1:-run}
case "$action" in image|build|run|test|stop|clean|config|status|password|report|check) ;; *)
  echo 'Expected image, build, run, test, stop, clean, config, status, password, report or check' >&2; exit 2;; esac
state_parent=${DEV_STATE_PARENT:-$(cd -- "$here/../../../.." && pwd -P)}
state_parent=$(cd -- "$state_parent" && pwd -P)
state=${DEV_STATE:-}
if [[ -z $state ]]; then
  case "$action" in stop|clean|status|password|report|check) echo 'DEV_STATE is required for this action' >&2; exit 2;; esac
  state=$(mktemp -d "$state_parent/goverlay-prism-runtime.XXXXXXXX")
  printf '%s\n' 'GOverlay disposable Prism engine v1' > "$state/marker"
fi
if [[ ! -d $state || -L $state || -L $state/marker ]]; then
  echo 'Refusing an unrecognized disposable state directory' >&2; exit 2
fi
state=$(cd -- "$state" && pwd -P)
if [[ $(dirname -- "$state") != "$state_parent" || $(basename -- "$state") != goverlay-prism-runtime.* ||
      $(stat -c %u -- "$state") != "$(id -u)" || $(stat -c %a -- "$state") != 700 ||
      $(cat -- "$state/marker" 2>/dev/null) != 'GOverlay disposable Prism engine v1' ]]; then
  echo 'Refusing an unrecognized or non-private disposable engine' >&2; exit 2
fi
for dir in root runroot runtime tmp config dev-reports; do
  [[ ! -L $state/$dir ]] || { echo 'Refusing symlinked engine/report directory' >&2; exit 2; }
  mkdir -p -- "$state/$dir"
done
for file in dev.lock dev-podman config/dev-containers.conf dev-reports/build.txt dev-reports/test.txt dev-reports/manifest.txt dev-reports/boundary.txt dev-reports/check.txt dev-reports/transport.txt dev-reports/image.txt dev-relay.json dev-reports/relay.txt; do
  [[ ! -L $state/$file ]] || { echo 'Refusing symlinked generated dev file' >&2; exit 2; }
done
exec 9>"$state/dev.lock"
flock -n 9 || { echo 'Another dev command is active for this state' >&2; exit 1; }
# Separate generated wrapper/config files: never overwrite research state files.
export XDG_RUNTIME_DIR="$state/runtime"
export CONTAINERS_CONF_OVERRIDE="$state/config/dev-containers.conf"
printf '[engine]\n' > "$CONTAINERS_CONF_OVERRIDE"
podman_bin=$(command -v podman)
printf '#!/usr/bin/env bash\nexec 9>&-\nexec %q --root %q --runroot %q --storage-driver vfs --tmpdir %q "$@"\n' \
  "$podman_bin" "$state/root" "$state/runroot" "$state/tmp" > "$state/dev-podman"
chmod 700 "$state/dev-podman"
export DEV_PROJECT="prism_$(basename -- "$state" | tr -cd 'a-zA-Z0-9_')_dev"
export DEV_PORT=${DEV_PORT:-6081}
[[ $DEV_PORT =~ ^[0-9]+$ && $DEV_PORT -ge 1024 && $DEV_PORT -le 65535 ]] || { echo 'Invalid DEV_PORT' >&2; exit 2; }
compose=(podman-compose --podman-path "$state/dev-podman" -p "$DEV_PROJECT" -f "$here/dev-compose.yaml" --profile dev)
engine=("$state/dev-podman")
printf 'DEV_STATE=%q\nDev project: %s\n' "$state" "$DEV_PROJECT"
container_id() {
  "${engine[@]}" ps --filter "label=com.docker.compose.project=$DEV_PROJECT" \
    --filter "label=com.docker.compose.service=dev-desktop" --format '{{.ID}}'
}
case "$action" in
  config) "${compose[@]}" config ;;
  image)
    export BUILDAH_LAYERS=false
    "${engine[@]}" build --target editor -t localhost/goverlay-prism-editor:test -f "$here/Containerfile" "$here"
    ;;
  build|test)
    if [[ -n $(container_id) ]]; then
      echo 'Stop the dev desktop with make dev-stop before build/test.' >&2; exit 1
    fi
    if ! "${engine[@]}" image exists localhost/goverlay-prism-editor:test; then
      echo 'Editor image missing: reuse this DEV_STATE with make dev-image first (image build needs network).' >&2
      exit 1
    fi
    "${engine[@]}" image inspect localhost/goverlay-prism-editor:test --format 'Image ID: {{.Id}}' | tee "$state/dev-reports/image.txt"
    "${compose[@]}" run --rm --no-deps "dev-$action" | tee "$state/dev-reports/$action.txt"
    ;;
  run)
    if ! "${engine[@]}" image exists localhost/goverlay-prism-editor:test; then
      echo 'Editor image missing: reuse this DEV_STATE with make dev-image, then make dev-build.' >&2; exit 1
    fi
    if ! "${engine[@]}" volume exists "${DEV_PROJECT}_build"; then
      echo 'Build missing: reuse this DEV_STATE with make dev-build first.' >&2; exit 1
    fi
    python3 "$here/dev-relay.py" stop "$state"
    "${compose[@]}" up -d --no-build --force-recreate dev-desktop
    ready=false
    for ((attempt=0; attempt<100; attempt++)); do
      cid=$(container_id)
      [[ -n $cid ]] || break
      if "${engine[@]}" exec "$cid" test -f /tmp/dev-ready 2>/dev/null; then ready=true; break; fi
      sleep .2
    done
    [[ $ready == true ]] || { echo 'Dev desktop failed startup. Run dev-build for this state and inspect the dedicated dev-desktop logs.' >&2; exit 1; }
    nohup setsid python3 "$here/dev-relay.py" serve "$state" "$cid" "$DEV_PORT" </dev/null >"$state/dev-reports/relay.txt" 2>&1 9>&- &
    relay_pid=$!
    for ((attempt=0; attempt<50; attempt++)); do
      [[ -f $state/dev-relay.json ]] && break
      kill -0 "$relay_pid" 2>/dev/null || { echo 'Loopback relay failed; existing listener was left untouched. See private relay report.' >&2; exit 1; }
      sleep .1
    done
    [[ -f $state/dev-relay.json ]] || { echo 'Relay readiness timeout' >&2; exit 1; }
    printf 'Open http://127.0.0.1:%s/vnc.html; retrieve VNC password with DEV_STATE=%q %q password\n' "$DEV_PORT" "$state" "$0"
    ;;
  password)
    "${compose[@]}" exec -T dev-desktop cat /home/tester/.vnc/dev-password ;;
  status) "${compose[@]}" ps ;;
  check)
    "${compose[@]}" exec -T dev-desktop python /dev-tools/dev-check.py "$HOME" | tee "$state/dev-reports/check.txt"
    python3 "$here/dev-transport.py" "$DEV_PORT" | tee "$state/dev-reports/transport.txt"
    ;;
  report)
    cid=$(container_id)
    [[ -n $cid && $cid != *$'\n'* ]] || { echo 'Exactly one dev desktop required' >&2; exit 1; }
    "${engine[@]}" cp "$cid:/build/manifest.txt" "$state/dev-reports/manifest.txt"
    "${engine[@]}" inspect "$cid" --format 'Image={{.Image}} User={{.Config.User}} Network={{.HostConfig.NetworkMode}} CapDrop={{.HostConfig.CapDrop}} Security={{.HostConfig.SecurityOpt}} Mounts={{json .Mounts}} Ports={{json .NetworkSettings.Ports}}' > "$state/dev-reports/boundary.txt"
    cat "$state/dev-reports/manifest.txt" "$state/dev-reports/boundary.txt"
    ;;
  stop|clean)
    python3 "$here/dev-relay.py" stop "$state"
    # Exact dev service scope only. Never compose down (research volumes exist).
    containers=$("${engine[@]}" ps -a --filter "label=com.docker.compose.project=$DEV_PROJECT" --format '{{.ID}}')
    for cid in $containers; do
      [[ $cid =~ ^[a-f0-9]{12,64}$ ]] || { echo 'Unexpected container identity' >&2; exit 1; }
      service=$("${engine[@]}" inspect "$cid" --format '{{index .Config.Labels "com.docker.compose.service"}}')
      case "$service" in dev-desktop|dev-test|dev-build) ;; *) echo 'Refusing unexpected dev service' >&2; exit 1;; esac
      if [[ $("${engine[@]}" inspect "$cid" --format '{{.State.Running}}') == true ]]; then
        remaining=1
        for ((attempt=0; attempt<20; attempt++)); do
          remaining=$("${engine[@]}" exec "$cid" python /dev-tools/dev-tunnel.py --count)
          [[ $remaining == 0 ]] && break
          sleep .2
        done
        [[ $remaining == 0 ]] || { echo 'Refusing container cleanup while relay exec clients remain' >&2; exit 1; }
        echo 'Dev relay exec clients reaped before container stop'
      fi
      "${engine[@]}" stop --time 10 "$cid"
      "${engine[@]}" rm "$cid"
    done
    if [[ $action == clean ]]; then
      for suffix in home build; do
        volume="${DEV_PROJECT}_$suffix"
        if "${engine[@]}" volume exists "$volume"; then
          label=$("${engine[@]}" volume inspect "$volume" --format '{{index .Labels "com.docker.compose.project"}}')
          [[ $label == "$DEV_PROJECT" ]] || { echo 'Refusing volume without exact dev project label' >&2; exit 1; }
          "${engine[@]}" volume rm "$volume"
        fi
      done
      if "${engine[@]}" network exists "${DEV_PROJECT}_internal"; then
        label=$("${engine[@]}" network inspect "${DEV_PROJECT}_internal" --format '{{index .Labels "com.docker.compose.project"}}')
        [[ $label == "$DEV_PROJECT" ]] || { echo 'Refusing network without exact dev project label' >&2; exit 1; }
        "${engine[@]}" network rm "${DEV_PROJECT}_internal"
      fi
      echo 'Only dedicated dev containers, HOME/build volumes and network removed; image cache and reports retained.'
    fi
    ;;
esac
