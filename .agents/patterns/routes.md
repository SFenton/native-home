# Routes

> **What:** the one way the app opens an authored place: a plain path the accepted publication resolves. **Read when:** adding a way into a page (push link, Live Activity link, Spotlight, Siri, Shortcuts), or when a link opens the wrong page.

**Rule.** A route is a plain authored path (`^[a-z][a-z0-9-]{0,79}$`) plus an optional anchor.
Every entry point makes one `RouteRequest` and asks the publication's `target(for:)`.
The answer is a page, a tab and a modal, or nothing.
The app binary holds no route name, alias table or page enum.
An unknown link is dropped quietly; an unknown anchor drops only the anchor.

## One path, four consumers

| Consumer | Makes the `RouteRequest` by | Where |
|---|---|---|
| Push and Live Activity links | `PushLink.init?(_:server:prefixes:)`: first segment is a link prefix, then the path, the fragment is the anchor | `HassCore/Push/PushLink.swift` |
| Spotlight | item id `route.<routeId>` from `RouteCatalog` | `HassCore/Spotlight/SpotlightCatalog.swift` |
| Siri and Shortcuts | `RouteEntity` chosen by `RouteQuery` | `Apps/iOS/RouteEntity.swift`, `RouteQuery.swift`, `OpenRouteIntent.swift` |
| App shortcut handoff | `AppShortcutRouter` | `HassUI/AppShortcutRouter.swift` |

All four reach `PushCoordinator`.
It holds the request until a publication is accepted, then calls `UKServerUIRenderer.openSystemRoute(_:)`.
The canonical resolution is `ServerUICompositionDocument.target(for:)` in `HassCore/ServerUIRendering/ServerUIExtensionRoutes.swift`.
A path matches a route's `path` first, then one of its `aliases`.

## What the publication authors

- Per route: `aliases` (at most 8, unique across every path and alias), `keywords` (at most 12, 40 characters each), `siri`, `visibleWhen`.
- `visibleWhen` takes viewer rules only, because the catalog is built without entity state.
- Top level: `extensions.linkPrefixes`, 1 to 8 slugs. Until authored, three migration slugs apply.
- The new fields need `sh.route-links@1`.
- A route's `tabId` is also its page's home tab: an in-app link opens the page there ([modal-sheet](modal-sheet.md#a-page-link-closes-the-sheet)).
- The Studio edits them under Routes; "Import legacy aliases" seeds the old alias table.

## The catalog

`RouteCatalog` (`FentonActivityModel`) is what Spotlight, Siri and the shortcut query read without the document.
`AppSession` builds it after each accepted publication or viewer change.
`RouteCatalogStore` saves it beside the extension presentation: account-scoped, 64 routes and 65,536 bytes at most, atomic, cleared at sign-out.
It never starts a connection or decodes the document.
A gated route stays hidden while the viewer is unknown.
A changed catalog reindexes Spotlight and calls `updateAppShortcutParameters()`.

## Tests

- `PushLinkTests`: every note 07 section 5.4 path.
- `SpotlightCatalogTests`, `ServerUIExtensionRouteTests`, `RouteCatalogTests`, `PushNavigationTests`.
- `ServerUIBootstrapHostedTests`: unknown anchor, unknown path, pending then accepted.
- The contract corpus `routes-*` cases, shared with the Studio.

Choices people see: [app-shortcuts-and-spotlight](../design/apple/app-shortcuts-and-spotlight.md). Names people say: [app-name](../platforms/apple/app-name.md).
