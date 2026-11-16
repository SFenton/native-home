# App Shortcuts and Spotlight

> **What:** the HIG choices behind the phrases, symbols and result titles for routes. **Read when:** changing `SHShortcuts`, a phrase, a symbol, or what a route shows in Spotlight.

Mechanism: [routes](../../patterns/routes.md). This page records only the visible choices.

## Decisions

| Choice | Decision | HIG |
|---|---|---|
| Number of shortcuts | Two: "Open S+H" (`OpenStartPageIntent`, `square.grid.2x2`) and "Open a page in S+H" (`OpenRouteIntent`, `house`). Pages are a parameter, not one shortcut each, so the set never lags what the publication authors. | App Shortcuts: "provide a few shortcuts, each a core task"; a parameter lets one shortcut cover many items. |
| Phrases | Every phrase carries `\(.applicationName)`; the page phrases use the parameter ("Open \(\.$target) in \(.applicationName)", "Show \(\.$target) in \(.applicationName)"). Short imperative verbs, no "please" or "my". | App Shortcuts: phrases are short, natural and always include the app name. |
| Symbols | SF Symbols the system already knows, drawn from the route's authored `icon` in Spotlight and Siri results, with `house` as the fallback. | SF Symbols: use symbols that match the action; authored icons stay the publication's choice. |
| Result title and subtitle | Title is the route's authored title; subtitle its authored summary; the first line of the description names S+H. | Spotlight: a result's title is what the person would say; keep it short and unambiguous. |
| Suggested by name | Only routes authored `siri: true`, at most 10; every route can still be named. | App Shortcuts: do not flood suggestions; surface the few that matter. |
| Search words | Authored `keywords`, then the route's aliases, then `AppBranding.searchTerms`. | Spotlight: index words people actually use. |

## Not decided here

The wording of authored titles, summaries and keywords belongs to the publication. This record does not fix `parameterPresentation` on the shortcut or scene delivery on iOS 26; both need a device check.
