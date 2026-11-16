// Prints the bundle identity (the hash the pin records) of an installed .app directory.
//
//   node bundle-hash.mjs PATH/TO/App.app          prints the sha256
//   node bundle-hash.mjs PATH/TO/App.app --files  prints the whole manifest as JSON
import { bundleIdentity } from "./paired-expo-crawl.mjs";

const [directory, flag] = process.argv.slice(2);
if (!directory) {
  console.error("usage: node bundle-hash.mjs APP_DIRECTORY [--files]");
  process.exit(2);
}
const identity = await bundleIdentity(directory);
console.log(flag === "--files" ? JSON.stringify(identity, null, 2) : identity.sha256);
