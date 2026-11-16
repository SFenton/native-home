# Studio at port 4801 runs without a token

Decision: the owner keeps the Studio at port 4801 local-only with no token. Options judged: set `STUDIO_AUTH_TOKEN` (a real gate, but a credential for every client), or no token with a guard hook (chosen). `tools/hooks/studio_guard.py` is the protection against other local processes, and `tools/studio_publish.py` works without auth and sends `STUDIO_AUTH_TOKEN` only when it is set.
Replaces: none
Rule home: .agents/workflow/security.md
