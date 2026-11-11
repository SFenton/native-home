# App-UI question on the pull request or in the session

Decision: an app-UI park routes by session kind; options judged: A park and wait on the terminal as before, B post the question on the pull request for every park, C show the options in the session and ask the owner to type the pick; picked C for an interactive session and B for a headless one.
Replaces: a park that always finished `needs_decision` and waited for the owner at the terminal.
Rule home: `.agents/workflow/autonomy.md`, section App-UI gate.

The gate prints `route=session` or `route=pr` on a park. A typed pick is logged as an owner prompt, so it can be cited as `Owner's request:`; a multiple-choice click is not. The runner posts the park question once on the pull request behind a fail-closed house-data check and edits its own comment on a later park.
