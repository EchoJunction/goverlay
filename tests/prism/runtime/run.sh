#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
state=''
if [[ ${1:-} == --state ]]; then
  state=${2:?Missing disposable state directory}
  shift 2
fi
action=${1:-smoke}
case "$action" in config|probe|build|build-editor|smoke|desktop|app-tests|app-desktop|password|status|down|discard) ;; *)
  echo "Usage: $0 [--state /tmp/goverlay-prism-runtime.XXXXXXXX] {config|probe|build|build-editor|smoke|desktop|app-tests|app-desktop|password|status|down|discard}" >&2; exit 2;; esac
if [[ -z $state ]]; then
  case "$action" in password|status|down|discard) echo '--state is required for this action' >&2; exit 2;; esac
  state=$(mktemp -d /tmp/goverlay-prism-runtime.XXXXXXXX)
  printf '%s\n' 'GOverlay disposable Prism engine v1' > "$state/marker"
fi
# Reuse only an explicitly selected, private, owned disposable engine root.
if [[ ! -d $state || -L $state || -L $state/marker ]]; then
  echo 'Refusing an unrecognized disposable state directory' >&2; exit 2
fi
state=$(cd -- "$state" && pwd -P)
if [[ $(dirname -- "$state") != /tmp || $(basename -- "$state") != goverlay-prism-runtime.* ||
      $(stat -c %u -- "$state") != "$(id -u)" || $(stat -c %a -- "$state") != 700 ||
      $(cat -- "$state/marker" 2>/dev/null) != 'GOverlay disposable Prism engine v1' ]]; then
  echo 'Refusing an unrecognized or non-private disposable state directory' >&2; exit 2
fi
for dir in root runroot runtime tmp config; do
  if [[ -L $state/$dir ]]; then echo 'Refusing symlinked engine directory' >&2; exit 2; fi
  mkdir -p -- "$state/$dir"
done
# Avoid expensive intermediate VFS filesystem copies on temporary storage.
export BUILDAH_LAYERS=false
export XDG_RUNTIME_DIR="$state/runtime"
export CONTAINERS_CONF_OVERRIDE="$state/config/containers.conf"
printf '[engine]\n' > "$CONTAINERS_CONF_OVERRIDE"
# Quote each fixed path as a shell literal; arguments are forwarded without eval.
podman_bin=$(command -v podman)
printf '#!/usr/bin/env bash\nexec %q --root %q --runroot %q --storage-driver vfs --tmpdir %q "$@"\n' \
  "$podman_bin" "$state/root" "$state/runroot" "$state/tmp" > "$state/podman"
chmod 700 "$state/podman"
project="prism_$(basename -- "$state" | tr -cd 'a-zA-Z0-9_')"
compose=(podman-compose --podman-path "$state/podman" -p "$project" -f "$here/compose.yaml")
printf 'Disposable engine: %s\nProject: %s\n' "$state" "$project"
base='docker.io/library/archlinux@sha256:dfb01267da058e5d08ffdc543bf484c9b404655b0bac1d0201d972bf950cdfd0'
fingerprint=$(cd -- "$here" && sha256sum Containerfile entrypoint.sh | sha256sum | cut -d' ' -f1)
case "$action" in
  config) "${compose[@]}" --profile interactive --profile editor --profile editor-interactive config ;;
  probe)
    "$state/podman" info --format 'rootless={{.Host.Security.Rootless}} runtime={{.Host.OCIRuntime.Name}} storage={{.Store.GraphDriverName}} root={{.Store.GraphRoot}} runroot={{.Store.RunRoot}}'
    "$state/podman" pull "$base"
    "$state/podman" image inspect "$base" --format '{{range .RepoDigests}}{{println .}}{{end}}' > "$state/base-digests.txt"
    grep -Fxq "$base" "$state/base-digests.txt"
    "$state/podman" run --rm --network none --cap-drop ALL --security-opt no-new-privileges "$base" /usr/bin/true
    ;;
  build)
    "${compose[@]}" build smoke
    "$state/podman" image inspect localhost/goverlay-prism-runtime:test --format '{{.Id}}' > "$state/image-id"
    printf '%s\n' "$fingerprint" > "$state/runtime-source-fingerprint"
    ;;
  build-editor)
    "${compose[@]}" --profile editor build app-tests
    "$state/podman" image inspect localhost/goverlay-prism-editor:test --format '{{.Id}}' > "$state/editor-image-id"
    printf '%s\n' "$fingerprint" > "$state/editor-source-fingerprint"
    ;;
  smoke)
    if ! "$state/podman" image exists localhost/goverlay-prism-runtime:test; then
      "${compose[@]}" build smoke
      printf '%s\n' "$fingerprint" > "$state/runtime-source-fingerprint"
    elif [[ $(cat "$state/runtime-source-fingerprint" 2>/dev/null) != "$fingerprint" ||
            $(cat "$state/image-id" 2>/dev/null) != "$("$state/podman" image inspect localhost/goverlay-prism-runtime:test --format '{{.Id}}')" ]]; then
      echo 'Runtime image source changed or is unverified; run this command with action build before smoke.' >&2
      exit 1
    fi
    "$state/podman" image inspect localhost/goverlay-prism-runtime:test --format '{{.Id}}' > "$state/image-id"
    "${compose[@]}" run --rm --no-deps smoke | tee "$state/smoke-report.txt"
    ;;
  app-tests)
    "${compose[@]}" --profile editor build app-tests
    "$state/podman" image inspect localhost/goverlay-prism-editor:test --format '{{.Id}}' > "$state/editor-image-id"
    printf '%s\n' "$fingerprint" > "$state/editor-source-fingerprint"
    "${compose[@]}" --profile editor run --rm --no-deps app-tests | tee "$state/editor-test-report.txt"
    ;;
  desktop|app-desktop)
    service=$action
    profile=interactive
    if [[ $action == app-desktop ]]; then profile=editor-interactive; fi
    "${compose[@]}" --profile "$profile" up -d --build "$service"
    printf 'Open http://127.0.0.1:%s/vnc.html (VNC authentication required).\n' "${PRISM_DESKTOP_PORT:-6080}"
    printf 'Password: %s --state %q password\n' "$0" "$state" ;;
  password)
    for service in app-desktop desktop; do
      if "${compose[@]}" --profile interactive --profile editor-interactive exec -T "$service" cat /home/tester/.vnc/password 2>/dev/null; then exit 0; fi
    done
    echo 'No running desktop password available' >&2; exit 1 ;;

  status) "${compose[@]}" --profile interactive --profile editor-interactive ps ;;
  down) "${compose[@]}" --profile interactive --profile editor --profile editor-interactive down ;;
  discard) "${compose[@]}" --profile interactive --profile editor --profile editor-interactive down --volumes
    echo 'Dedicated containers and account volume removed; disposable image cache remains in the printed state directory.' ;;
esac
