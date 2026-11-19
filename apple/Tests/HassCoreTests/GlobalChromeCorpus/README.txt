# Global-chrome corpus (the app's own)

The Studio does not carry `sh.sheet-levels@1`, `sh.page-chrome-hide@1`, `sh.page-wide-open@1` or `sh.tabs-visibility@1`, so these cases are not in
`ContractCorpus/`, which is a byte-for-byte copy of the Studio's `contract/corpus`. They are read only by `ServerUIGlobalChromeTests`.

- `reject/pending-global-chrome-*.json` (37): each is refused by a shipped build as `unsupported_capability`; with the compiler's global-chrome rules on
  (`ServerUIGlobalChrome.$understood`) a case the Studio would compile is accepted, and one it would refuse gives `studioIssue`. `index.json` lists them
  in the shape of the shared index (`file`, `outcome`, `issue`, `pending`, `studioIssue`).
- `accept/badge-chrome-button.json`: a plain document with no levels, hides or wide-open, used as the baseline "nothing declared" fixture. It was in the
  shared corpus until the Studio's copy replaced it with a case that declares `sh.badge-nodes@1`.

When the Studio takes these ids, move the cases into its corpus and delete this folder.
