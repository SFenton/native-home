# tools/test_ha: the test Home Assistant instance

A second, small Home Assistant (VM `homeassistant-test` on the Linux host) that serves the synthetic DemoHouse for App Review and
CI. Plan: `build/research/test-ha-instance.md`; decision: `build/decisions/house-config-runtime.md` ("Test Home Assistant
instance"). Operations rules: [ha-operations](../../.agents/platforms/apple/ha-operations.md).

| File | What |
|---|---|
| `vm.xml.tmpl` | The libvirt domain: 2 vCPU, CPU shares 256, 3 GiB, 32 GiB thin qcow2 on the root volume, UEFI, bridge `nm-bridge`, no autostart. |
| `haos.pin` | The pinned HAOS image (version, URL, sha256). |
| `rebuild.sh` | Download, verify, define and start the VM (`--dry-run`, `--destroy`). |
| `export_demo_house.sh` | DEBUG-only: `DemoHouseExportTests` writes `build/ha/demo-house.json` (the document and one resting state per id). |
| `gen_demo_package.py` | Export to `packages/demo_house.yaml` (helpers, scripts, automations, persons, template entities), `demo_house_extra.yaml`, `fenton_home/house.json` and the `fenton_demo` data. |
| `custom_components/fenton_demo` | Test-only todo, valve, camera, remote, media_player and sun entities (the template integration has no media_player; `sun.demo_sun_1` is a plain state because HA's built-in sun only makes `sun.sun`). |
| `configuration.yaml.tmpl` | The instance's `configuration.yaml`. |
| `provision.sh` | Export, generate, one `ha_change.py --host hass-test apply`, then `http_config.py` (proxy settings over the websocket), then `verify.py`. |
| `http_config.py` | Runs inside the SSH add-on. Core 2026.11 ignores an `http:` YAML block; this reads `http/config`, merges the proxy settings, calls `configure`, waits for Core, then `promote`s. Idempotent. Core listens on port 80 on a fresh Supervisor install. |
| `verify.py` | Reads back that every DemoHouse id exists with a state and that `fenton_home/house_config` returns the document. |
| `orchestrator.patch` | Guarded start-after and stop-before lines for the host's `compose_orchestrator.sh` (host lane applies). |
| `ssh_config.template` | The `Host hass-test` alias for the Mac's ssh config. |

Order: `rebuild.sh`, owner onboarding (admin user, token), SSH add-on, `ssh_config.template`, `provision.sh`. Every change after
the first boot goes through `tools/ha_change.py --host hass-test`. Credentials: `FENTON_TEST_HA_URL` / `FENTON_TEST_HA_TOKEN` are
the test instance's own; never the house's `FENTON_HASS_*`. Entity-key details marked in `demo_house_extra.yaml` are confirmed by
the step-6 spike.
