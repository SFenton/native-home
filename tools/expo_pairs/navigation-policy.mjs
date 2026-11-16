// Snapshot projections the paired Expo crawl applies to every accessibility snapshot before Expo Explore sees it.
//
// A node is one entry of an agent-device snapshot: { index, parentIndex, type, label, identifier, value, rect,
// enabled, visible, selected, hittable, ref, ... }. Every function here is pure: it returns new nodes, never edits
// the input, and keeps `index`, `parentIndex` and `ref` so a later tap still resolves against the generation-pinned ref.
//
// The three projections run in this order: coalesceSnapshotButtons, then projectRecipeTabs, then projectVacuumTabs.

const BUTTON = "Button";

/** True when `rect` has finite, positive width and height. */
const hasGeometry = rect => rect != null && ["x", "y", "width", "height"].every(key => Number.isFinite(rect[key]))
  && rect.width > 0 && rect.height > 0;

/** The key two native Button copies must share, byte for byte, to count as one control; undefined when not eligible. */
function buttonKey(node) {
  if (node?.type !== BUTTON || !hasGeometry(node.rect)) return undefined;
  const { x, y, width, height } = node.rect;
  return JSON.stringify([node.type, node.label ?? null, node.identifier ?? null, node.enabled ?? null,
    node.visible ?? null, node.selected ?? null, node.value ?? null, x, y, width, height]);
}

/**
 * The native Duo chrome exposes one button twice, once in the navigation bar and once in the floating toolbar, on the
 * same exact frame. Keep the last copy of each such pair. Copies that differ in any compared field stay (the control is
 * then genuinely ambiguous), and a node with no usable geometry is never merged.
 */
export function coalesceSnapshotButtons(nodes) {
  const last = new Map();
  nodes.forEach((node, position) => {
    const key = buttonKey(node);
    if (key !== undefined) last.set(key, position);
  });
  return nodes.filter((node, position) => {
    const key = buttonKey(node);
    return key === undefined || last.get(key) === position;
  });
}

/** Gives the identifier-less Button children of the parent identified by `parentIdentifier` an adapter-only alias. */
function projectChildren(nodes, parentIdentifier, aliases) {
  const parents = new Set(nodes.filter(node => node.identifier === parentIdentifier).map(node => node.index));
  if (parents.size === 0) return nodes;
  return nodes.map(node => {
    if (node.type !== BUTTON || node.identifier || !parents.has(node.parentIndex)) return node;
    const alias = aliases[node.label];
    return alias === undefined ? node : { ...node, identifier: alias };
  });
}

const RECIPE_TABS = { General: "explore.recipe.tab.general", Ingredients: "explore.recipe.tab.ingredients",
  Instructions: "explore.recipe.tab.instructions" };

/** Aliases the three recipe segments (children of `recipe.tabs`, no identifier of their own, exact known label). */
export const projectRecipeTabs = nodes => projectChildren(nodes, "recipe.tabs", RECIPE_TABS);

const VACUUM_TABS = { Controls: "explore.vacuum.tab.controls", Rooms: "explore.vacuum.tab.rooms",
  "Auto-Clean": "explore.vacuum.tab.auto-clean", Dock: "explore.vacuum.tab.dock", Info: "explore.vacuum.tab.info" };

/** Aliases the five vacuum segments (children of `vacuum.tabs`); a standalone Dock command is never aliased. */
export const projectVacuumTabs = nodes => projectChildren(nodes, "vacuum.tabs", VACUUM_TABS);

/** The whole pipeline in the order the crawl applies it. */
export const projectSnapshotNodes = nodes => projectVacuumTabs(projectRecipeTabs(coalesceSnapshotButtons(nodes)));
