import assert from "node:assert/strict";
import { mkdtemp, mkdir, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import {
  assertDeviceCommand, assertInstalledMatchesPin, assertPinnedDevice, assertReferencePin, bundleIdentity, fixtureRoot,
  loadReferencePin, run,
} from "../paired-expo-crawl.mjs";

const pin = { bundleSHA256: "a".repeat(64), sourceSHA: "b".repeat(40), simulatorName: "Pinned Reference" };
const referenceCase = { side: "reference", bundleSHA256: pin.bundleSHA256, sourceSHA: pin.sourceSHA, deviceId: "UDID-PINNED" };

test("the committed pin is complete", () => {
  const committed = loadReferencePin();
  assert.match(committed.bundleSHA256, /^[0-9a-f]{64}$/);
  assert.match(committed.sourceSHA, /^[0-9a-f]{40}$/);
  assert.equal(committed.simulatorName, "SH-ref-expo-pinned");
});

test("a reference case with another bundle hash is refused", () => {
  assert.throws(() => assertReferencePin({ ...referenceCase, bundleSHA256: "c".repeat(64) }, pin), /reference pin/);
  assert.throws(() => assertReferencePin({ ...referenceCase, sourceSHA: "d".repeat(40) }, pin), /different reference source/);
  assert.doesNotThrow(() => assertReferencePin(referenceCase, pin));
});

test("the installed bundle must equal the pin; the candidate side is not pinned", () => {
  assert.throws(() => assertInstalledMatchesPin(referenceCase, pin, "e".repeat(64)), /Refusing to run/);
  assert.doesNotThrow(() => assertInstalledMatchesPin(referenceCase, pin, pin.bundleSHA256));
  assert.doesNotThrow(() => assertInstalledMatchesPin({ side: "candidate" }, pin, "e".repeat(64)));
  assert.doesNotThrow(() => assertReferencePin({ side: "candidate", bundleSHA256: "f".repeat(64) }, pin));
});

test("a reference case must drive the dedicated simulator", () => {
  const listing = { devices: { "iOS 27.1": [{ name: "Pinned Reference", udid: "UDID-PINNED" }, { name: "Other", udid: "UDID-OTHER" }] } };
  assert.doesNotThrow(() => assertPinnedDevice(referenceCase, pin, listing));
  assert.throws(() => assertPinnedDevice({ ...referenceCase, deviceId: "UDID-OTHER" }, pin, listing), /not the pinned simulator/);
  assert.throws(() => assertPinnedDevice(referenceCase, pin, { devices: {} }), /does not exist/);
  assert.doesNotThrow(() => assertPinnedDevice({ side: "candidate", deviceId: "UDID-OTHER" }, pin, listing));
});

test("run stops on a pin mismatch before it touches a device", async () => {
  const execute = () => { throw new Error("no device command may run"); };
  const config = { contract: "sdui.expo.fixture-case.v1", command: "/x/agent-device", side: "reference", appearance: "dark",
    bundleSHA256: "c".repeat(64), sourceSHA: pin.sourceSHA };
  await assert.rejects(run(config, { execute, pin }), /reference pin/);
});

test("the device command must be an absolute agent-device path", () => {
  assert.doesNotThrow(() => assertDeviceCommand("/some/dir/agent-device"));
  for (const bad of ["agent-device", "/some/dir/other", "/some dir/agent-device", "", undefined]) {
    assert.throws(() => assertDeviceCommand(bad), /absolute agent-device path/);
  }
});

test("the fixture root is under the simulator's own data folder", () => {
  assert.equal(fixtureRoot("UDID", "/h"), "/h/Library/Developer/CoreSimulator/Devices/UDID/data/Containers/Data/Application/");
});

test("bundleIdentity hashes every file, sorted, and is stable", async () => {
  const dir = await mkdtemp(join(tmpdir(), "bundle-"));
  await mkdir(join(dir, "Frameworks"));
  await writeFile(join(dir, "b.txt"), "b");
  await writeFile(join(dir, "Frameworks", "a.txt"), "a");
  const first = await bundleIdentity(dir);
  assert.deepEqual(Object.keys(first.files), ["Frameworks/a.txt", "b.txt"]);
  assert.equal((await bundleIdentity(dir)).sha256, first.sha256);
  await writeFile(join(dir, "b.txt"), "changed");
  assert.notEqual((await bundleIdentity(dir)).sha256, first.sha256);
});
