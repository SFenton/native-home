# Paired Expo crawl harness

> **What:** replays a recorded journey on the pinned Expo reference build and on the native candidate, so `tools/expo_pair_compare.py` can judge the pairs. **Read when:** capturing or re-capturing a parity pair.

- `paired-expo-crawl.mjs`: the replay (one case file in, a capture folder out). Needs Expo Explore 0.23.0 (`EXPO_EXPLORE_DIR`, else the global npm root).
- `navigation-policy.mjs`: the snapshot projections (duplicate buttons, recipe and vacuum tab aliases).
- `pair_cases.py`: `migrate` a recorded publication (drops the removed bedroom fields, names an existing gallery page); `prepare` and `run` write one run's fixture to the simulator just before that run.
- `reference-pin.json`: the reference build. The reference side refuses any other bundle hash, source commit or simulator. The pinned simulator is `SH-ref-expo-pinned`, a clone no other session installs over.
- `bundle-hash.mjs APP`: prints the hash the pin records.

A migrated publication holds house values: keep it under `build/`. Tests: `python3 -m unittest tools.tests.test_expo_pairs`.
