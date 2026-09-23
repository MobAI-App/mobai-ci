# mobai-ci

Run MobAI mobile UI tests in CI. `mobai-ci` executes your `.mob` and Maestro
(`.yaml`/`.yml`) flows on a device and emits JUnit, plus a screenshot and UI
tree for every failed step so you can see *why* a step failed, not just that it
did.

Four ways to get a device, one command to run flows on it:

| Path | Runner | Device | Cost |
|------|--------|--------|------|
| **iOS simulator** | `macos-15` or newer | booted on the runner | free |
| **Android emulator** | `ubuntu-latest` | booted on the runner | free |
| **USB device** | self-hosted macOS or Linux | your iPhone or Android phone on USB | free |
| **Cloud device farm** | any | real device in BrowserStack / Sauce / AWS | Pro |
| **BYOD** | any | a device on your own machine, over a tunnel | Pro |

The CLI is free and self-contained. Cloud and BYOD (any run against a device
that isn't on the runner) are Pro and need a MobAI account key.

## Install

GitHub Actions:

```yaml
- uses: MobAI-App/mobai-ci@v1
  # with:
  #   version: 0.1.0   # default: latest
```

Anywhere else:

```sh
curl -fsSL https://mobai.run/ci/install.sh | sh
```

Pin a version with `MOBAI_CI_VERSION=x.y.z`. Override the install dir with
`MOBAI_CI_BIN_DIR`. Supports macOS and Linux (amd64/arm64).

## Write a flow

A flow is a short script of UI steps. MobAI `.mob` is the native format; Maestro
`.yaml`/`.yml` flows run too (see [Maestro compatibility](#maestro-compatibility)).
Put flows in a `flows/` directory in your repo; `mobai-ci test ./flows` runs
every one, each as its own test case.

```mob
# flows/onboarding.mob - one test case
app "com.example.app" fresh          # launch (fresh = kill first, clean start)
assert_exists ~"Continue" timeout:20000
tap ~"Continue"
tap ~"Continue"
assert_exists ~"Try it free" timeout:8000
tap ~"Try it free"
screenshot                           # saved into the report
```

The essentials:

- `~"text"` matches an element by visible text (fuzzy/contains). Use `"exact"`
  for an exact accessibility id, or `@"id"` for a resource id.
- `assert_exists ~"..." timeout:MS` is how you **wait** - it polls until the
  element appears or the timeout elapses. `tap` does not wait, so gate every
  tap behind an `assert_exists` for the thing you expect to see first.
- `app "bundle-id" fresh` starts from a clean launch (kills the app first).
  Without `fresh` it attaches to whatever's already on screen.
- `screenshot` captures the current screen into the report (the optional
  argument is a folder for saving a raw copy on the device host; the report
  copy is always `step-N.png`).
- Lines starting with `#` are comments.

Validate flows without a device before you push:

```sh
mobai-ci validate ./flows
```

Common actions: `tap`, `type "text"`, `swipe up|down|left|right`,
`assert_exists` / `assert_not_exists`, `back`, `wait MS`, `screenshot`. The full
DSL reference (predicates, scrolling-to-find, extraction, parameters) lives in
the MobAI app docs.

### Workflows: tests as plain text

A `.mobflow` is a test written the way you would tell a tester, one step per
line. No selectors, no waits: each step is performed on the device by
Jev, TypeSafe's small model that looks at one screen and does
one thing, so the test keeps working when a button moves or a label changes.

```
# flows/onboarding.mobflow
open the Numbra app
the onboarding screen is shown with a Continue button
tap "Continue"
tap "Continue"
tap "Try it free"
the photo picker screen is shown with a "Choose from library" button
```

Before a step runs, Jev reads the sentence and tells what kind of step it is:
something to do, something to check, or a sign-in. A check is judged from the
screen and never acted on, so a failing check fails the run instead of being
nudged into passing. When a sentence could be read both ways, force it with a
prefix: `assert: the cart is empty`, `login: sign in as the tester`. Blank lines
and `#` comments are ignored.

Workflows need a TypeSafe API key in `MOBAI_TYPESAFE_KEY` (or `--jev-key`).
They run free in CI like everything else local; the device and the key are
yours. `.mobflow` and `.mob` files can share one directory:

```
  PASS  smoke.mob            (4.2s)
  PASS  onboarding.mobflow  (13.1s)  [jev]
           5.1s  line 1: [act] open the Numbra app
           0.3s  line 2: [assert] the onboarding screen is shown with a Continue button
```

A sign-in step may use any credential defined as `MOBAI_SECRET_<NAME>`
(`MOBAI_SECRET_ADMIN_EMAIL`, `MOBAI_SECRET_ADMIN_PASSWORD`). Jev picks by the
credential's name and the field's label, so name them the way the step would
say them. The value is typed on the device and scrubbed from logs, reports and
saved UI trees; a screenshot can still show an unmasked field. A step gets a
budget of 8 moves (`--jev-step-budget`): a step that needs more is usually two
steps. Workflows run on local devices only (simulator, emulator, USB), not on
cloud farms or BYOD hosts.

### Parameters

`${name}` placeholders in flows are filled from `--param name=value` (repeatable),
so one flow runs against staging or prod without edits:

```sh
mobai-ci test ./flows --param env=staging --param user=qa@example.com
```

### Maestro compatibility

Existing Maestro flows run as-is: `launchApp`, `tapOn`, `assertVisible`,
`inputText`, `swipe`, `back`, and friends map onto MobAI actions. Point
`mobai-ci test` at your `.yaml`/`.yml` files (or a mixed directory) and they're
picked up alongside `.mob` flows. Provider-specific Maestro extensions that have
no MobAI equivalent are skipped with a warning at `validate` time.

## How-to

Each recipe has a copy-paste workflow under [`examples/`](./examples). Adjust the
lines marked `ADJUST` (your build command, bundle id, device).

### iOS simulator (free, on the runner)

Boot a simulator on a macOS runner (`macos-15` or newer),
build your app, run flows.
[`examples/github-actions-simulator.yml`](./examples/github-actions-simulator.yml)

```yaml
- uses: MobAI-App/mobai-ci@v1
  with:
    boot-sim: true                     # UDID lands in $MOBAI_SIM_UDID
- name: Build app (Debug, simulator)
  run: |
    xcodebuild -scheme MyApp -destination 'generic/platform=iOS Simulator' \
      -configuration Debug -derivedDataPath build build
    echo "APP_PATH=$(find build/Build/Products -name '*.app' -type d | head -1)" >> "$GITHUB_ENV"
- name: Run flows
  run: mobai-ci test ./flows --app "$APP_PATH" --device "$MOBAI_SIM_UDID" --wait-device 4m --output reports
```

Put `boot-sim` **before** your build: the simulator boots in the background
while `xcodebuild` runs, and `--wait-device` absorbs whatever boot time is left.
The action caches a reusable image, so first-run preparation is paid once and
later runs boot fast. Pin the runner version (`macos-15`, `macos-26`) rather
than `macos-latest`: the cache is keyed to the runner image, so a silent
`latest` migration throws away every warm cache and drops you back to
first-run boot times until it rebuilds. iOS simulators take a `.app`;
mobai-ci repackages it for install.

To run on a slimmed simulator, point `sim-slim` at a committed
[simslim](https://github.com/MobAI-App/simslim) profile:

```yaml
- uses: actions/checkout@v4
- uses: MobAI-App/mobai-ci@v1
  with:
    boot-sim: true
    sim-slim: ./ci/slim.json         # services your tests do not need
```

The profile is applied once, while the cached image is built, and the image
keeps it, so later runs restore an already-slim simulator for free. The profile
joins the cache key, so editing it starts a fresh image rather than reusing the
old one. Check out your repo first: the path is relative to the workspace. One
difference from a plain boot: a slim boot does not continue in the background,
because it reads the simulator's state back before reporting the UDID.

### Android emulator (free, on the runner)

Same shape on an `ubuntu-latest` runner. The action enables KVM for you.
[`examples/github-actions-emulator.yml`](./examples/github-actions-emulator.yml)

```yaml
- uses: MobAI-App/mobai-ci@v1
  with:
    boot-emu: true                     # serial lands in $MOBAI_EMU_SERIAL
- name: Build app
  run: |
    ./gradlew assembleDebug
    echo "APP_PATH=app/build/outputs/apk/debug/app-debug.apk" >> "$GITHUB_ENV"
- name: Run flows
  run: mobai-ci test ./flows --app "$APP_PATH" --device "$MOBAI_EMU_SERIAL" --wait-device 4m --output reports
```

The first run prepares the emulator image (one-time, a few minutes); later runs
resume from the emulator's Quick Boot snapshot in seconds via the action cache.

### USB device (free, on the runner)

A phone plugged into a self-hosted macOS or Linux runner is a local device:
`mobai-ci devices` lists it and `mobai-ci test` runs on it, no account needed.
Android needs nothing else. An iPhone needs the on-device runner signed for that
phone, and there are two ways to get that:

- **Sign it yourself, headless.** Give mobai-ci a provisioning profile that
  includes the phone's UDID, plus the certificate and private key it was issued
  for, and it signs the runner when needed: first run, after a mobai-ci
  update, when the profile changes. No Apple ID, no 2FA, no desktop app.

  ```sh
  mobai-ci test ./flows --app build/MyApp.ipa \
    --sign-profile ci/runner.mobileprovision \
    --sign-cert ci/cert.pem --sign-key ci/key.pem
  ```

  The profile must cover the runner's bundle id, `run.mobai.MobAI.xctrunner`,
  either explicitly or with a wildcard app id. Certificate and key are PEM;
  from a `.p12`:

  ```sh
  openssl pkcs12 -in dev.p12 -clcerts -nokeys -out cert.pem
  openssl pkcs12 -in dev.p12 -nocerts -nodes -out key.pem
  ```

  In CI, keep the three files as secrets and write them out in a step. The
  flags also read `MOBAI_SIGN_PROFILE`, `MOBAI_SIGN_CERT` and `MOBAI_SIGN_KEY`.

- **Sign it once with the MobAI desktop app.** Start the bridge on the phone
  from the app on the same machine; mobai-ci then picks up the signed runner
  from the app's support directory (`~/.mobai` on Linux,
  `~/Library/Application Support/mobai` on macOS). A free Apple ID gets a
  7-day profile, so this needs repeating weekly; a paid membership signs for a
  year.

### Cloud device farm (Pro)

Real devices in BrowserStack, Sauce Labs, or AWS Device Farm - no device on the
runner. [`examples/github-actions-cloud.yml`](./examples/github-actions-cloud.yml)

```yaml
- uses: MobAI-App/mobai-ci@v1        # installs the CLI; no boot-* needed
- name: Build app
  run: ./scripts/build-app.sh        # produces build/MyApp.ipa (or .apk)
- name: Run flows on BrowserStack
  env:
    MOBAI_API_KEY: ${{ secrets.MOBAI_API_KEY }}       # cloud is Pro-only
    BROWSERSTACK_USERNAME: ${{ secrets.BROWSERSTACK_USERNAME }}
    BROWSERSTACK_ACCESS_KEY: ${{ secrets.BROWSERSTACK_ACCESS_KEY }}
  run: |
    mobai-ci test ./flows --cloud browserstack \
      --device "iPhone 15" --os "17" --app build/MyApp.ipa --output reports
```

Provider credentials come from the environment:

| Provider | `--cloud` | Env |
|----------|-----------|-----|
| BrowserStack | `browserstack` | `BROWSERSTACK_USERNAME`, `BROWSERSTACK_ACCESS_KEY` |
| Sauce Labs | `saucelabs` | `SAUCE_USERNAME`, `SAUCE_ACCESS_KEY`, `SAUCE_REGION` (see below) |
| AWS Device Farm | `awsdevicefarm` | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` |

Browse the catalog to get exact device names and OS versions:

```sh
mobai-ci devices --cloud saucelabs
```

`--app` takes a local `.ipa`/`.apk` (uploaded once and reused across runs by
content hash) **or** an already-uploaded provider ref (`bs://…`, `storage:…`,
`arn:…`). A cloud iOS device needs a device build (not a simulator `.app`); an
unsigned device `.ipa` is re-signed by the provider. Cloud runs are billed by
the minute and default to a 30m overall timeout (`--timeout` to change); the
session always ends when the run does.

### BYOD - your own device over a tunnel (Pro)

Drive a device attached to *your* machine from a hosted runner. The build never
leaves your network; the runner just talks to your host's MobAI HTTP API.
[`examples/github-actions-byod-tailscale.yml`](./examples/github-actions-byod-tailscale.yml)

One-time host setup (the machine with the device):

1. Run the MobAI desktop app; attach the device (or boot a simulator).
2. In **API settings**: enable **Allow external connections** and, optionally,
   **Generate a token**.
3. Make the host reachable from the runner. The example uses Tailscale (MagicDNS
   name like `office-mac`), but any tunnel works - cloudflared, SSH `-R`,
   WireGuard, or a self-hosted runner on the same LAN (then just point
   `MOBAI_ADDR` at the LAN IP, no tunnel).

Then in the job:

```yaml
- name: Connect to tailnet
  uses: tailscale/github-action@v2
  with:
    oauth-client-id: ${{ secrets.TS_OAUTH_CLIENT_ID }}
    oauth-secret: ${{ secrets.TS_OAUTH_SECRET }}
    tags: tag:ci
- run: curl -fsSL https://mobai.run/ci/install.sh | sh
- name: Run flows on the office device
  env:
    MOBAI_ADDR: http://office-mac:8686              # host's MagicDNS name or LAN IP
    MOBAI_API_KEY: ${{ secrets.MOBAI_API_KEY }}     # BYOD is Pro-only
    MOBAI_TOKEN: ${{ secrets.MOBAI_TOKEN }}         # only if you set a host token
  run: mobai-ci test ./flows --app build/MyApp.ipa --output reports
```

Your Tailscale ACL must let `tag:ci` reach the host on `:8686`. If the runner
holds the device via a lease and it's busy, add `--wait` to queue for a free
device instead of failing.

### Sharding

Split a large suite across parallel runners. Each shard runs a round-robin slice:

```yaml
strategy:
  matrix: { shard: [1, 2, 3, 4] }
# ...
- run: mobai-ci test ./flows --shard ${{ matrix.shard }}/4 --device "$MOBAI_SIM_UDID" --wait-device 4m --output reports
```

## Reports & artifacts

`test` always writes `<output>/junit.xml`. Every explicit `screenshot`
step is saved to `<output>/<case>/step-N.png`, so a green run still leaves you the
shots you asked for. On top of that, each **failed** step gets an automatic
`step-N.png` plus a `step-N-uitree.txt` capture of the failing screen, so a
"couldn't find element" failure shows you exactly what was on screen. Keep them
on red (and green):

```yaml
- uses: actions/upload-artifact@v4
  if: always()
  with: { name: mobai-reports, path: reports }
```

Optional richer outputs:

- `--allure` → `<output>/allure-results/`, ready for `allure generate` or an
  Allure TestOps upload. Every `screenshot` step and each failure capture is
  attached to its step.
- `--report-bundle` → `<output>/run.json` + `artifacts/`, a machine-readable
  record of the run (cases, steps, timings, attachments) with git and CI context
  filled in automatically on GitHub Actions and GitLab CI. The `artifacts/` tree
  holds every step's screenshot and UI tree, not just failures.

## Troubleshooting

**`no running device found`** - `mobai-ci test` attaches to an *already running*
device; it doesn't boot one. On the runner, use `boot-sim` / `boot-emu` (or
`sim boot` / `emu boot`) first and pass the printed UDID/serial with
`--wait-device`. In a **BYOD** job this almost always means `MOBAI_ADDR` isn't
set or incorrect, so the CLI fell back to looking for a *local* device - set `MOBAI_ADDR` to
your host and confirm the host's "Allow external connections" is on.

**First run is slow / times out on a cold simulator** - a fresh CI simulator's
first on-device bring-up is much slower than a warm local one. The default is
generous, but if you see startup timeouts bump `--startup-timeout` (1.5-2.5m is
typical for cold CI sims). The image cache (`boot-sim`/`--cache`) removes most of
this after the first run; to skip it entirely, warm the cache from a scheduled
job with `mobai-ci sim prepare --cache <dir>`.

**Cloud: `no device matches` / device-not-found** - device names and OS versions
must match the provider catalog exactly. List them first:
`mobai-ci devices --cloud <provider>`. Names are matched loosely (Sauce treats
`--device` as a pattern), so a too-specific string can miss.

**Cloud: onboarding flows flake, pass locally** - a cloud device can carry app
state between runs, so a suite that assumes a fresh install is non-deterministic.
Start each flow with `app "id" fresh`, and where a run truly needs clean data,
reinstall (`--app`) at the top of the run. (Full data-reset support is on the
roadmap.)

**BYOD: Tailscale `403` when connecting** - the ephemeral node's identity must be
authorized. Check that your OAuth client is tagged `tag:ci` and the ACL grants
`tag:ci` access to the host on `:8686`. With federated identity (no secret), the
trust-credential subject must match your repo/branch
(`repo:<owner>/<repo>:ref:refs/heads/<branch>`).

**`latest` install fails on hosted runners** - anonymous `api.github.com` calls
are rate-limited on shared runner IPs. The `MobAI-App/mobai-ci` action passes
`GH_TOKEN` for you; if you install via `install.sh` directly, export `GH_TOKEN`
(or pin `MOBAI_CI_VERSION`).

**Which build format?** iOS simulator → `.app`. iOS real/cloud device →
`.ipa` (unsigned device builds are re-signed by cloud providers). Android →
`.apk`.

## Command reference

```
mobai-ci test <path|glob...>   run flows -> JUnit + artifacts + exit code
mobai-ci install <app>         install a build on the target device
mobai-ci devices               list reachable devices (add --cloud <p> for a farm)
mobai-ci validate <path...>    parse flows, no device
mobai-ci sim boot | prepare    boot / pre-build a test-ready iOS simulator (macOS)
mobai-ci emu boot | prepare    boot / pre-build a test-ready Android emulator
mobai-ci version
```

Key `test` flags (`mobai-ci test --help` for all):

```
--device <name|udid|serial>   pick a device (default: the only running one)
--app <build>                 install before running (.ipa / .apk / sim .app)
--wait-device <dur>           wait for the target device to boot/appear
--output <dir>                report + artifacts dir (default ./mobai-ci-out)
--shard i/N                   run shard i of N (tests split round-robin)
--timeout / --test-timeout    overall / per-test budget (e.g. 20m, 3m)
--startup-timeout <dur>       on-device runner bring-up budget (default 8m)
--jev-key / --jev-model       workflows: TypeSafe API key (env MOBAI_TYPESAFE_KEY)
--jev-step-budget <n>         workflows: moves one step may take (default 8)
--sign-profile / --sign-cert / --sign-key
                              USB iPhone: re-sign the on-device runner with your
                              own identity, offline (env MOBAI_SIGN_*)
--param K=V                   ${name} substitution in flows (repeatable)
--allure / --report-bundle    extra report formats alongside JUnit
--cloud <provider>            run on a farm: browserstack|saucelabs|awsdevicefarm
--os / --platform / --virtual cloud device selection
--mobai-addr / --token        remote MobAI host + API token (BYOD)
--api-key <mobai_...>         MobAI account key; remote + cloud are Pro (env MOBAI_API_KEY)
--wait                        remote: queue for a free device instead of failing
```

Key `sim boot` / `sim prepare` flags (macOS, `mobai-ci sim boot --help` for all):

```
--device-type <model>         simulator model (default "iPhone 16 Pro")
--runtime <id>                iOS runtime id (default: newest installed)
--cache <dir>                 reusable simulator image; later runs boot much faster
--slim <profile.json>         turn off the iOS background services named in a
                              simslim profile file, so one machine can host
                              several simulators
--startup-timeout <dur>       budget for one-time preparation (default 8m)
```

`--slim` takes a [simslim](https://github.com/MobAI-App/simslim) profile
(`brew install mobai-app/tap/simslim`, then `simslim profile ./ci/slim.json`).
The file is required rather than implied by a bare flag: turning services off
changes what your tests can exercise, and the committed profile is the record of
what you gave up. The cost is paid once, while the `--cache` image is built, and
the image keeps it, so later runs restore an already-slim simulator for free.
One consequence: a copy of a simulator does not inherit the setting, so slim runs
boot the prepared simulator directly instead of a fresh copy per run, and runs on
one machine share it (`--app` reinstalls your build either way).

Exit codes: `0` all passed, `1` a test failed, `2` setup/usage error.

## Examples

- [`examples/github-actions-simulator.yml`](./examples/github-actions-simulator.yml) - iOS simulator on macOS (local, free)
- [`examples/github-actions-workflows.yml`](./examples/github-actions-workflows.yml) - plain-text workflows on an iOS simulator (local, free)
- [`examples/github-actions-emulator.yml`](./examples/github-actions-emulator.yml) - Android emulator on Linux (local, free)
- [`examples/github-actions-cloud.yml`](./examples/github-actions-cloud.yml) - cloud device farm (Pro)
- [`examples/github-actions-byod-tailscale.yml`](./examples/github-actions-byod-tailscale.yml) - your own device over a Tailscale tunnel (Pro)

## License

The files in this repository (the action, `install.sh`, the examples and these
docs) are MIT licensed, see [LICENSE](./LICENSE).

The `mobai-ci` binaries on the Releases page are closed source and free to use,
commercially and in CI, under [LICENSE-BINARY.md](./LICENSE-BINARY.md).
