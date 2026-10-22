# Isolated Prism runtime harness

Run Prism and MangoHud in a disposable **rootless Podman Compose** environment.
The default smoke uses Xvfb and Mesa software OpenGL. It opens no ports, mounts
no host directories, needs no account, and exits after bounded probes. It tests
container runtime availability, OpenGL library injection/config transport, and
Prism first-run startup. It does not prove a visible Minecraft overlay or the
GOverlay production binding/rollback path.

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
