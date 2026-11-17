// The paired Expo crawl: replays one recorded journey through Expo Explore on a simulator and records screenshots
// plus accessibility snapshots, for the reference app (the pinned Expo build) or the candidate (the native app).
//
//   node paired-expo-crawl.mjs CASE.json [--output DIR]
//
// Expo Explore is resolved from EXPO_EXPLORE_DIR, else from the global npm root. The reference side refuses to run
// unless the installed bundle is the one recorded in reference-pin.json (see assertReferencePin).
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { createHash, randomUUID } from "node:crypto";
import { createReadStream, readFileSync } from "node:fs";
import { mkdir, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, join, resolve, sep } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { coalesceSnapshotButtons, projectRecipeTabs, projectVacuumTabs } from "./navigation-policy.mjs";

/** Where this file lives; the reference pin sits beside it. */
const here = dirname(fileURLToPath(import.meta.url));

/** The Expo Explore version the adapter was reviewed against. */
export const EXPLORE_VERSION = "0.23.0";

/** The directory holding the Expo Explore package. */
export function exploreRoot(environment = process.env, execute = execFileSync) {
  if (environment.EXPO_EXPLORE_DIR) return resolve(environment.EXPO_EXPLORE_DIR);
  const globalRoot = execute("npm", ["root", "-g"], { encoding: "utf8", timeout: 30000 }).trim();
  return join(globalRoot, "@expo", "explore");
}

/** Imports one Expo Explore module by its path under dist/, only when a run needs it, so the pure checks load without it. */
async function explore(path) {
  return import(pathToFileURL(join(exploreRoot(), "dist", path)).href);
}

const hash = bytes => createHash("sha256").update(bytes).digest("hex");

export async function bundleIdentity(directory) {
  const entries = [];
  async function visit(relative = "") {
    for (const entry of await readdir(join(directory, relative), { withFileTypes: true })) {
      const path = join(relative, entry.name);
      assert.ok(!entry.isSymbolicLink(), `Unresolved bundle symlink: ${path}`);
      if (entry.isDirectory()) await visit(path);
      else {
        assert.ok(entry.isFile(), `Unsupported bundle entry: ${path}`);
        const digest = createHash("sha256");
        for await (const bytes of createReadStream(join(directory, path))) digest.update(bytes);
        entries.push([path, digest.digest("hex")]);
      }
    }
  }
  await visit();
  assert.ok(entries.length > 0, "Empty installed app bundle.");
  entries.sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0);
  const files = Object.fromEntries(entries);
  return { sha256: hash(JSON.stringify(files)), files };
}

export async function verifyBundle(config, directory) {
  assert.match(config.bundleSHA256 ?? "", /^[0-9a-f]{64}$/, "Pin the complete app bundle, including renderer frameworks and resources.");
  const actual = await bundleIdentity(directory);
  assert.equal(actual.sha256, config.bundleSHA256, "Installed app bundle differs from the recorded build.");
  return actual;
}

export function verifyLaunchInputs(config, inputBytes, binaryBytes) {
  const fixture = JSON.parse(inputBytes);
  assert.equal(fixture.id, config.fixtureID, "Unexpected fixture input.");
  assert.equal(config.fixtureSHA256, hash(inputBytes), "Fixture differs from the paired case.");
  assert.equal(config.binarySHA256, hash(binaryBytes), "Installed executable differs from the recorded build.");
  assert.equal(fixture.referenceTime, config.referenceTime, "Fixture clock differs from the paired case.");
  assert.equal(fixture.pauseContinuousAnimations === true, config.pauseContinuousAnimations === true,
    "Fixture motion policy differs from the paired case.");
}

export function verifyFixture(config, receipt, inputBytes, binaryBytes) {
  verifyLaunchInputs(config, inputBytes, binaryBytes);
  assert.equal(receipt.status, "prepared", "Fixture preparation did not succeed.");
  assert.equal(receipt.launch, "--gallery-fixture", "Not an isolated gallery launch.");
  assert.equal(receipt.fixtureID, config.fixtureID, "Stale fixture receipt.");
  assert.equal(receipt.inputSHA256, hash(inputBytes), "Fixture changed after launch.");
  assert.equal(receipt.referenceTime === undefined ? undefined : Number(receipt.referenceTime),
    config.referenceTime, "Prepared fixture clock differs from the paired case.");
  assert.ok(receipt.continuousAnimationsPaused === undefined
    || ["true", "false"].includes(receipt.continuousAnimationsPaused), "Invalid fixture motion receipt.");
  assert.equal(receipt.continuousAnimationsPaused === "true", config.pauseContinuousAnimations === true,
    "Prepared fixture motion policy differs from the paired case.");
}

export function verifyPublication(config, receipt) {
  const expected = config.expectedPublication;
  assert.ok(expected, "Candidate evidence requires a pinned publication.");
  assert.equal(receipt.status, "ready", "A retained last-good publication is not successful candidate adoption.");
  for (const key of ["publisherId", "revision", "documentSha256"]) {
    assert.equal(receipt[key], expected[key], `Candidate publication ${key} differs from the paired case.`);
  }
  assert.deepEqual([...receipt.assets].sort(), expected.assets, "Candidate assets differ from the paired case.");
  assert.equal(receipt.dataMode, "fixtures");
  assert.equal(receipt.fixtureActionsOnly, true);
  assert.equal(receipt.liveActionsEnabled, false);
}

const captureKey = step => JSON.stringify([step.capture, step.state ?? "default"]);
const matchesNode = (node, expected) => Object.entries(expected).every(([key, value]) => node[key] === value);

export function validatePostconditions(plan, conditions) {
  assert.ok(Array.isArray(conditions), "Every capture needs explicit AX postconditions.");
  const captures = plan.steps.filter(step => "capture" in step);
  const keys = captures.map(captureKey);
  assert.equal(new Set(keys).size, keys.length, "Give repeated captures distinct state names.");
  assert.deepEqual(conditions.map(captureKey).sort(), [...keys].sort(), "AX postconditions must cover exactly the planned captures.");
  for (const condition of conditions) {
    assert.ok(Array.isArray(condition.nodes) && condition.nodes.length > 0, "A capture needs positive AX evidence.");
    assert.ok(condition.absent === undefined || Array.isArray(condition.absent));
    for (const expected of [...condition.nodes, ...(condition.absent ?? [])]) {
      assert.ok(expected.identifier || expected.label || expected.role, "AX assertions need an identity.");
      for (const key of Object.keys(expected)) {
        assert.ok(["identifier", "label", "role", "kind", "selected", "hittable", "enabled", "value"].includes(key),
          `Unsupported AX assertion: ${key}`);
      }
    }
  }
}

export async function verifyCaptureEvidence(config, map) {
  const failures = [];
  const artifact = async (id, kind) => {
    const record = map.artifacts.find(item => item.id === id && item.kind === kind);
    assert.ok(record, `Missing ${kind} artifact: ${id}`);
    const file = resolve(config.output, record.path);
    assert.ok(file.startsWith(resolve(config.output) + sep), "Artifact escapes the evidence directory.");
    const bytes = await readFile(file);
    assert.equal(hash(bytes), record.sha256, "Evidence artifact has changed.");
    return bytes;
  };
  for (const condition of config.postconditions) {
    const screenIDs = map.screens.filter(screen => screen.title === condition.capture).map(screen => screen.id);
    const variantIDs = map.variants.filter(variant => screenIDs.includes(variant.screenId)
      && variant.key === (condition.state ?? "default")).map(variant => variant.id);
    const observations = map.observations.filter(item => variantIDs.includes(item.variantId) && item.screenshotArtifactId);
    if (!observations.length) {
      failures.push({ capture: condition.capture, state: condition.state, reason: "No screenshot observation." });
      continue;
    }
    for (const observation of observations) {
      const { nodes } = JSON.parse(await artifact(observation.accessibilityArtifactId, "accessibility"));
      const png = await artifact(observation.screenshotArtifactId, "screenshot");
      assert.deepEqual({ width: png.readUInt32BE(16), height: png.readUInt32BE(20) }, config.viewport);
      const missing = condition.nodes.filter(expected => !nodes.some(node => matchesNode(node, expected)));
      const forbidden = (condition.absent ?? []).filter(expected => nodes.some(node => matchesNode(node, expected)));
      if (missing.length || forbidden.length) {
        failures.push({ capture: condition.capture, state: condition.state, observationID: observation.id, missing, forbidden });
      }
    }
  }
  return failures;
}

export function missingCaptures(plan, map) {
  return plan.steps.filter(step => "capture" in step).filter(step => !map.screens.some(screen =>
    screen.title === step.capture && map.variants.some(variant =>
      variant.screenId === screen.id && variant.key === (step.state ?? "default")
      && map.observations.some(observation =>
        observation.variantId === variant.id && observation.screenshotArtifactId))));
}

/** The pinned reference build, as recorded in reference-pin.json. */
export function loadReferencePin(path = join(here, "reference-pin.json")) {
  const pin = JSON.parse(readFileSync(path, "utf8"));
  assert.match(pin.bundleSHA256 ?? "", /^[0-9a-f]{64}$/, "reference-pin.json must record a complete bundle hash.");
  assert.match(pin.sourceSHA ?? "", /^[0-9a-f]{40}$/, "reference-pin.json must record the source commit.");
  assert.ok(pin.simulatorName, "reference-pin.json must name the dedicated simulator.");
  return pin;
}

/**
 * The reference side runs only against the recorded build. A different bundle hash (another process reinstalled over the
 * dedicated simulator, or a rebuild that is not the recorded one) stops the run before it launches anything.
 */
export function assertReferencePin(config, pin) {
  if (config.side !== "reference") return;
  assert.equal(config.bundleSHA256, pin.bundleSHA256,
    `The case pins bundle ${config.bundleSHA256}, but the reference pin is ${pin.bundleSHA256}.`);
  assert.equal(config.sourceSHA, pin.sourceSHA, "The case names a different reference source commit than the pin.");
}

/** The installed bundle must be the pinned one; called with the hash just measured on the simulator. */
export function assertInstalledMatchesPin(config, pin, installedSHA256) {
  if (config.side !== "reference") return;
  assert.equal(installedSHA256, pin.bundleSHA256,
    `Refusing to run: the installed reference bundle is ${installedSHA256}, the pinned one is ${pin.bundleSHA256}.`);
}

/**
 * A reference case may only drive the dedicated simulator the pin names, so a session that reinstalls over a shared
 * simulator cannot change what is measured. `listing` is the parsed output of `xcrun simctl list devices -j`.
 */
export function assertPinnedDevice(config, pin, listing) {
  if (config.side !== "reference") return;
  const devices = Object.values(listing.devices ?? {}).flat();
  const named = devices.filter(device => device.name === pin.simulatorName);
  assert.ok(named.length > 0, `The pinned simulator ${pin.simulatorName} does not exist.`);
  assert.ok(named.some(device => device.udid === config.deviceId),
    `Refusing to run: ${config.deviceId} is not the pinned simulator ${pin.simulatorName}.`);
}

/** An absolute path to an executable named agent-device: the bound command device_open printed, or a wrapper of it. */
export function assertDeviceCommand(command) {
  assert.ok(typeof command === "string" && command.startsWith("/") && !/\s/.test(command)
    && command.split("/").pop() === "agent-device", "The case command must be an absolute agent-device path.");
}

/** The directory every simulator keeps its app data in; the fixture folder must sit under the case's own device. */
export function fixtureRoot(deviceId, home = homedir()) {
  return `${home}/Library/Developer/CoreSimulator/Devices/${deviceId}/data/Containers/Data/Application/`;
}

export async function run(config, { execute = execFileSync, pin = loadReferencePin() } = {}) {
  assert.equal(config.contract, "sdui.expo.fixture-case.v1");
  assertDeviceCommand(config.command);
  assert.ok(["reference", "candidate"].includes(config.side));
  assert.ok(["light", "dark"].includes(config.appearance));
  assertReferencePin(config, pin);
  if (config.side === "reference") {
    assertPinnedDevice(config, pin, JSON.parse(execute("xcrun", ["simctl", "list", "devices", "-j"],
      { encoding: "utf8", timeout: 30000, maxBuffer: 16 * 1024 * 1024 })));
  }
  const exploreDir = exploreRoot();
  const packageInfo = JSON.parse(await readFile(join(exploreDir, "package.json"), "utf8"));
  assert.equal(packageInfo.version, EXPLORE_VERSION, "Review the adapter before changing Expo versions.");
  const { runBlackBoxExploration } = await explore("binary/explorer.js");
  const { createReplaySession, parseReplayPlan, assertReplayFits } = await explore("binary/replay.js");
  const { duoScreenshotTurn } = await explore("binary/run.js");
  const { ExploreStore, getCoverage } = await explore("map/store.js");
  const { createExplorationInputs } = await explore("config/exploration-inputs.js");
  const { executeCaptureSetup } = await explore("capture/setup-actions.js");
  const plan = parseReplayPlan(config.plan);
  validatePostconditions(plan, config.postconditions);
  assert.ok(!plan.steps.some(step => step.optional), "Required paired steps cannot silently become optional.");
  const captures = plan.steps.filter(step => "capture" in step);
  assert.ok(captures.length > 0);
  const limits = { maxScreens: plan.steps.length + captures.length + 5,
    maxActions: plan.steps.length + 5, maxTurns: plan.steps.length * 4 + 20 };
  assertReplayFits(plan, "ios", limits);
  assert.ok(resolve(config.fixtureDirectory).startsWith(fixtureRoot(config.deviceId)));
  assert.ok(resolve(config.fixtureDirectory).endsWith("/Library/Application Support/GalleryFixture"));
  verifyLaunchInputs(config, await readFile(join(config.fixtureDirectory, "bootstrap.json")), await readFile(config.binaryPath));
  const installedApp = execute("xcrun", ["simctl", "get_app_container", config.deviceId, "com.sfenton.home", "app"],
    { encoding: "utf8", timeout: 30000 }).trim();
  assert.equal(resolve(config.binaryPath), join(installedApp, "FentonHome.debug.dylib"), "Recorded binary is not the installed app.");
  const bundle = await verifyBundle(config, installedApp);
  assertInstalledMatchesPin(config, pin, bundle.sha256);
  const root = resolve(config.output);
  await mkdir(root, { recursive: false, mode: 0o700 });
  await writeFile(join(root, "case.json"), JSON.stringify(config, null, 2) + "\n", { flag: "wx" });
  await writeFile(join(root, "bundle-manifest.json"), JSON.stringify(bundle, null, 2) + "\n", { flag: "wx" });
  let deviceFailure;
  const command = args => {
    if (deviceFailure) throw new Error(`Device execution paused: ${deviceFailure}`);
    try {
      const raw = execute(config.command, args.includes("--json") ? args : [...args, "--json"],
        { encoding: "utf8", timeout: 150000, maxBuffer: 16 * 1024 * 1024, stdio: ["ignore", "pipe", "pipe"] });
      const response = JSON.parse(raw);
      if (!response.success) throw new Error(JSON.stringify(response.error));
      return response.data;
    } catch (error) {
      deviceFailure = String(error.stderr || error.stdout || error.message).slice(-4000);
      console.error(`DEVICE_FAILURE: ${deviceFailure}`);
      throw new Error(deviceFailure);
    }
  };
  const launch = ["open", "com.sfenton.home", "--relaunch", "--launch-args=--gallery-fixture"];
  if (config.side === "candidate") launch.push("--launch-args=--server-ui-preview");
  const publicationReceiptPath = resolve(config.fixtureDirectory, "../ServerUIPreview/receipt.json");
  if (config.side === "candidate") {
    assert.ok(config.expectedPublication, "Candidate evidence requires a pinned publication.");
    await rm(publicationReceiptPath, { force: true });
  }
  await rm(join(config.fixtureDirectory, "receipt.json"), { force: true });
  command(launch);
  command(["settings", "appearance", config.appearance]);
  if (config.entrySelector) command(["wait", config.entrySelector, String(config.entryTimeoutMs ?? 15000)]);
  verifyFixture(config,
    JSON.parse(await readFile(join(config.fixtureDirectory, "receipt.json"), "utf8")),
    await readFile(join(config.fixtureDirectory, "bootstrap.json")),
    await readFile(config.binaryPath));
  let publicationReceipt;
  if (config.side === "candidate") {
    publicationReceipt = JSON.parse(await readFile(publicationReceiptPath, "utf8"));
    await writeFile(join(root, "publication-receipt.json"), JSON.stringify(publicationReceipt, null, 2) + "\n", { flag: "wx" });
    verifyPublication(config, publicationReceipt);
  }
  const inputs = createExplorationInputs({ environment: {} });
  const snapshot = () => {
    const data = command(["snapshot"]);
    return { ...data, nodes: projectVacuumTabs(projectRecipeTabs(coalesceSnapshotButtons(data.nodes))) };
  };
  const store = new ExploreStore(root);
  const timestamp = new Date().toISOString();
  const map = {
    contract: "expo.explore.local-map.v1", revision: 0,
    run: {
      id: randomUUID(), name: "S+H", platform: "ios", controller: "agent-device", exploration: "black-box",
      bundleId: "com.sfenton.home", status: "exploring", createdAt: timestamp, updatedAt: timestamp,
      build: { version: config.version, source: "local" },
      environment: { deviceModel: config.deviceModel, osVersion: config.osVersion, locale: "en",
        orientation: config.pose.includes("landscape") ? "landscape" : "portrait", colorScheme: config.appearance },
      limits: { maxDurationMinutes: 10, maxScreens: limits.maxScreens, maxActions: limits.maxActions },
      deviceId: config.deviceId,
    },
    artifacts: [], screens: [], variants: [], observations: [], elements: [],
    actionAttempts: [], transitions: [], journeys: [], frontier: [], gaps: [],
  };
  await store.initialize(map, false);
  const session = createReplaySession(plan, "ios");
  const exploration = await runBlackBoxExploration({
    session, store, map, inputs, app: { name: "S+H", bundleId: "com.sfenton.home", platform: "ios", version: config.version },
    hints: "Network-isolated canonical fixture. Execute the exact paired replay, without external navigation.",
    deadlineMs: Date.now() + 10 * 60000, ...limits, loadingSettleMs: config.loadingSettleMs ?? 1500,
    allowDestructive: config.allowFixtureLabels ?? [],
    budgetNote: () => session.budgetNote(),
    observe: async includeImage => {
      if (includeImage) command(["wait", "stable", "1000", "15000"]);
      const data = snapshot();
      const frame = { nodes: data.nodes, capturedAt: new Date().toISOString() };
      if (!includeImage) return frame;
      inputs.assertSafeSnapshot(data.nodes);
      const imagePath = join(root, "pending-frame.png");
      try {
        command(["screenshot", imagePath, "--normalize-status-bar", "--pixel-density", String(config.pixelDensity ?? 1)]);
        const png = await readFile(imagePath);
        const width = png.readUInt32BE(16), height = png.readUInt32BE(20);
        assert.deepEqual({ width, height }, config.viewport, "Device viewport does not match the paired case.");
        const turn = duoScreenshotTurn({ platform: "ios", deviceModel: config.deviceModel, nodes: data.nodes, width, height });
        return { ...frame, png, width, height, imageSha256: hash(png), frameId: randomUUID(),
          ...(turn === "turn" ? { landscape: true } : {}) };
      } finally {
        await rm(imagePath, { force: true });
      }
    },
    act: async action => {
      if ("frameId" in action) throw new Error("Coordinate fallback is disabled; use a current semantic selector.");
      if (action.action === "back") command(["back", "--in-app", "--settle"]);
      else if (action.action === "dismiss-keyboard") command(["keyboard", "dismiss"]);
      else if (action.action === "type") throw new Error("Use a named fixture field, not unscoped typing.");
      else {
        if (action.action === "open" && new URL(action.url).protocol !== "fentonhome:") {
          throw new Error("Fixture replay cannot open an external URL.");
        }
        await executeCaptureSetup([action], {
          snapshot: async () => snapshot(),
          command: async args => command(args),
          open: async url => command(["open", "com.sfenton.home", url]),
          readinessAttempts: 1, postActionObservation: "caller",
        });
      }
    },
  });
  assertInstalledMatchesPin(config, pin, (await verifyBundle(config, installedApp)).sha256);
  const missing = missingCaptures(plan, map);
  const failedPostconditions = await verifyCaptureEvidence(config, map);
  const plannedJourneyComplete = !deviceFailure && exploration.stopReason === "finished"
    && missing.length === 0 && failedPostconditions.length === 0;
  const coverage = getCoverage(map);
  map.run.status = plannedJourneyComplete && coverage.completion.eligible ? "complete" : "partial";
  if (map.run.status !== "complete") map.run.stopReason = exploration.stopReason;
  map.run.completedAt = new Date().toISOString();
  await store.write(map);
  const result = {
    contract: config.contract, side: config.side, fixtureID: config.fixtureID,
    sourceSHA: config.sourceSHA, binarySHA256: config.binarySHA256, bundleSHA256: config.bundleSHA256,
    fixtureSHA256: config.fixtureSHA256, publicationReceipt,
    pose: config.pose, viewport: config.viewport, pixelDensity: config.pixelDensity ?? 1, appearance: config.appearance,
    dataDeterministic: config.dataDeterministic === true,
    referenceTime: config.referenceTime, pauseContinuousAnimations: config.pauseContinuousAnimations === true,
    renderCachePolicy: config.renderCachePolicy,
    integration: "Unmodified Expo Explore 0.23.0 black-box engine and deterministic replay; exact T3 device_open command.",
    plannedJourneyComplete, wholeCrawlComplete: map.run.status === "complete",
    missing, failedPostconditions, coverage, exploration, deviceFailure, mapPath: store.mapPath,
    certification: "Not production parity without matching candidate evidence and the full required-case ledger.",
  };
  await writeFile(join(root, "result.json"), JSON.stringify(result, null, 2) + "\n", { flag: "wx" });
  console.log(JSON.stringify({ output: root, plannedJourneyComplete, wholeCrawlComplete: result.wholeCrawlComplete,
    plannedCaptures: captures.length, screenRecords: exploration.screens, missing: missing.length,
    failedPostconditions: failedPostconditions.length, stopReason: exploration.stopReason, deviceFailure }, null, 2));
  if (!plannedJourneyComplete) process.exitCode = 2;
  return result;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const config = JSON.parse(await readFile(process.argv[2], "utf8"));
  if (process.argv[3] !== undefined) {
    assert.equal(process.argv[3], "--output");
    assert.equal(process.argv.length, 5);
    config.output = resolve(process.argv[4]);
  }
  await run(config);
}
