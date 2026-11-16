# The server-driven root: the publication reaches the app through Home Assistant

Decision: the app's only root is the server-driven host. It follows the UI publication over its one Home Assistant connection, through `fenton_home/ui_publication/subscribe` in the owner's `fenton_home` integration. The Studio writes the publication into Home Assistant with an admin-authenticated websocket command. The compiled product is removed from the build: the shell, the tab catalog, and the pages and routes the renderer does not compose. Shared components the renderer composes stay.
Replaces: the compiled tab catalog and root (`UKShellViewController`, `AppSection`), and the reader-enrollment transport that read the Studio directly.
Rule home: `.agents/platforms/apple/architecture.md#server-driven-root`
Gate: matches_request=yes. The owner chose B in session on 2026-11-14 ("Publish into HA"), and said: "The existing app should NOT be shipped/compiled as part of this effort." `tools/jev_gate.py` was not run on this record. The screens it adds before a layout exists are judged in their own record.

Owner's request (2026-11-14): "we have to be able to either connect to the app, or the app has to publish something that HASS can consume — we need to make a decision there."

| Option | What it is | Why it loses or wins |
|---|---|---|
| A | The app reads the Studio directly | It needs an HTTPS publisher reachable from every phone, a second Keychain credential, per-account enrollment that a re-login breaks, and a 30 s poll, against "no REST polling". The Studio would become a production service the house depends on |
| **B (owner pick)** | The Studio publishes into Home Assistant; the app follows it from Home Assistant | It has the same shape as `fenton_home/house_config/subscribe`. It works wherever Home Assistant is reachable, adds no secret, and takes the user's identity from Home Assistant. It is pushed and resubscribed on reconnect, and the trust boundary becomes "a Home Assistant admin wrote it". It keeps "one state path" and "source of truth" literally true |
| C | A hidden Lovelace storage dashboard as the carrier | It misuses another product's schema and its size limits, and the frontend may try to render it |

- Content-addressed assets, such as the backdrop, come from an authenticated Home Assistant HTTP view. They are fetched once by hash with the existing bearer token.
- With no last good layout, the app shows a recovery boundary in place of a page. Its states and copy are compiled boundary copy (the copy pattern) and are judged in `2026-11-14-server-ui-boundary.md`.
- Later owner calls in this review build on this root: generic actions, one layout with `visibleWhen`, house config folded into the publication, and authored setup with native consent.
