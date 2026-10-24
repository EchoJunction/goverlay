# Isolated Prism runtime harness

Run Prism and MangoHud in a disposable **rootless Podman Compose** environment.
The default smoke uses Xvfb and Mesa software OpenGL. It opens no ports, mounts
no host directories, needs no account, and exits after bounded probes. It tests
container runtime availability, OpenGL library injection/config transport, and
Prism first-run startup. It does not prove a visible Minecraft overlay or the
GOverlay production binding/rollback path.

The runtime also includes `vulkan-swrast` (Lavapipe) for software Vulkan.
Passing the OpenGL smoke does not prove that Minecraft can create its requested
GLX visual or use a Vulkan backend. A game reporting no matching GLX visual and
missing Vulkan surface support needs its actual backend checked separately.
Record Vulkan/Lavapipe game results separately from the OpenGL smoke; neither
establishes host-native, Wayland or Flatpak compatibility.

The bundled Java 21 is a runtime baseline. Prism can select or download a managed
Java runtime required by the selected Minecraft version. Verify the actual game
executable for both instances; changing the distribution's default Java alone
does not establish which runtime Prism launches.

Prerequisites on the host: Linux, working rootless Podman (including subordinate
UID/GID mappings), `podman-compose`, Bash and coreutils. Package installation is
inside the image only. This harness never runs sudo or requests escalation; an
execution sandbox may require its operator to permit rootless user namespaces.
Do not repair a host Podman configuration to accommodate this test.

```sh
./tests/prism/runtime/run.sh smoke
```

The first line prints a private `/tmp/goverlay-prism-runtime.XXXXXXXX` state
folder. Keep that exact path to reuse its image cache or interactive desktop:

```sh
./tests/prism/runtime/run.sh --state /tmp/goverlay-prism-runtime.XXXXXXXX config
./tests/prism/runtime/run.sh --state /tmp/goverlay-prism-runtime.XXXXXXXX probe
./tests/prism/runtime/run.sh --state /tmp/goverlay-prism-runtime.XXXXXXXX smoke
```

`probe` pulls the pinned official Arch digest, verifies its recorded repository
digest and runs a trivial base-image process. `smoke` builds the image and records the
image ID and report as `image-id` and `smoke-report.txt` in that state folder.
Arch's rolling packages are reported by exact installed version. The base-image
digest and downloaded noVNC/websockify source checksums are pinned in Containerfile;
this does not freeze the rolling package repository.
After changing Containerfile or entrypoint.sh, run `build` before `smoke`.
The smoke command rejects a cached image whose recorded source fingerprint
does not match these files, including images built outside this wrapper.

Every Podman call, including Compose's version probe, uses a generated wrapper
with explicit root, runroot, temporary storage and `vfs` driver under the private
state folder, plus its own `XDG_RUNTIME_DIR`. No default host engine store is
used. A dedicated project name scopes containers and volumes. The image build
context is this directory alone; source repositories and Git metadata are not
sent to the build.

## Optional browser desktop

This explicitly starts a persistent container-only Prism desktop and publishes
**only `127.0.0.1:6080`**. Set `PRISM_DESKTOP_PORT` to select another local port.

```sh
./tests/prism/runtime/run.sh --state /tmp/goverlay-prism-runtime.XXXXXXXX desktop
./tests/prism/runtime/run.sh --state /tmp/goverlay-prism-runtime.XXXXXXXX password
```

Open `http://127.0.0.1:6080/vnc.html`, connect, and enter the generated VNC
password. The password command deliberately reveals that private desktop secret
to the local user; do not paste its output into logs or reports. VNC credentials
remain mode 0600 inside the dedicated container-owned HOME volume. Raw VNC is
not published. HTTP is local-only and should not be forwarded to another host.

Sign into Prism through that isolated UI with your own licensed account. No host
Prism accounts, tokens, keyrings, browser profiles, display sockets, GPU devices,
engine sockets, audio or HOME are mounted. Never copy an accounts.json into this
harness. It does not bypass account or Minecraft entitlement requirements.

For the later manual A/B test, create two disposable instances through Prism's
UI, give both the same Java executable, and use visibly different MangoHud
profiles. Close Prism before externally changing fixture settings. Candidate
fixture activation is research, not implemented safe production binding. Launch
each using normal Play, observe its HUD, exit and repeat after restarting. Record
Java environment transport separately from visible HUD evidence. Inspect only
whitelisted MangoHud environment keys; full launcher logs, game arguments and
process environments can contain credentials and must not be exported.

## Optional application build and fixture tests

The editor image adds FPC, Lazarus and Qt6Pas inside the container. These commands
mount this source repository read-only at `/source`, copy a snapshot without Git
metadata or generated build products into container-owned `/build`, then compile
there. They never compile into the host checkout. Use a source checkout without
private files: the source mount exposes the repository contents to the container.

```sh
./tests/prism/runtime/run.sh --state /tmp/goverlay-prism-runtime.XXXXXXXX build-editor
./tests/prism/runtime/run.sh --state /tmp/goverlay-prism-runtime.XXXXXXXX app-tests
./tests/prism/runtime/run.sh --state /tmp/goverlay-prism-runtime.XXXXXXXX app-desktop
```

`app-tests` runs the production Prism parser tests, logic tests and focused
`TPrismGuiTests` suite with networking disabled. It records a source snapshot
digest and writes `editor-image-id` and `editor-test-report.txt` to the private
state folder. It does not run the complete GUI suite, which includes an existing
network-dependent download test. `build-editor` builds tools without running
tests or copying the source. Rolling package changes can require a fresh build.

`app-desktop` builds the main GOverlay executable from that snapshot and opens it beside
Prism through the same authenticated browser desktop. Both use the dedicated
container's `$XDG_DATA_HOME/PrismLauncher` root. Create disposable instances in
Prism's UI; no instances are inserted automatically. This editor supports local profile editing;
it does not establish production Prism binding or a working Minecraft launch.
Stop `desktop` before starting `app-desktop` because both publish the same port.
Both desktop modes share the dedicated HOME volume; `discard` removes it.
This mode builds no PasCube preview or deployment helpers. Prism preview is
unavailable in the editor; `app-tests` builds the helpers needed by its tests.

## Stop and discard

```sh
# Stop only this dedicated project, retaining its account volume and image cache:
./tests/prism/runtime/run.sh --state /tmp/goverlay-prism-runtime.XXXXXXXX down
# Explicitly remove this project's container-owned account volume too:
./tests/prism/runtime/run.sh --state /tmp/goverlay-prism-runtime.XXXXXXXX discard
```

Discarding the dedicated volume destroys its isolated account/instance state.
The image cache remains under the printed temporary folder. No global prune,
system reset, or deletion of unrelated containers is performed. Temporary
storage can consume several gigabytes and is subject to host `/tmp` cleanup.

Container results are a separate compatibility row. Native-host, Wayland,
Flatpak and real Minecraft normal-Play checks remain untested until performed
in those environments; Xvfb/software GL cannot establish them.

## Synthetic development GUI

The separate `dev-compose.yaml`/`dev.sh` profile starts current-source GOverlay
with account-free synthetic native/Flatpak/custom Prism A/B fixtures. Its HOME,
build volumes and project are independent of the research `desktop-home` volume.
It uses a private state directory beside the source checkout by default; retain
its printed `DEV_STATE` and allow at least 15 GiB free for VFS image/container
copies. Override `DEV_STATE_PARENT` explicitly to choose a different parent.

```sh
# Prints DEV_STATE. If tools image is absent, follow the dev-image instruction:
make dev-build
make dev-image DEV_STATE=<printed-private-state>
make dev-build DEV_STATE=<same-state>
make dev-test DEV_STATE=<same-state>
make dev-run DEV_STATE=<same-state>
DEV_STATE=<same-state> ./tests/prism/runtime/dev.sh password
```

Open `http://127.0.0.1:6081/vnc.html` and use the private VNC password. `DEV_PORT`
selects another local port. No Prism first-run wizard or account is involved.
Image bootstrap needs network; application builds/tests are offline. Build
snapshots readonly source into container storage, records source/binary/harness
hashes and rejects stale runs. Stop the desktop before rebuilding/testing.
`dev-test` includes the existing focused production suites plus six local saves
and fresh-process reloads in persistent synthetic HOME. This is separate from
actual binary/window and browser-boundary checks:

```sh
DEV_STATE=<same-state> ./tests/prism/runtime/dev.sh check
DEV_STATE=<same-state> ./tests/prism/runtime/dev.sh report
make dev-stop DEV_STATE=<same-state>
make dev-clean DEV_STATE=<same-state>
```

All dev containers use network none. A bounded host relay binds only 127.0.0.1
and forwards browser bytes through Podman exec stdio to fixed container
localhost:6080, without an engine socket mount. It checks process owner, start
time and exact argv with pidfd before stopping; active exec clients are reaped
before container cleanup. Host Python3 with Linux pidfd support, flock and
setsid are required. No payload/password is logged. Eight clients and 120-second
idle limits apply; reconnect after an idle disconnect.

Reports stay in `DEV_STATE/dev-reports`. Stop keeps synthetic edits; clean removes
only exact dev project containers/label-checked volumes/network, retaining image
cache and reports. It never calls generic Compose down or deletes research
account volumes. Do not import real accounts/data; readonly source exposes its
contents to the container. Native Wayland, installed-host GUI behavior and
Minecraft integration are not established by this container desktop.
