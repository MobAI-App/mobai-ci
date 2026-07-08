# mobai-ci

Run MobAI mobile UI tests in CI. `mobai-ci` executes your `.mob` and Maestro
(`.yaml`/`.yml`) flows on a device and emits JUnit, plus a screenshot and UI
tree for every failed step.

It runs the device on the CI runner itself: a booted iOS simulator on a macOS
runner, or an Android emulator on Linux. The CLI is free and self-contained.

## Install

GitHub Actions:

```yaml
- uses: MobAI-App/mobai-ci@v1
  # with:
  #   version: 0.1.0   # default: latest
```

Anywhere else:

```sh
curl -fsSL https://raw.githubusercontent.com/MobAI-App/mobai-ci/main/install.sh | sh
```

Pin a version with `MOBAI_CI_VERSION=x.y.z`. Override the install dir with
`MOBAI_CI_BIN_DIR`. Supports macOS and Linux (amd64/arm64).

## Usage

```
mobai-ci test <path|glob...>   # run flows -> JUnit + artifacts + exit code
mobai-ci install <app>         # install a build on the target device
mobai-ci devices               # list reachable devices
mobai-ci validate <path...>    # parse flows, no device
mobai-ci sim boot              # boot a test-ready iOS simulator (macOS), print its UDID
mobai-ci emu boot              # boot a test-ready Android emulator (Linux/macOS), print its serial
mobai-ci version
```

Flags:

```
--device <name|udid|serial>   pick a device (default: the only running one)
--app <build>                 install before running (.ipa / .apk / sim .app)
--output <dir>                report + artifacts dir (default ./mobai-ci-out)
--shard i/N                   run shard i of N (tests split round-robin)
--timeout / --test-timeout    overall / per-test budget (e.g. 20m, 3m)
--wait-device <dur>           wait for the target device to boot/appear
--param K=V                   ${name} substitution in flows (repeatable)
--cloud <provider>            run on a cloud device farm: browserstack|saucelabs|awsdevicefarm
--os <version>                cloud device OS version (pair with --device)
--platform ios|android        cloud platform (default: inferred from --app extension)
--virtual                     target a cloud emulator/simulator catalog entry
--cloud-opt K=V               provider job option (repeatable)
--allure                      also write <output>/allure-results/
--report-bundle               also write <output>/run.json + artifacts/
```

`mobai-ci test` **attaches** to a running device. On macOS runners,
`mobai-ci sim boot` brings one up for you (with `--cache <dir>`, a reusable
image makes later boots much faster; the action wires this up automatically
with `boot-sim: true`). The boot continues in the background - pair it with
`--wait-device` so it overlaps your build step. One running device is
auto-detected; otherwise pass `--device`.

Android is the same flow with `mobai-ci emu boot`: the action input
`boot-emu: true` brings up an emulator and puts its serial in
`$MOBAI_EMU_SERIAL`. The first run prepares the image (one-time); later runs
resume in seconds via the emulator's Quick Boot. Linux runners need KVM, which
the action enables automatically.

First runs pay a one-time image preparation. To avoid it entirely, run
`mobai-ci sim prepare --cache <dir>` from a small scheduled workflow so the
cache is already warm when test runs need it.

**Cloud device farms** (Pro). Run the same flows on real devices in
BrowserStack, Sauce Labs, or AWS Device Farm without a device on the runner.
Set `MOBAI_API_KEY` (or `--api-key`) and the provider credentials via env:
`BROWSERSTACK_USERNAME` + `BROWSERSTACK_ACCESS_KEY`, `SAUCE_USERNAME` +
`SAUCE_ACCESS_KEY` (+ optional `SAUCE_REGION`), or `AWS_ACCESS_KEY_ID` +
`AWS_SECRET_ACCESS_KEY`. Browse the catalog with
`mobai-ci devices --cloud <provider>`, then run with
`--cloud <provider> --device <name> --os <version> --app <build>`. A local
`.ipa`/`.apk` is uploaded for you and deduplicated across runs; or pass an
already-uploaded provider ref (`bs://...`, `storage:...`, `arn:...`). Cloud
runs are billed by the minute and have a default overall timeout; override it
with `--timeout`.

Exit codes: `0` all passed, `1` a test failed, `2` setup/usage error.

## Examples

- [`examples/github-actions-simulator.yml`](./examples/github-actions-simulator.yml): iOS simulator on a macOS runner (local, free).
- [`examples/github-actions-emulator.yml`](./examples/github-actions-emulator.yml): Android emulator on a Linux runner (local, free).
- [`examples/github-actions-byod-tailscale.yml`](./examples/github-actions-byod-tailscale.yml): drive a device on your own machine over a Tailscale tunnel (BYOD, Pro).
- [`examples/github-actions-cloud.yml`](./examples/github-actions-cloud.yml): run on a cloud device farm - BrowserStack / Sauce Labs / AWS Device Farm (Pro).

## Artifacts

`test` writes `<output>/junit.xml` and, per failed step,
`<output>/<case>/step-N.png` + `step-N-uitree.txt`: the screenshot and UI tree
of the failing screen, so you can see why an element wasn't found.

`--allure` additionally writes `<output>/allure-results/`, ready for
`allure generate` or an Allure TestOps upload. `--report-bundle` writes
`<output>/run.json` + `artifacts/`, a machine-readable record of the run
(cases, steps, timings, attachments) with git and CI context filled in
automatically on GitHub Actions and GitLab CI. JUnit stays the always-on
default.
