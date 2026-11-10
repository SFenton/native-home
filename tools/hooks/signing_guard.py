#!/usr/bin/env python3
"""PreToolUse hook for Bash, Read, Grep, Glob, Edit, Write, MultiEdit and NotebookEdit: signing material is owner-only.

Owner decision 2026-11-03 ("Approve"): certificates, provisioning profiles and Apple ID / App Store Connect keys stay with the
owner (the fixed set in ``.agents/workflow/agent-roster.md``). The TestFlight upload of a reviewed build stays autonomous
because it runs on GitHub Actions (``.github/workflows/ios-release-build.yml``) with repository secrets that the job writes to
``$RUNNER_TEMP`` itself; no agent session touches a local key.

Acts on **agent sessions**, headless ones included: ``FENTON_HEADLESS=1``, or a payload with an ``agent_type`` or ``agent_id``
(the main thread of ``claude --agent X`` and every subagent carry them). A plain interactive session of the owner carries
neither and is never blocked. Exit 2 sends the message back.

Blocked, by tool:

- **Read, Grep, Edit, Write, MultiEdit, NotebookEdit** of a path that is signing material (``*.p12 *.pfx *.p8
  *.mobileprovision *.provisionprofile *.cer *.certSigningRequest *.keychain *.keychain-db``, ``AuthKey_*``,
  ``~/Library/MobileDevice`` and ``Provisioning Profiles``, ``~/Library/Keychains``).
- **Bash**, per simple command (quote-aware; wrappers, ``bash -c`` and ``eval`` strings, ``xargs`` and heredoc-free text only):
  any word that names that material (reading, copying, moving, hashing, base64, a redirect target, a ``find -name '*.p12'``),
  or the App Store Connect key variables ``ASC_PRIVATE_KEY`` and ``ASC_KEY_PATH`` (and the ``--asc-key-path`` / ``-authenticationKeyPath`` options);
  ``security import|export|find-identity|delete-identity|add-certificates`` and the other keychain credential commands
  (``dump-keychain``, ``unlock-keychain``, ``set-key-partition-list``, ``create-keychain``, ``delete-keychain``,
  ``delete-certificate``, ``find-generic-password``, ``find-internet-password``); ``fastlane match|cert|sigh``; any
  ``xcrun altool`` or ``notarytool`` (both carry or store credentials).

**GitHub App keys and tokens (owner, 2026-11-04; reworked after review round 1).** The role identities' private keys
(``~/.config/fenton-hass/github-apps/<role>.pem``) and the installation tokens minted from them (``ghs_``) are owner-only. This part
does **not** use the shell lexer. A Bash command is refused on its raw text, case-insensitively, quoted mentions and heredoc bodies
included (rarely needed, so blocked): ``github-apps``, ``.pem``, ``.config`` with ``fenton-has``, a wildcard, brace, escape or quote
inside a ``.config`` path, the bare ``~/.config`` folder, ``$'``/``$"`` next to a key or token name, a token variable expansion
(``$GH_TOKEN`` and kin, ``${!x}``), a literal ``ghs_``/``ghu_``/``gho_``/``github_pat_`` token, an environment dump (``env``,
``printenv``, ``set``, ``export -p``, ``ps eww``), ``gh auth token|git-credential|status --show-token``, ``git credential``,
``security find-*-password``. File tools (Read, Grep, Glob, Edit, Write, ...) are refused on the resolved path (``~``, symlinks and
case folded) when it is the ``~/.config/fenton-hass`` folder, below it, an ancestor of it up to ``~/.config``, or ends in ``.pem``.
The one exemption is the exact command ``[python3 [-I]] <checkout>/tools/gh_app_token.py check <role>`` with the real helper of this repo
and nothing else in it; the helper reads a key in-process and prints no token.

**This is a tripwire, not a wall: detection, not prevention.** Residual bypasses: a symlink to home followed by wildcards, a path built at run time
(variables, base64-decoded text), a script file that opens the key, a Write whose content is run later, and wildcard walks from a
directory that is not named. Also refused as cheap extras: a recursive reader or copier aimed at home or ``~/.config``, a wildcard
in a hidden folder under home, ``PRIVATE KEY`` as a search pattern; allowed on purpose: ``ls -l ~/.config/fenton-hass/env`` and
``touch|rm ~/.config/fenton-hass/NO_NIGHTLY``. A stronger guarantee needs an OS boundary, for example a separate macOS user that
owns the keys plus a token broker; that is a future option, not built.

**The owner's GitHub login (2026-11-09).** The agent's ``gh`` login is the default config; the owner's admin login lives in
``~/.config/gh-owner``. Agent sessions are refused: that folder (path-only: any ``/gh-owner`` segment that ends a word or is followed by ``/``, so ``.config/./gh-owner``, ``../gh-owner`` and
``//`` count; ``gh-owner`` in a branch, ref, record name or grep pattern, followed by ``-`` or with no slash, does not), the ``gh-admin`` command, a ``hosts.yml`` word, a
file tool on one (resolved path, case folded), ``GH_CONFIG_DIR``/``XDG_CONFIG_HOME`` anywhere in code, assigning, ``export``,
``unset`` or ``env -u`` of ``GH_TOKEN``/``GITHUB_TOKEN``/``GH_ENTERPRISE_TOKEN``, ``gh auth login|logout|switch|refresh|token|
setup-git|git-credential``, ``gh config set``, ``git config`` writes and ``git -c`` of ``credential.*``, and Edit/Write of
``~/.gitconfig``, ``~/.config/git/config`` or ``~/.git-credentials``. Plain ``gh auth status`` and ``ls ~/.config/gh`` pass. Names
inside prose (``--body``, ``echo``, data heredocs) pass. Same limits: a relative walk (``cd ~/.config/gh; cat *``), a path built at
run time, a Bash redirect into ``~/.gitconfig``, a ``.config/gh-owner`` path inside a ``git commit -m "$(cat <<EOF ...)"`` body (use ``-F -``) and a script that opens the file are not seen.

Not blocked: prose in a ``git commit -m``/``gh --body`` value or in a grep pattern, an ``echo`` that only mentions a name, and
the release scripts run with ``--dry-run`` (they print the commands and read no key). Out of scope: a path built from a variable
or encoded text and script files that open a key (see above). The deny list in ``tools/triage/config.json`` backs this hook
for unattended sessions.
"""

from __future__ import annotations

import fnmatch
import json
import os
import re
import sys
from typing import List, Optional

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from shell_parse import FEEDERS, KEYWORDS, SHELLS, WRAPPERS, XARGS_VALUE, strip_prefixes, tokenize, unwrap_xargs  # noqa: E402

MESSAGE = (
    "Blocked: certificates, provisioning profiles, signing keys and App Store Connect keys are owner-only (fixed set, "
    "agent-roster.md). TestFlight upload stays autonomous on GitHub Actions (ios-release-build uses repository secrets), so "
    "no agent needs a local key, certificate, profile or keychain command. If the build fails on signing, report it as "
    "`needs_decision` with `owner_only` and let the owner fix it in their own terminal."
)

#: Files whose names say they are signing material (a trailing word character means a different extension: ``.cert``).
SIGNING_FILE = re.compile(r"\.(?:p12|pfx|p8|mobileprovision|provisionprofile|cer|certSigningRequest|keychain-db)(?![A-Za-z0-9])"
                          r"|AuthKey_", re.I)
#: ``login.keychain`` only as a path-like word (it holds a slash), so a Swift test filter such as ``X.Keychain`` passes.
KEYCHAIN_PATH = re.compile(r"/[^/\s]*\.keychain(?![A-Za-z0-9-])")
SIGNING_DIR = re.compile(r"Library/MobileDevice|Provisioning[ \\]?Profiles|Library/Keychains", re.I)
ASC_ENV = re.compile(r"ASC_(?:PRIVATE_KEY|KEY_PATH)")
ASC_EXPANSION = re.compile(r"\$\{?ASC_(?:PRIVATE_KEY|KEY_PATH)")
#: Options that hand a key file to a release tool or to xcodebuild: an agent never has a local key to pass.
KEY_OPTIONS = {"--asc-key-path", "-authenticationKeyPath", "--apiKey", "--apiIssuer"}
SECURITY_DENIED = {"import", "export", "find-identity", "delete-identity", "add-certificates", "dump-keychain", "unlock-keychain",
                   "set-key-partition-list", "create-keychain", "delete-keychain", "delete-certificate", "find-generic-password",
                   "find-internet-password"}
FASTLANE_DENIED = {"match", "cert", "sigh"}
APPLE_TOOLS = {"altool", "notarytool"}
#: The release scripts run with ``--dry-run`` print their commands and read no key.
RELEASE_SCRIPTS = {"testflight_upload.sh", "ios_ipa_build.sh", "testflight_queue.py"}
#: Option values that are prose or a search pattern, not a path.
PROSE_OPTIONS = {"-m", "--message", "--body", "-b", "--title", "-t", "--notes", "--note", "--subject"}
SEARCHERS = {"grep", "egrep", "fgrep", "rg", "ag", "ack", "sed", "awk"}
SEARCH_PATTERN_OPTIONS = {"-e", "--regexp", "-g", "--glob", "--iglob", "-t", "--type", "-T", "--type-not", "-f", "--file"}
SHELL_C = re.compile(r"^-[A-Za-z]*c[A-Za-z]*$")
PATH_TOOLS = ("Read", "Grep", "Glob", "Edit", "Write", "MultiEdit", "NotebookEdit")

#: GitHub App private keys: any ``.pem`` file, or a path component ``github-apps`` (``~/.config/fenton-hass/github-apps/<role>.pem``).
PEM_FILE = re.compile(r"\.pem(?![A-Za-z0-9])", re.I)
APP_KEY_DIR = re.compile(r"(?:^|[/\\])github-apps(?:[/\\]|$)", re.I)
#: The one token helper: it reads a key in-process and never prints a token (``tools/gh_app_token.py``).
TOKEN_HELPER = "gh_app_token.py"
#: An expansion of a variable that holds an installation or user token.
TOKEN_VAR = re.compile(r"\$\{?[A-Za-z_]*(?:GH|GITHUB|APP|INSTALLATION|GHS)[A-Za-z_]*TOKEN", re.I)
TOKEN_VAR_NAME = re.compile(r"^[A-Za-z_]*(?:GH|GITHUB|APP|INSTALLATION|GHS)[A-Za-z_]*TOKEN$", re.I)
TOKEN_LITERAL = re.compile(r"(?<![A-Za-z0-9_])gh[sup]_[A-Za-z0-9_]{16,}|github_pat_[A-Za-z0-9_]{16,}")
#: A file whose name says it caches a token. Source and docs about the helper (``gh_app_token.py``) are not token files.
TOKEN_FILE = re.compile(r"^\.?(?:(?:gh|github)[-_]?(?:app[-_]?)?(?:installation[-_]?)?token(?:[-_.][A-Za-z0-9._-]*)?|ghs_[A-Za-z0-9_]*)$", re.I)
TOKEN_FILE_SOURCE = re.compile(r"\.(?:py|sh|md|swift|txt|json|yml|yaml)$", re.I)
#: The owner's admin login folder and the ``gh-admin`` helper name (``~/.config/gh-owner``); prose-tolerant like the key folder.
#: Only a path counts: a ``/gh-owner`` segment that ends the word or is followed by ``/`` (so ``.config/./gh-owner``, ``../gh-owner`` and ``//`` need no resolving), never a branch, ref, review-record name or grep pattern containing the text.
OWNER_GH = re.compile(r"/gh-owner(?:/|(?=[\s;&|)<>'\"`]|$))|(?:^|[\s'\"=:(])gh-owner/", re.I)
OWNER_GH_PATH = re.compile(r"(?:^|/)gh-owner(?:/|$)", re.I)
OWNER_GH_WHY = "the owner's gh login folder (~/.config/gh-owner)"
#: Environment names that choose or hold the gh login.
GH_ENV_NAMES = "GH_CONFIG_DIR|XDG_CONFIG_HOME|GH_TOKEN|GITHUB_TOKEN|GH_ENTERPRISE_TOKEN"
GH_ENV_WORD = re.compile(r"^(?:-u)?(?:" + GH_ENV_NAMES + r")(?:=|$)")
GH_CONFIG_ENV = re.compile(r"(?<![A-Za-z0-9_])(?:GH_CONFIG_DIR|XDG_CONFIG_HOME)(?![A-Za-z0-9_])")
GH_CONFIG_ENV_WHY = "GH_CONFIG_DIR / XDG_CONFIG_HOME (they choose which gh login runs)"
GH_AUTH_DENIED = {"login", "logout", "switch", "refresh", "token", "setup-git", "git-credential"}
GIT_CRED_KEY = re.compile(r"^(?:-c)?credential\.", re.I)
GIT_READ_FLAGS = {"--get", "--get-all", "--get-regexp", "--list", "-l", "--get-urlmatch"}
#: Files an agent never edits: they route git to a credential helper or hold plain-text tokens.
GIT_CRED_FILES = (".gitconfig", ".git-credentials", os.path.join(".config", "git", "config"), os.path.join(".config", "git", "credentials"))
#: Commands that print or copy their operands.
EMITTERS = {"echo", "printf", "print", "cat", "tee", "base64", "xxd", "od", "hexdump", "less", "more", "head", "tail", "pbcopy", "strings"}


def agent_session(payload: dict) -> bool:
    """Is this an agent session (runner or headless, a ``--agent`` main thread, or a subagent)?"""
    return (os.environ.get("FENTON_HEADLESS") == "1" or bool(payload.get("agent_type")) or bool(payload.get("agent_id")))


#: Names a wildcard word is matched against: ``cp ~/Desktop/*.p1? /tmp`` and ``ls ~/Library/Mobile*/Prov*`` still name them.
SAMPLE_FILES = ("app.pem", "role.private-key.pem", "dist.p12", "dist.pfx", "AuthKey_ABC123.p8", "key.p8", "app.mobileprovision", "app.provisionprofile", "dist.cer",
                "req.certSigningRequest", "login.keychain-db", "login.keychain")
SAMPLE_PREFIXES = ("", "./", "dir/", "~/", "~/Desktop/", "~/Downloads/", "$HOME/", "/Users/u/Desktop/", "/Users/u/Downloads/", "/Users/u/")
SAMPLE_DIRS = ("~/.config/fenton-hass/github-apps", "~/.config/fenton-hass/github-apps/coder.pem", "$HOME/.config/fenton-hass/github-apps",
               "/Users/u/.config/fenton-hass/github-apps", "/Users/u/.config/fenton-hass/github-apps/coder.pem", "github-apps",
               "~/Library/MobileDevice", "~/Library/MobileDevice/Provisioning Profiles", "~/Library/MobileDevice/Provisioning Profiles/x.mobileprovision",
               "~/Library/Keychains", "~/Library/Keychains/login.keychain-db", "/Users/u/Library/MobileDevice", "$HOME/Library/MobileDevice",
               "/Users/u/Library/MobileDevice/Provisioning Profiles", "/Users/u/Library/Keychains", "Library/MobileDevice", "Library/Keychains")
GLOB_CHARS = re.compile(r"[*?\[]")


def glob_names_signing(word: str) -> bool:
    """Does a wildcard word (``*.p1?``, ``~/Library/Mobile*/Prov*``) match a sample signing name? Only when its last path component
    has at least two literal characters: ``~/Desktop/*`` or ``*`` could name anything and does not count (a folder that is itself
    signing material, such as ``~/Library/Keychains/*``, is caught by name)."""
    if not GLOB_CHARS.search(word):
        return False
    if "fenton-hass/" in word.lower() and any(fnmatch.fnmatchcase(d.lower(), word.lower()) for d in SAMPLE_DIRS if "github-apps" in d):
        return True  # `~/.config/fenton-hass/github-*/c*`: the owner's folder is known, so a wildcard below it names the keys
    if len(GLOB_CHARS.sub("", word.rstrip("/").rsplit("/", 1)[-1])) < 2:
        return False
    low = re.sub(r"^/users/[^/*?\[]+/", "/users/u/", word.lower())
    names = [prefix + name for prefix in SAMPLE_PREFIXES for name in SAMPLE_FILES] + list(SAMPLE_DIRS)
    return any(fnmatch.fnmatchcase(name.lower(), low) for name in names)


def names_signing(text: str) -> Optional[str]:
    """Why ``text`` (one word or a path) names signing material, or ``None``."""
    if glob_names_signing(text):
        return "a wildcard that matches signing material"
    if SIGNING_FILE.search(text) or KEYCHAIN_PATH.search(text):
        return "signing material by name"
    if SIGNING_DIR.search(text):
        return "the provisioning-profile or keychain folders"
    if ASC_ENV.search(text):
        return "the App Store Connect key variables"
    if text in KEY_OPTIONS:
        return f"an App Store Connect key option ({text})"
    if PEM_FILE.search(text) or APP_KEY_DIR.search(text):
        return "a GitHub App private key (*.pem or the github-apps folder)"
    base = os.path.basename(text.rstrip("/"))
    if TOKEN_FILE.match(base) and not TOKEN_FILE_SOURCE.search(base):
        return "a file that holds a GitHub token"
    return None


def token_print_reason(program: str, words: List[str]) -> Optional[str]:
    """Why a command would print a GitHub token (a variable, ``printenv``, or a literal ``ghs_`` token), or ``None``."""
    if program in ("printenv", "declare", "typeset", "export", "set") and any(
            TOKEN_VAR_NAME.match(w) for w in words[1:] if not w.startswith("-")):
        return f"{program} of a GitHub token variable"
    if program in EMITTERS:
        text = " ".join(words[1:])
        if TOKEN_VAR.search(text):
            return "printing a variable that holds a GitHub token"
        if TOKEN_LITERAL.search(text):
            return "printing a GitHub token"
    return None


def security_reason(words: List[str]) -> Optional[str]:
    """``security <subcommand>`` that reads, writes or lists keychain identities and credentials."""
    positional = [w for w in words[1:] if not w.startswith("-")]
    if positional and positional[0] in SECURITY_DENIED:
        return f"security {positional[0]}"
    return None


def drop_prose(program: str, words: List[str]) -> List[str]:
    """The words of a command without the values that are prose or a search pattern (git/gh messages, grep patterns)."""
    if program == "git":  # `git grep PATTERN`: the pattern is a search, not a path
        sub = [w for w in words[1:] if not w.startswith("-")][:1]
        if sub == ["grep"]:
            return drop_prose("grep", words[words.index("grep"):])
    if program in ("git", "gh", "ship.sh"):
        kept, skip = [], False
        for word in words:
            if skip:
                skip = False
            elif word in PROSE_OPTIONS:
                skip = True
            elif not word.startswith(("--message=", "--body=", "--title=", "--notes=", "--note=", "--subject=")):
                kept.append(word)
        return kept
    if program in SEARCHERS:
        kept, skip, seen_pattern = [], False, False
        for word in words[1:]:
            if skip:
                skip = False
            elif word in SEARCH_PATTERN_OPTIONS:
                skip = True
                seen_pattern = seen_pattern or word in ("-e", "--regexp")
            elif word.startswith("-"):
                kept.append(word)
            elif not seen_pattern:
                seen_pattern = True  # the first operand is the pattern
            else:
                kept.append(word)
        return kept
    if program in ("echo", "printf"):  # only a redirect target is a path
        return [words[i + 1] for i, w in enumerate(words[:-1]) if re.fullmatch(r"\d*>>?", w)]
    return words


def release_dry_run(words: List[str]) -> bool:
    """A release script (directly, or through bash/python) run with ``--dry-run``."""
    return "--dry-run" in words and any(os.path.basename(w) in RELEASE_SCRIPTS for w in words[:3])


def hosts_yml_glob(word: str) -> bool:
    """Does a wildcard word name ``hosts.yml`` (``hosts.*``, ``ho*.yml``)? ``*.yml`` alone does not: it needs a literal ``ho`` start or ``host``."""
    last = word.rstrip("/").rsplit("/", 1)[-1].lower()
    return bool(GLOB_CHARS.search(last)) and fnmatch.fnmatchcase("hosts.yml", last) and (last.startswith("ho") or "host" in last)


def gh_credential_reason(words: List[str]) -> Optional[str]:
    """Why one simple command reaches or changes the gh/git GitHub login (owner decision 2026-11-09), or ``None``: login-choosing
    environment names (also as ``VAR=`` prefixes, ``export``, ``unset``, ``env -u``), ``hosts.yml`` words, ``gh auth``/``gh config set``
    and ``git`` credential-helper writes. Prose values and search patterns are not words (:func:`drop_prose`)."""
    stripped = strip_prefixes(list(words))
    prefix = words[:len(words) - len(stripped)]
    program = os.path.basename(stripped[0]) if stripped else ""
    kept = drop_prose(program, stripped) if stripped else []
    if program in FEEDERS:  # `xargs -I{} gh auth login`
        args = stripped[1:]
        skip = 0
        while skip < len(args) and args[skip].startswith("-"):
            skip += 2 if args[skip] in XARGS_VALUE else 1
        inner = strip_prefixes(args[skip:])
        if any(GH_ENV_WORD.match(w) for w in args[skip:len(args) - len(inner)]) or (inner and gh_credential_reason(inner)):
            return "a gh login change run through xargs"
    if program == "gh-admin":
        return "the owner's admin gh alias (gh-admin)"
    if any(GH_ENV_WORD.match(w) for w in [*prefix, *kept]):
        return "setting, exporting or unsetting a gh login variable (GH_CONFIG_DIR, XDG_CONFIG_HOME, GH_TOKEN, GITHUB_TOKEN, GH_ENTERPRISE_TOKEN)"
    for word in kept:
        if os.path.basename(word.rstrip("/")).lower() == "hosts.yml" or hosts_yml_glob(word):
            return "a gh hosts.yml (it holds a login token)"
    positional = [w for w in kept[1:] if not w.startswith("-")]
    if program == "gh":
        if "auth" in positional[:2]:
            sub = positional[positional.index("auth") + 1:][:1]
            if sub and sub[0] in GH_AUTH_DENIED:
                return f"gh auth {sub[0]} (it changes or prints the gh login)"
        if positional[:2] == ["config", "set"] or positional[1:3] == ["config", "set"]:
            return "gh config set"
    if program == "git":
        why = "a git credential.* setting (the credential helper chooses the GitHub login)"
        args = kept[1:]
        for i, word in enumerate(args):  # `git -c credential.x=y <any subcommand>` and `--config-env=credential.x=ENV` always set it
            if (word == "-c" and i + 1 < len(args) and GIT_CRED_KEY.match(args[i + 1])) or word.lower().startswith(("-ccredential.", "--config-env=credential.")):
                return why
        if positional[:1] == ["config"] and any(GIT_CRED_KEY.match(w) for w in args) and not (set(args) & GIT_READ_FLAGS):
            return why
    return None


def simple_reason(words: List[str], depth: int) -> Optional[str]:
    """Why one simple command touches signing material or runs a credential command, or ``None``."""
    why = dump_reason(words)
    if why:
        return why
    why = gh_credential_reason(words)
    if why:
        return why
    words = strip_prefixes(list(words))
    if not words:
        return None
    if os.path.basename(words[0]) == "ps" and any(PS_ENV_WORD.fullmatch(w) for w in words[1:]):
        return "a process listing with environments"
    if os.path.basename(words[0]) in FEEDERS:
        words = unwrap_xargs(words[1:]) or words
    program = os.path.basename(words[0])
    if program in SHELLS or program == "eval":
        strings = [words[i + 1] for i, w in enumerate(words[:-1]) if SHELL_C.match(w)] if program in SHELLS else [" ".join(words[1:])]
        for text in strings:
            why = command_reason(text, depth + 1)
            if why:
                return why
    if program == "xcrun":  # `xcrun security ...` is `security ...`
        rest, skip = [], False
        for w in words[1:]:
            if skip:
                skip = False
            elif w in ("-sdk", "--sdk", "-toolchain", "--toolchain"):
                skip = True
            elif not w.startswith("-"):
                rest.append(w)
        if rest[:1] == ["security"]:
            words, program = ["security", *rest[1:], *[w for w in words[1:] if w.startswith("-")]], "security"
    if program == "security":
        why = security_reason(words)
        if why:
            return why
    names = [os.path.basename(w) for w in words]
    if "fastlane" in names:
        sub = [w for w in words[names.index("fastlane") + 1:] if not w.startswith("-")][:1]
        if sub and sub[0] in FASTLANE_DENIED:
            return f"fastlane {sub[0]}"
    if program in APPLE_TOOLS or (program == "xcrun" and APPLE_TOOLS & set(w for w in words[1:4])):
        return "altool/notarytool (they carry or store Apple credentials)"
    if release_dry_run(words):
        return None
    why = token_print_reason(program, words)
    if why:
        return why
    if program in ("echo", "printf") and ASC_EXPANSION.search(" ".join(words)):
        return "an expansion of the App Store Connect key variables"
    for word in drop_prose(program, words):
        if BARE_CONFIG.search(word):
            return "a bare .config word (a relative path to the key folder)"
        why = names_signing(word)
        if why:
            return why
    return None


#: The one allowed use of the helper: ``[python3 [-I]] <path>/tools/gh_app_token.py check <role>`` and nothing else.
HELPER_COMMAND = re.compile(r"(?:python3?\s+(?:-I\s+)?)?(?P<path>[A-Za-z0-9_./~-]*tools/gh_app_token\.py)\s+check\s+[a-z][a-z0-9-]*")
#: Raw-text patterns (no lexing, case-insensitive) for a Bash command that reaches the key folder or a token.
HOME = r"(?:~|\$\{?home\}?|/users/[^/\s]+|/home/[^/\s]+)"
HOME_CONFIG = HOME + r"/\.config"
#: Home itself as a word: a recursive reader pointed at it reaches ``~/.config/fenton-hass``.
HOME_WORD = r"(?:-C\s*)?" + HOME + r"/?(?=[\s;&|)'\"`]|$)"
RECURSIVE_TOOLS = r"(?:grep|egrep|fgrep|rg|ag|ack|find|tar|cp|rsync|ditto|zip|gtar|bsdtar|mv|ln)"
RAW_KEY_PATTERNS = (
    (re.compile(r"github-apps", re.I), "the github-apps key folder"),
    (re.compile(r"\.pem(?![a-z0-9])", re.I), "a *.pem file"),
    (re.compile(r"\.config\b[^\n]*fenton-has", re.I), "the fenton-hass config folder"),
    (re.compile(r"fenton-has[^\n]*\.config\b", re.I), "the fenton-hass config folder"),
    (re.compile(r"\.config/?\S*[*?\[{\\$'\"]", re.I), "a wildcard, brace, escape or quote inside a .config path"),
    (re.compile(HOME_CONFIG + r"/?(?=[\s;&|)<>'\"`]|$)", re.I), "the .config folder itself (it holds the key folder)"),
    (re.compile(HOME + r"/\.[^/\s]*[*?\[{]", re.I), "a wildcard inside a hidden folder under home"),
    (re.compile(r"(?:^|[;&|(`]\s*|&&\s*)cd(?:\s+" + HOME + r"/?|\s*)(?:\s*[;&|]+|\s*$)[^\n]*\s\.[A-Za-z0-9_-]*[*?\[{]", re.I),
     "a hidden-folder wildcard after cd to home"),
    (re.compile(r"(?:^|[\s;&|(`])" + RECURSIVE_TOOLS + r"\b[^\n;&|]*\s" + HOME_WORD, re.I),
     "a recursive reader or copier aimed at the home folder (it reaches the keys)"),
    (re.compile(r"\b(?:grep|egrep|fgrep|rg|ag|ack|sed|awk)\b[^\n;&|]*private\s+key", re.I), "a search for PRIVATE KEY"),
)
RAW_KEY_PATTERNS += (
    (OWNER_GH, OWNER_GH_WHY),
    (GH_CONFIG_ENV, GH_CONFIG_ENV_WHY),
)
#: ``$'..'`` and ``$".."`` are checked per word, see ``raw_key_reason``.
ANSI_QUOTE = re.compile(r"\$['\"]")
ANSI_NAME = re.compile(r"github|token|\.pe|\.config|app|key", re.I)
RAW_TOKEN_PATTERNS = (
    (re.compile(r"\$\{?!?[A-Za-z_]*(?:GH|GITHUB|APP|INSTALLATION|GHS)[A-Za-z_]*TOKEN", re.I), "an expansion of a GitHub token variable"),
    (re.compile(r"\$\{![A-Za-z_][A-Za-z_0-9]*\}"), "an indirect variable expansion (it can name a token variable)"),
    (re.compile(r"(?<![A-Za-z0-9_])gh[sup]_[A-Za-z0-9_]{16,}|github_pat_[A-Za-z0-9_]{16,}"), "a literal GitHub token"),
    (re.compile(r"environ\W[^\n]{0,60}(?:GH|GITHUB|APP|INSTALLATION)[A-Za-z_]*TOKEN", re.I), "an environment read of a GitHub token"),
    (re.compile(r"\bos\.environ\b(?!\s*(?:\.get\b|\[))|%ENV\b|\bENVIRON\b(?!\s*\[)"), "a read of the whole process environment"),
    (re.compile(r"\bgh\s+auth\s+(?:token|git-credential)\b", re.I), "gh auth token / git-credential (the owner's token)"),
    (re.compile(r"\bgh\s+auth\s+status\b[^\n;&|]*\s(?:-[A-Za-z]*t[A-Za-z]*|--show-token)\b", re.I), "gh auth status --show-token"),
    (re.compile(r"\bgit\s+credential\b|credential-osxkeychain|git-credential", re.I), "git credential helpers (they print the owner's token)"),
    (re.compile(r"\bsecurity\s+[^\n;&|]*find-(?:internet|generic)-password", re.I), "security find-*-password"),
    (re.compile(r"gh_app_token[^\n]*(?:\s-c\b|<<|import|runpy|exec)|(?:\s-c\b|<<|import|runpy|exec)[^\n]*gh_app_token", re.I),
     "the token helper used from code (only `gh_app_token.py check <role>` is allowed)"),
)
#: A dump of the process environment is judged per simple command (``dump_reason``), not on raw text, so a quoted body, an
#: inline-code span or a comment that merely says ``env`` or ``(set)`` runs nothing and passes (#370).
DUMP_PROGRAMS = {"env", "printenv", "set", "export", "declare", "typeset"}
#: A relative path to the key folder as a word (``cd .config``, ``tar -C ~ -cf - .config``); a prose word holds spaces and never equals it.
BARE_CONFIG = re.compile(r"(?:^|=)\.config(?:/|$)", re.I)
PS_ENV_WORD = re.compile(r"-[A-Za-z]*E[A-Za-z]*|e|ew|eww")
#: ``env | grep SIMULATOR``: a dump filtered by a pattern that names no credential is ordinary work.
CREDENTIAL_WORD = re.compile(r"gh|git|tok|secret|key|pass|app|auth|cred|pw|ses", re.I)
#: The documented owner-folder uses: listing the env file's mode, and pausing or resuming the nightly.
ALLOWED_OWNER_FOLDER = re.compile(r"(?:ls\s+-l\s+" + HOME + r"/\.config/fenton-hass/env"
                                  r"|(?:touch|rm|rm\s+-f|ls|ls\s+-l)\s+" + HOME + r"/\.config/fenton-hass/NO_NIGHTLY)", re.I)


def _dump_args(program: str, rest: List[str]) -> bool:
    """Do the words after ``program`` leave it a bare dump of the environment (options only, no variable or command)?"""
    for i, word in enumerate(rest):
        if re.match(r"^\d*[<>]", word):
            rest = rest[:i]  # a redirect ends the arguments
            break
    if program == "set":
        return not rest
    if program in ("printenv", "export", "declare", "typeset"):
        return all(w.startswith("-") for w in rest)
    prev_opt = False  # env: options, each with at most one bare name after it
    for word in rest:
        if word.startswith("-"):
            prev_opt = True
        elif prev_opt and re.fullmatch(r"[A-Za-z_]+", word):
            prev_opt = False
        else:
            return False
    return True


def dump_reason(words: List[str]) -> Optional[str]:
    """``env``, ``printenv``, ``set``, ``export``, ``declare`` or ``typeset`` as the program of a simple command (after keywords, ``VAR=``
    words and wrappers) with nothing but options: a dump of the process environment, which may hold a token."""
    wrapped, prev_opt = False, False
    for i, word in enumerate(words):
        base = os.path.basename(word)
        if base in DUMP_PROGRAMS:
            return "a dump of the process environment (it may hold a token)" if _dump_args(base, words[i + 1:]) else None
        if word in KEYWORDS or re.match(r"^\w+=", word) or base in WRAPPERS:
            wrapped, prev_opt = True, False
        elif wrapped and (word.startswith("-") or prev_opt or re.fullmatch(r"\d+[smhd]?", word)):
            prev_opt = word.startswith("-")
        else:
            return None
    return None


def safe_env_filter(rest: List[tuple]) -> bool:
    """Is the next pipeline segment ``grep [options] PATTERN`` that keeps only lines for a plain pattern naming no credential? An inverted match
    (``-v``), a pattern file (``-f``), a regex that can match anything (``.*``) and an alternation that names a credential word all dump it."""
    if not rest or rest[0][0] != "|":
        return False
    words = rest[0][1]
    if not words or os.path.basename(words[0]) != "grep":
        return False
    patterns: List[str] = []
    args, index = words[1:], 0
    while index < len(args):
        word = args[index]
        index += 1
        if word == "--":
            patterns += args[index:]
            break
        if word.startswith("--"):
            name, _eq, value = word.partition("=")
            if name in ("--invert-match", "--file"):
                return False
            if name == "--regexp":
                patterns.append(value if _eq else (args[index] if index < len(args) else ""))
                index += 0 if _eq else 1
        elif word.startswith("-") and len(word) > 1:
            letters = word[1:]
            if "v" in letters or "f" in letters:
                return False
            if "e" in letters:
                tail = letters.split("e", 1)[1]
                patterns.append(tail or (args[index] if index < len(args) else ""))
                index += 0 if tail else 1
        else:  # every bare word counts (an option's value such as `-A 3` is harmless; a file operand is no safe filter either)
            patterns.append(word)
    return bool(patterns) and all(
        re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_|^$()\\-]*", p) and not CREDENTIAL_WORD.search(p) for p in patterns)


def helper_command(command: str) -> bool:
    """Is ``command`` exactly ``python3 <checkout>/tools/gh_app_token.py check <role>`` for this repo's real helper?"""
    match = HELPER_COMMAND.fullmatch(command.strip())
    if not match:
        return False
    here = os.path.dirname(os.path.dirname(os.path.dirname(os.path.realpath(__file__))))
    roots = {here}
    if "/.claude/worktrees/" in here:
        roots.add(here.split("/.claude/worktrees/")[0])
    target = os.path.realpath(os.path.expanduser(match.group("path")))
    return any(target == os.path.realpath(os.path.join(root, "tools", "gh_app_token.py")) for root in roots)


#: Raw rules that only matter when the text can run: a *name* (the owner's config folder, the whole-environment read) that sits in prose handed to
#: a data command (a quoted ``--body``/``-m`` value, an ``echo`` argument, the body of ``cat > file <<EOF``, ``git commit -F - <<EOF``) is no read (#370).
PROSE_TOLERANT = frozenset({"the fenton-hass config folder", "a read of the whole process environment",
                            "a wildcard, brace, escape or quote inside a .config path",
                            "the .config folder itself (it holds the key folder)", OWNER_GH_WHY, GH_CONFIG_ENV_WHY})


def _scan(command: str, quotes_stripped: bool, skip: frozenset = frozenset()) -> Optional[str]:
    for pattern, why in RAW_KEY_PATTERNS:
        if why not in skip and pattern.search(command):
            return why
    if not quotes_stripped:
        for word in command.split():
            if ANSI_QUOTE.search(word) and ANSI_NAME.search(word):
                return "ANSI-C or locale quoting inside a word that names a key or token"
    for pattern, why in RAW_TOKEN_PATTERNS:
        if why not in skip and pattern.search(command):
            return why
    return None


def _unquoted(text: str) -> str:
    return re.sub(r"[\\'\"]", "", text)


def code_text(command: str) -> Optional[str]:
    """The words of ``command`` that can run, or ``None`` when that cannot be told: the bodies of the data heredocs are gone
    (``merge_guard.drop_cat_heredocs``: ``cat > file``, ``git commit -F -``, ``gh pr create|comment --body-file -``; any other heredoc, a shell
    or interpreter reading it, gives ``None``), and in each simple command the values of git/gh message options and the arguments of
    ``echo``/``printf`` are dropped (:func:`drop_prose`)."""
    try:
        from merge_guard import drop_cat_heredocs
    except ImportError:
        return None
    body_free = drop_cat_heredocs(command)
    if body_free is None:
        return None
    pieces: List[str] = []
    for _op, words in tokenize(body_free):
        stripped = strip_prefixes(list(words))
        program = os.path.basename(stripped[0]) if stripped else ""
        pieces.append(" ".join(drop_prose(program, words)) if stripped else "")
    return "\n".join(pieces)


def raw_key_reason(command: str) -> Optional[str]:
    """Why the raw text of a command (no shell parsing) reaches a key or a token, or ``None``. Scanned twice: as written, and with
    quotes and backslashes removed (``~/.co''nfig``, ``github\\-apps``). The two names in :data:`PROSE_TOLERANT` are judged on the words
    that can run (:func:`code_text`) when those can be told apart, on the raw text otherwise."""
    code = code_text(command)
    skip = PROSE_TOLERANT if code is not None else frozenset()
    why = _scan(command, False, skip) or _scan(_unquoted(command), True, skip)
    if why or code is None:
        return why
    return _scan(code, False) or _scan(_unquoted(code), True)


def command_reason(command: str, depth: int = 0) -> Optional[str]:
    """Why a Bash command touches signing material, a GitHub App key or a token, or ``None``."""
    if depth > 3:
        return "a shell nested too deep to check"
    if depth == 0:
        if helper_command(command) or ALLOWED_OWNER_FOLDER.fullmatch(command.strip()):
            return None
        why = raw_key_reason(command)
        if why:
            return why
    segments = tokenize(command)
    for index, (_op, words) in enumerate(segments):
        why = simple_reason(words, depth)
        if why and not (why.startswith("a dump of the process") and safe_env_filter(segments[index + 1:])):
            return why
    return None


def key_folder_reason(value: str) -> Optional[str]:
    """Is a file-tool path the key folder, below it, or an ancestor of it up to ``~/.config`` (after ``~``, symlinks and case)?"""
    if not value:
        return None
    expanded = os.path.expanduser(value)
    if re.search(r"[*?\[{]", expanded):
        folded = expanded.lower()
        if re.search(r"fenton-has|github-app|\.pem", folded) or re.search(r"\.config/?[^/]*[*?\[{]", folded):
            return "a wildcard that reaches the key folder"
    real = os.path.realpath(expanded).casefold()
    if OWNER_GH_PATH.search(real) or OWNER_GH_PATH.search(expanded.casefold()) or OWNER_GH.search(expanded):
        return "the owner's gh login folder (~/.config/gh-owner)"
    if os.path.basename(real) == "hosts.yml" or hosts_yml_glob(expanded):
        return "a gh hosts.yml (it holds a login token)"
    config = os.path.realpath(os.path.join(os.path.expanduser("~"), ".config")).casefold()
    keys = os.path.join(config, "fenton-hass")
    if real == keys or real.startswith(keys + os.sep) or "/.config/fenton-hass" in real:
        return "the fenton-hass config folder (it holds the GitHub App keys)"
    if real == config or real.endswith("/.config") or keys.startswith(real + os.sep):
        return "a folder above the fenton-hass config folder (a recursive search would reach the keys)"
    if real.endswith(".pem"):
        return "a *.pem file"
    return None


def git_credential_file_reason(value: str) -> Optional[str]:
    """Is a path ``~/.gitconfig``, ``~/.config/git/config|credentials`` or ``~/.git-credentials`` (resolved, case folded)?"""
    real = os.path.realpath(os.path.expanduser(value)).casefold()
    home = os.path.realpath(os.path.expanduser("~")).casefold()
    if any(real == os.path.join(home, name) for name in GIT_CRED_FILES):
        return "a global git config or credentials file (the credential helper chooses the GitHub login)"
    return None


def path_reason(tool: str, tool_input: dict) -> Optional[str]:
    """Why a file tool's target is signing material, a GitHub App key or the gh/git login, or ``None``."""
    keys = {"Grep": ("path", "glob"), "Glob": ("path", "pattern")}.get(tool, ("file_path", "notebook_path"))
    for key in keys:
        value = str(tool_input.get(key) or "")
        why = (names_signing(value) or key_folder_reason(value)) if value else None
        if not why and value and tool in ("Edit", "Write", "MultiEdit", "NotebookEdit"):
            why = git_credential_file_reason(value)
        if why:
            return why
    return None


def main(argv: Optional[List[str]] = None) -> int:
    """Read the hook payload from stdin; exit 2 with ``MESSAGE`` to block."""
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        return 0
    tool = payload.get("tool_name")
    if tool not in ("Bash", *PATH_TOOLS) or not agent_session(payload):
        return 0
    tool_input = payload.get("tool_input") or {}
    why = command_reason(str(tool_input.get("command") or "")) if tool == "Bash" else path_reason(str(tool), tool_input)
    if why:
        print(f"{MESSAGE} (matched: {why})", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
