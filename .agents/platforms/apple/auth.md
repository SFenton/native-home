# Authentication

> **What:** how the app signs in and keeps tokens. **Read when:** touching sign-in, tokens or the Keychain.

## Flow (`HassLoginFlow`)

Uses Home Assistant's login flow API, the same path the HA web login uses, so the user types username and password into a native form:

1. `POST /auth/login_flow` `{client_id, handler: ["homeassistant", null], redirect_uri}` → `flow_id`, `step_id: "init"`.
2. `POST /auth/login_flow/{flow_id}` `{client_id, username, password}` → either `type: "create_entry"` with `result` (the authorization code), or `type: "form"` with `step_id: "mfa"`, or `errors.base` (`invalid_auth`). **The app does not do the second step** (owner, 2026-10-17: never used): `HassLoginFlow.submitMFACode` stays in HassCore, but the screen has no code field, and an `mfa` step shows "Two-step sign-in isn't supported. Turn it off for this account in Home Assistant."
3. `POST /auth/token` (form-encoded) `grant_type=authorization_code&code=…&client_id=…` → `access_token`, `refresh_token`, `expires_in`.
4. Refresh: `grant_type=refresh_token&refresh_token=…&client_id=…`.
5. Sign out: `POST /auth/token` `action=revoke&token=<refresh_token>`, then clear the Keychain.

`client_id` is `HassServer.clientID` and `redirect_uri` shares its host, which Home Assistant accepts without fetching the client page. TODO(orchestrator): verify against the live server and confirm how the refresh token shows in the HA profile page.

## Sign-in screen (owner design, 2026-10-17)

`LoginView` / `LoginModel` (HassUI `Features/Login`). The first row is the Server address field (owner, 2026-11-06, reversing the 2026-10-17 "no address field"; decision and rules 1 to 9 in [house-config-states](../../design/house-config-states.md)). Debug builds can prefill it with `FENTON_HASS_SERVER`. Motion: [direction G, Launch and sign-in motion](../../design/direction-g.md).

- **Layout (always dark).** The radial ground `#3A4E73` → `#1E2A44` → `#121722` (`SignInGround`; `#121722` is also `LaunchBackground`, so the first frame matches the launch screen). A bare 96 pt house-and-heart (`SignInMark`, `HouseHeartShape`: no tile, the heart's ring is transparent so the ground shows) in the house colour of the saved `AppIconChoice` (`ActivityAppIconStore`, default Navy + Sky). "S+H" in 34 pt bold (VoiceOver: "S and H"), "Sign in to your Home Assistant", then a glass module (`#1C1C1E` at 66%, 26 pt radius, hairline) with Server, Username and Password rows (label column and field, 52 pt, `.URL` / `.username` / `.password` content types so a password manager offers its entry, Return order Server, Username, Password, then submits), a 50 pt capsule Sign In (`#0071E3`, white), and the footnote "Your password goes only to your Home Assistant. S+H keeps a sign-in key in your Keychain, never the password." At accessibility sizes the labels sit above the fields, the form scrolls, and the button stays reachable. iPad and the unfolded Duo: a centred column of at most 460 pt, any orientation.
- **Server field** (rules 1 to 9 of the decision record):
  1. First row of the glass module, the same row view as Username (label column 96 pt scaled, 52 pt scaled rows, label above the field at accessibility sizes). Identifiers `login.server`, `login.server.readonly`, `login.username`, `login.password`, `login.submit`. On iPad and the unfolded Duo the column stays at most 460 pt and keeps its hinge placement.
  2. Label "Server", VoiceOver "Server address", placeholder `homeassistant.local:8123`.
  3. Keyboard: `.URL` keyboard and content type, no autocapitalisation, autocorrection, spell checking or smart punctuation, Return reads Next, Clear button while editing. Sign In needs all three fields (`LoginModel.canSubmit`).
  4. Normalising (`HassServerAddress.parse`, HassCore, pure): trim; no scheme adds `https://`, except `*.local`, `localhost`, a single-label host name and RFC 1918, link-local or loopback IPv4 addresses and loopback, link-local (`fe80::/10`), unique-local or IPv4-mapped private IPv6 addresses, which get `http://` (the port never decides); an IPv6 address needs its brackets (`[fe80::1]:8123`), bare is invalid; an IDN host is punycode in the URL and Unicode in the field; path, query, fragment, user info and trailing slash are dropped, an explicit port is kept; plain `http://` only for those local hosts. The field shows the normalised address once editing ends.
  5. Errors, inline and next to the field (table below).
  6. Prefill: `FENTON_HASS_SERVER` (debug builds only), then the last server signed in to (`RememberedAccountStore.server`), then Info.plist `HASS_DEFAULT_SERVER`, then empty. A deliberate sign-out and Use a Different Account keep the server. No field takes focus by itself.
  7. Welcome back: Server and Username are read-only rows (one element each, "Server, <host>"; middle truncation), only Password is editable. Use a Different Account keeps the server and clears the username.
  8. Switching servers is sign out, then sign in with another address.
  9. The footnote stays.
- **Errors, in plain words, inline** (`LoginModel.Failure`):

  | Failure | Shown |
  |---|---|
  | Bad address (`badAddress`: the field ends editing or Sign In is pressed with text that does not parse, or `http://` to a non-local host) | The red line "Enter the address you open Home Assistant with, like homeassistant.local:8123."; red hairline round the Server row (top corners follow the module); focus back in Server with the text kept; announced. Never calls the login flow |
  | Not Home Assistant (`notHomeAssistant`: step 1, `POST /auth/login_flow`, answers 404, a non-JSON reply or JSON without `flow_id`) | The red line "Home Assistant didn't answer at that address. Check it and try again."; the same hairline, focus and announcement |
  | Wrong username or password | Red (`#FF6961`) line with a warning glyph under the module: "That username and password don't match. Check them and try again."; the password row gets a red hairline, the password clears and takes focus, the server and username stay; VoiceOver announces it |
  | Server unreachable (DNS, TLS, timeout, offline, HTTP error from a gateway) | A red-tinted card above the module: "Can't reach Home Assistant" / "Check the server address and that this phone is online. If both are right, Home Assistant may be restarting; try again in a minute." with a **Details** disclosure holding the raw reason; no hairline on Server (the address may be right); the button reads **Try Again**; the fields keep their values |
  | Anything else | The same card: "Sign-in didn't work" with Details |
  | Two-step account | The red line: "Two-step sign-in isn't supported. Turn it off for this account in Home Assistant." |
- **Working.** Pressing Sign In scales the capsule to 0.96; the label becomes "Signing In…" with a white `ArcSpinner` inside the button (VoiceOver value "Signing In"); the fields dim to 50% and are off.
- **Session expired.** A rejected token (`HassConnection.Status.rejected`) used to sign out silently into a blank form. `AppSession.sessionExpired()` now keeps who it was (`RememberedAccount`: the last username, saved in `UserDefaults` on a successful sign-in, and the person's name the profile button already keeps under `shell.profileName`; never the password) and the screen shows **Welcome back, <first name>** with the person's monogram, the username read-only, only the password field, Sign In, and a **Use a Different Account** text button that forgets the account (`AppSession.forgetExpiredAccount()`). A phone that never remembered a username (signed in before this shipped) shows the plain form. A deliberate sign-out keeps the username to fill the next form, not the welcome back.
- **Debug switches (Debug builds).** `FENTON_SIGNIN_STUB=wrong|slow|success|unreachable|failed|twostep|nothomeassistant` answers the login flow from a canned `URLProtocol` (`DebugSignInStub`) so a journey sees every error without a failed sign-in on the real server (repeated refusals can get an address banned); `FENTON_EXPIRED_ACCOUNT=<username>|<name>` starts as if that session had ended; `FENTON_SKIP_INTRO=1` skips the intro (every journey but the intro's own); `FENTON_AUTOSIGNIN=1` (with `FENTON_HASS_USERNAME` / `_PASSWORD`) presses Sign In by itself after `FENTON_AUTOSIGNIN_DELAY` seconds, which is how the launch cost run signs in with no test driving the app.

## Default server (`HASS_DEFAULT_SERVER`)

- No address is compiled into the app. The sign-in Server field starts with the last server signed in to, else the build's default (`HassServer.buildDefault`, Info.plist `HASS_DEFAULT_SERVER`, parsed with `HassServerAddress.parse` so a value with no scheme or a trailing newline works like typed text), else blank with its placeholder. Debug builds put `FENTON_HASS_SERVER` above both.
- Release builds get the value from the GitHub Actions repository **variable** `HASS_DEFAULT_SERVER` (a variable, not a secret; the owner sets it with `gh variable set HASS_DEFAULT_SERVER --body <url>`). Unset, the build setting is empty and a fresh install starts with a blank Server field. See [testflight](testflight.md#default-server-variable).
- Existing installs keep their server: it is restored from the Keychain session, never from the build setting, so changing or clearing the variable signs nobody out or moves them (`AppSessionTests`).

## Storage

- Refresh token and server URL: Keychain, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, service `com.sfenton.home.auth`, in the app group `group.com.sfenton.home` so the notification service extension can fetch camera snapshots ([push](push.md)). An item saved before the group existed moves in on first read; a build without the entitlement keeps an unshared item.
- Sign-out also deletes the cached people's photos (`PersonAvatars.removeAll()`, [avatar](../../patterns/avatar.md)); an expired session does the same through `signOut()`. A photo request carries the Bearer token only to the signed-in server's host.
- Sign-out also clears the house config (`HouseConfigStore.clear()` and the cached `HouseConfig.json` in the app group container; a cache write that finishes later is dropped), see [connection-lifecycle](connection-lifecycle.md#house-config). The document is house data, not a credential, but it is keyed to the signed-in server and nothing of it stays after sign-out.
- Sign-out clears the phone's push registration (`update_registration` with empty `app_data`) before revoking the refresh token.
- Access token: memory only, in `TokenManager` (an actor that refreshes 60 s before expiry and coalesces concurrent refreshes).
- The last username, the person's name and the last server (`RememberedAccountStore`, `UserDefaults`): not secrets, kept for the session-expired sign-in and the next form. `FENTON_UITEST_RESET` clears all three; a sign-out keeps the server and username.
- Never store the password. Never commit a token or an env file. Live-server validation reads `FENTON_HASS_USERNAME`, `FENTON_HASS_PASSWORD` and `FENTON_HASS_TOKEN` in-process: `--env shell` makes the test script load them from `~/.config/fenton-hass/env` through `tools/hass_creds.sh`, and no shell exports them; see [devices](../../testing/apple/devices.md).

## Agent GitHub App keys (owner-only)

The role identities' GitHub App private keys live at `~/.config/fenton-hass/github-apps/<role>.pem` (mode 600) and the installation tokens minted from them start `ghs_`. Both are owner-only for agents (owner, 2026-11-04). **This is detection, not prevention.**

- `tools/hooks/signing_guard.py` scans the raw text of an agent's Bash command (no shell parsing; quoted mentions and heredoc bodies count, so they are refused too): `github-apps`, `.pem`, `fenton-hass` under `.config`, a wildcard, brace, escape or quote inside a `.config` path, the bare `~/.config`, token variables (`$GH_TOKEN` and kin, `${!x}`), literal `ghs_`/`ghu_`/`gho_`/`github_pat_` tokens, environment dumps, `gh auth token`, `gh auth status --show-token`, `gh auth git-credential`, `git credential` and `security find-*-password`. File tools (Read, Grep, Glob, Edit, Write) are refused on the resolved path (`~`, symlinks, case) when it is `~/.config/fenton-hass`, below it, an ancestor of it up to `~/.config`, or `*.pem`.
- The one exemption is the exact command `python3 <checkout>/tools/gh_app_token.py check <role>` (the repo's real helper, nothing else in the command). The helper reads a key in-process and prints no token.
- The unattended deny list (`tools/triage/config.json`) repeats the rules that Claude Code honours (only `Read(path)` and `Edit(path)` rules match paths; Grep and Glob follow Read, Write follows Edit) plus Bash patterns. `tools/redact.py` masks the token prefixes and whole PEM blocks (across lines, CRLF, unterminated) in every digest, log and posted note.
- Also refused as cheap extras: the bare word `.config`, a wildcard in a hidden folder under home (`~/.c*`), a recursive reader or copier (grep -r, rg, find, tar, cp, rsync, ditto, zip, ln) aimed at home itself, and `PRIVATE KEY` as a search pattern. The `$'` rule fires only inside a word that also names a key or token, and every pattern is scanned a second time with quotes and backslashes removed. Allowed on purpose: `ls -l ~/.config/fenton-hass/env` and `touch|rm ~/.config/fenton-hass/NO_NIGHTLY`.
- **A tripwire, not a wall.** Residual bypasses: a symlink to home followed by wildcards, a path built at run time (variables, base64-decoded text), a script file that opens the key, a Write whose content is run later, and wildcard walks that never name the folder. Quoted mentions of `github-apps` or `.pem` (a commit message, a PR body) are refused too. The stronger future option, not built: an OS boundary, a separate macOS user that owns the keys, plus a token broker that mints installation tokens for the agent user.

## Web frontend hand-off

The Home Assistant settings modal opens `/config` and `/profile` signed in: `FrontendSession` stores the current tokens as `localStorage.hassTokens` (same shape and `clientId` the frontend uses) at document start, only on the server origin, in a non-persistent web data store. See [settings](../../pages/settings/ios.md).
