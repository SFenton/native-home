import assert from "node:assert/strict";
import { test } from "node:test";
import { coalesceSnapshotButtons, projectRecipeTabs, projectSnapshotNodes, projectVacuumTabs } from "../navigation-policy.mjs";

const rect = { x: 10, y: 20, width: 100, height: 44 };
const button = (index, extra = {}) => ({ index, parentIndex: 0, type: "Button", label: "Back", rect, enabled: true, ref: `e${index}`, ...extra });

test("coalesce keeps the last of two identical buttons on one frame", () => {
  const nodes = [button(1), button(2), { index: 3, type: "Other", label: "x" }];
  assert.deepEqual(coalesceSnapshotButtons(nodes).map(node => node.index), [2, 3]);
});

test("coalesce keeps buttons that differ in any compared field", () => {
  for (const change of [{ label: "Close" }, { identifier: "id" }, { enabled: false }, { selected: true }, { value: "1" },
    { rect: { ...rect, x: 11 } }]) {
    const nodes = [button(1), button(2, change)];
    assert.equal(coalesceSnapshotButtons(nodes).length, 2, JSON.stringify(change));
  }
});

test("coalesce never merges a button without finite positive geometry", () => {
  for (const bad of [undefined, { x: 0, y: 0, width: 0, height: 10 }, { x: 0, y: 0, width: 10, height: -1 },
    { x: Number.NaN, y: 0, width: 10, height: 10 }]) {
    const nodes = [button(1, { rect: bad }), button(2, { rect: bad })];
    assert.equal(coalesceSnapshotButtons(nodes).length, 2);
  }
});

test("coalesce only merges Buttons and keeps refs and indexes", () => {
  const twins = [{ index: 1, type: "Other", label: "a", rect }, { index: 2, type: "Other", label: "a", rect }];
  assert.equal(coalesceSnapshotButtons(twins).length, 2);
  const [kept] = coalesceSnapshotButtons([button(1), button(2)]);
  assert.equal(kept.ref, "e2");
  assert.equal(kept.index, 2);
});

test("recipe tabs get adapter-only identifiers, only under recipe.tabs, only when none exists", () => {
  const nodes = [
    { index: 1, type: "SegmentedControl", identifier: "recipe.tabs" },
    button(2, { parentIndex: 1, label: "General" }),
    button(3, { parentIndex: 1, label: "Ingredients" }),
    button(4, { parentIndex: 1, label: "Instructions", identifier: "native.id" }),
    button(5, { parentIndex: 1, label: "Other" }),
    button(6, { parentIndex: 9, label: "General" }),
  ];
  const out = projectRecipeTabs(nodes);
  assert.equal(out[1].identifier, "explore.recipe.tab.general");
  assert.equal(out[2].identifier, "explore.recipe.tab.ingredients");
  assert.equal(out[3].identifier, "native.id");
  assert.equal(out[4].identifier, undefined);
  assert.equal(out[5].identifier, undefined);
  assert.equal(nodes[1].identifier, undefined, "the input is not edited");
  assert.equal(out[1].ref, "e2");
});

test("vacuum tabs alias the five segments and not a standalone Dock command", () => {
  const nodes = [{ index: 1, type: "SegmentedControl", identifier: "vacuum.tabs" },
    ...["Controls", "Rooms", "Auto-Clean", "Dock", "Info"].map((label, i) => button(2 + i, { parentIndex: 1, label })),
    button(9, { parentIndex: 0, label: "Dock" })];
  const out = projectVacuumTabs(nodes);
  assert.deepEqual(out.slice(1, 6).map(node => node.identifier), [
    "explore.vacuum.tab.controls", "explore.vacuum.tab.rooms", "explore.vacuum.tab.auto-clean",
    "explore.vacuum.tab.dock", "explore.vacuum.tab.info"]);
  assert.equal(out[6].identifier, undefined);
});

test("a snapshot with no recipe or vacuum tabs passes through unchanged", () => {
  const nodes = [button(1), { index: 2, type: "Other", label: "Wake Alarms" }];
  assert.deepEqual(projectSnapshotNodes(nodes), nodes);
});

test("the pipeline coalesces, then projects", () => {
  const nodes = [{ index: 1, type: "SegmentedControl", identifier: "recipe.tabs" },
    button(2, { parentIndex: 1, label: "General" }), button(3, { parentIndex: 1, label: "General" })];
  const out = projectSnapshotNodes(nodes);
  assert.equal(out.length, 2);
  assert.equal(out[1].identifier, "explore.recipe.tab.general");
});
