#!/usr/bin/env python3
"""PreToolUse hook for Bash, Read, Grep, Glob, Edit, Write, MultiEdit and NotebookEdit: the owner's Studio is reached only through the Studio's own publish CLI.

Owner decision 2026-11-16: agents may publish a finished change to the Studio draft, but only by the publish CLI that lives in the Studio repository
(``scripts/studio-publish.ts``, documented in that repository's ``docs/agent-publish.md``). Port 4801 runs
local-only with no token, so any local process could publish to the house with the Studio's own Home Assistant
credential; this guard is what stops another agent process. It is a tripwire, not a wall: it reads command text only.

Acts on **agent sessions** (``FENTON_HEADLESS=1``, or a payload with ``agent_type`` or ``agent_id``); the owner's plain terminal is never blocked.

Blocked, in an agent session:

- **File tools** (Read, Grep, Glob, Edit, Write, MultiEdit, NotebookEdit) on a path with a ``native-v2`` segment, the ``.studio.lock`` file, or
  a ``data`` folder inside a Studio checkout (``ha-native-home-app``, ``studio-releases``): the Studio's data directory holds the draft and
  the house layout, and the server keeps the draft in memory, so a file edit is overwritten or corrupts the next start.
- **Bash**, per simple command (quote-aware; ``bash -c`` and ``eval`` strings, ``xargs`` and wrappers unwrapped), any word that names the Studio's
  write or publish routes (``/native/api/draft``, ``ha/publish``, ``ha/rollback``, ``ha/restore-draft``, ``ha/start-from-published``,
  ``/native/api``), whatever the program, except that ``grep``, ``rg``, ``ag``, ``ack`` and ``git log|grep|show|diff`` may name a route as a search
  pattern (a ``git config alias.*`` or ``git -c alias.*`` stays blocked); a word naming a Studio port (``:4800``, ``:4801``, ``:4819``) when the program is a network client or an
  interpreter (curl, wget, httpie, nc, python, node, ...); a word that names ``native-v2`` or ``.studio.lock`` (a bare ``native-v2`` is allowed as
  a search pattern); ``$DATA_DIR`` expanded.
- **Exempt:** one exact form, the whole simple command, and only for a real Studio checkout (a directory with ``package.json`` named
  ``native-home-studio``, a ``.git`` entry and ``scripts/studio-publish.ts``): ``<checkout>/node_modules/.bin/tsx <checkout>/scripts/studio-publish.ts <sub> ...``
  (absolute, or relative to a cwd inside a checkout; no ``..`` segment, no other tsx option; the script must resolve to ``scripts/studio-publish.ts``
  of the checkout; a relative path is read against the cwd after any earlier ``cd``, and refused when that ``cd`` cannot be followed); there is no npm form.
  The data-directory rules still apply to the exempt form's words, redirect targets and ``--log`` (native-v2, ``.studio.lock``, ``$DATA_DIR``,
  ``<checkout>/data``), and a ``NODE_*``, ``TSX_*``, ``LD_*`` or ``DYLD_*`` variable in front of it is refused. Of its subcommands ``apply``, ``publish``,
  ``rollback`` and ``resolve`` run only for ``agent_type`` ``orchestrator`` or ``menial`` (lanes build changes; the dispatched publish step publishes) and never
  in a headless session; ``status`` and ``check`` run for every agent. Any other word naming the CLI (``studio-publish``, ``studio:publish``,
  ``studio_publish``) in a command that runs code is refused, except the record store ``studio-publish/<id>/...`` and its ``studio-publish.jsonl`` log; a test file such as ``tests/studio-publish.test.ts`` is not the CLI.

Prose in a ``git commit -m`` or ``gh --body`` value is not read. Heredocs: when any simple command in the line runs code (an interpreter, shell,
network client or task runner), every heredoc body is read for routes, ports, the data directory and the tool's name, whichever line opens it
(``python3 - <<EOF``, ``cat <<EOF | python3 -``, ``cat > x.py <<EOF`` then ``python3 x.py``). Only a heredoc whose own command is ``git`` or ``gh``
(``git commit -F - <<EOF``) is skipped. A command piped into or out of code has its ports read too; a separate command (``lsof -i :4801 && python3 x.py``)
does not. Same limits as ``signing_guard``: a path or URL built at run time, a script file that opens the URL, and a Write whose content runs later
are not seen. Exit 2 sends the message back.
"""

from __future__ import annotations

import json
import os
import re
import sys
from typing import List, Optional

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from shell_parse import SHELLS, strip_prefixes, tokenize, unwrap_xargs  # noqa: E402

try:  # the registry of T3-launched triage sessions: a registered session gets the runner's markers
    import triage_session
except Exception:  # noqa: BLE001
    triage_session = None

MESSAGE = (
    "Blocked: the owner's Studio draft and publication change only through the Studio's publish CLI "
    "(`<studio checkout>/node_modules/.bin/tsx <studio checkout>/scripts/studio-publish.ts <command>`, docs/agent-publish.md in the Studio repository) "
    "(status, check, apply, publish, rollback, resolve), run by the dispatched publish step. Do not call the Studio API or touch its data directory "
    "yourself. If the tool cannot do what you need, report `needs_decision`."
)
TOOL = "studio-publish.ts"
STUDIO_PACKAGE = "native-home-studio"
PATH_TOOLS = ("Read", "Grep", "Glob", "Edit", "Write", "MultiEdit", "NotebookEdit")
#: Subcommands that change the draft or the live publication; roles that may run them.
MUTATING = ("apply", "publish", "rollback", "resolve")
PUBLISHERS = ("orchestrator", "menial")

ROUTE = re.compile(r"/?native/api(?![A-Za-z0-9_-])|(?<![A-Za-z0-9_])ha/(?:publish|rollback|restore-draft|start-from-published)(?![A-Za-z0-9_-])", re.I)
PORT = re.compile(r":(?:4800|4801|4819)(?![0-9])")
PORT_WORD = re.compile(r"^(?:4800|4801|4819)$")
NATIVE_V2 = re.compile(r"native-v2[/\\]|[/\\]native-v2", re.I)
BARE_NATIVE_V2 = re.compile(r"^native-v2$", re.I)
LOCK = re.compile(r"\.studio\.lock", re.I)
DATA_DIR_VAR = re.compile(r"\$\{?DATA_DIR(?![A-Za-z0-9_])")
#: The data folder at the root of a Studio checkout only (``<checkout>/data``): source folders such as ``src/workspace2/data`` stay open.
STUDIO_DATA = re.compile(r"(?:ha-native-home-app|studio-releases)(?:[/\\][^/\\]+)?[/\\]data(?:[/\\]|$)", re.I)
#: A word that names the CLI (``scripts/studio-publish.ts``, ``studio:publish``, ``import studio_publish``) but not ``test_studio_publish`` or a test file
#: such as ``tests/studio-publish.test.ts``, nor the record store ``studio-publish/<id>/...`` and its log ``studio-publish.jsonl``.
TOOL_WORD = re.compile(r"(?<![A-Za-z0-9_-])studio[_:-]publish(?![A-Za-z0-9_-]|\.test\.|/|\.jsonl(?![A-Za-z0-9_.-]))", re.I)
HEREDOC = re.compile(r"<<-?\s*(['\"]?)(\w+)\1[^\n]*\n(.*?)(?:\n\s*\2\s*(?:\n|$)|\Z)", re.S)
#: Programs that run code or other programs: a word naming the tool is refused for them unless it is the exact exempt form.
RUNNERS = {"uv", "uvx", "pipx", "poetry", "pdm", "hatch", "tox", "pytest", "make", "just", "npm", "pnpm", "yarn"}
#: Searchers read text; a route named as their pattern is not a call (``git`` reads are judged by ``git_reads``).
SEARCH_ONLY = {"grep", "egrep", "fgrep", "rg", "ag", "ack"}
#: ``git`` subcommands that only read; ``git config alias.x "!curl ..."`` and ``git -c alias.x=...`` are not among them.
GIT_READS = {"log", "grep", "show", "diff"}
NETWORK = {"curl", "wget", "http", "https", "xh", "httpie", "nc", "ncat", "netcat", "telnet", "socat", "ssh", "node", "nodejs", "deno",
           "bun", "ruby", "perl", "php", "npx", "tsx", "ts-node", "pwsh", "osascript", "python", "python2", "python3", "lua", "go"}
SEARCHERS = {"grep", "egrep", "fgrep", "rg", "ag", "ack", "sed", "awk"}
PROSE_OPTIONS = {"-m", "--message", "--body", "-b", "--title", "-t", "--notes", "--note", "--subject"}
SHELL_C = re.compile(r"^-[A-Za-z]*c[A-Za-z]*$")


def agent_session(payload: dict) -> bool:
    """Is this an agent session (headless, or a payload with ``agent_type`` or ``agent_id``)?"""
    return os.environ.get("FENTON_HEADLESS") == "1" or bool(payload.get("agent_type")) or bool(payload.get("agent_id"))


def program_of(base: str) -> str:
    """The program name with a version suffix dropped (``python3.11`` -> ``python3``)."""
    return re.sub(r"(?<=\D)[0-9.]+$", "", base) if base.startswith("python") else base


def studio_root(path: str) -> str:
    """The real path of the Studio checkout that holds ``path`` (or that is ``path``), or ``""``.

    A Studio checkout is a git worktree of the Studio repository: a directory with a ``.git`` entry, a ``package.json`` named
    ``native-home-studio`` and a ``scripts/studio-publish.ts`` file. The walk up stops after 8 levels."""
    current = os.path.realpath(path or os.getcwd())
    for _ in range(8):
        package = os.path.join(current, "package.json")
        if os.path.exists(os.path.join(current, ".git")) and os.path.isfile(package) and os.path.isfile(os.path.join(current, "scripts", TOOL)):
            try:
                with open(package, "r", encoding="utf-8") as handle:
                    if json.load(handle).get("name") == STUDIO_PACKAGE:
                        return current
            except (OSError, ValueError, AttributeError):
                pass
        parent = os.path.dirname(current)
        if parent == current:
            break
        current = parent
    return ""


def absolute(word: str, cwd: Optional[str]) -> Optional[str]:
    """``word`` as an absolute path against ``cwd`` (``~`` expanded), or ``None`` when it has a ``.`` or ``..`` segment (a traversal trick)
    or is relative while ``cwd`` is unknown (after a ``cd`` whose target the guard cannot follow)."""
    given = os.path.expanduser(word)
    if any(part in ("..", ".") for part in given.split("/")[1:]) or given.startswith("../") or given == "..":
        return None
    if os.path.isabs(given):
        return given
    return os.path.join(cwd, given) if cwd else None


def is_tool_call(words: List[str], payload: dict, project: str) -> Optional[List[str]]:
    """The CLI's arguments (subcommand first) when ``words`` is exactly the exempt form, else ``None``.

    ``<checkout>/node_modules/.bin/tsx <checkout>/scripts/studio-publish.ts ...``: both paths in a real Studio checkout, and the script's real path
    is ``<checkout>/scripts/studio-publish.ts``."""
    cwd = None if payload.get("_cd_unknown") else str(payload.get("cwd") or project or os.getcwd())
    if len(words) >= 3 and os.path.basename(words[0]) == "tsx" and (words[0] == "node_modules/.bin/tsx" or words[0].endswith("/node_modules/.bin/tsx")):
        tsx, script = absolute(words[0], cwd), absolute(words[1], cwd)
        if tsx is None or script is None:
            return None
        home = os.path.dirname(os.path.dirname(os.path.dirname(tsx)))  # <checkout>/node_modules/.bin/tsx -> <checkout>, and it must be the root itself
        if not studio_root(home) or studio_root(home) != os.path.realpath(home):
            return None
        real = os.path.realpath(script)
        root = studio_root(os.path.dirname(os.path.dirname(real)))
        if root and real == os.path.join(root, "scripts", TOOL):
            return words[2:]
        return None
    return None


def tool_reason(args: List[str], payload: dict) -> str:
    """Why a call of the CLI is refused: a mutating subcommand outside the publisher roles, or an unknown subcommand."""
    words = [a for a in args if not a.startswith("-")]
    # argparse takes global options (``--log PATH``, and abbreviations of it) before the subcommand: any mutating word is a mutating call.
    sub = next((a for a in words if a in MUTATING), "") or next((a for a in words if a in ("status", "check")), "")
    if sub in MUTATING:
        if os.environ.get("FENTON_HEADLESS") == "1" or payload.get("agent_type") not in PUBLISHERS:
            return f"`{sub}` runs only in the orchestrator's dispatched publish step"
    elif sub not in ("status", "check"):
        return "unknown studio-publish subcommand"
    return ""


#: ``git -c KEY=VALUE`` keys that cannot run a command (``diff.external``, ``core.pager``, ``alias.*`` and ``core.sshCommand`` can).
GIT_SAFE_CONFIG = re.compile(r"(?:color\.[\w.]+|core\.quotepath|diff\.(?:renames|algorithm|context))=", re.I)
#: Options of the read subcommands that run a program.
GIT_RUNS = re.compile(r"^(?:--open-files-in-pager|--ext-diff|--textconv|--exec|--upload-pack)", re.I)
#: ``-O`` alone or bundled anywhere in a short-option word (``-nO'cmd'``): git grep's pager option, which runs a program.
GIT_PAGER_SHORT = re.compile(r"^-(?!-)[A-Za-z]*O")


def git_reads(words: List[str]) -> bool:
    """Is this ``git`` call a read (``log``, ``grep``, ``show``, ``diff``) that cannot run a program?

    ``-c`` is allowed only for keys in ``GIT_SAFE_CONFIG``; ``-O``, ``--open-files-in-pager``, ``--ext-diff`` and ``--textconv`` anywhere refuse."""
    rest = words[1:]
    while rest and rest[0].startswith("-"):
        option = rest[0]
        if option == "-c" and len(rest) > 1:
            if not GIT_SAFE_CONFIG.match(rest[1]):
                return False
            rest = rest[2:]
        elif option in ("-C", "--git-dir", "--work-tree") and len(rest) > 1:
            rest = rest[2:]
        elif option.startswith("-c") and len(option) > 2:
            return False
        else:
            rest = rest[1:]
    return bool(rest) and rest[0] in GIT_READS and not any(GIT_RUNS.match(w) or GIT_PAGER_SHORT.match(w) for w in rest[1:])


#: Variables that make node, tsx or the loader run code of their own: refused as a prefix of the exempt form.
LOADER_VAR = re.compile(r"(?<![A-Za-z0-9_])(?:NODE_\w*|TSX_\w*|LD_\w*|DYLD_\w*)=", re.I)
#: A word that is, or starts with, a redirect operator or ``--option=``: the path it carries is the part after.
PATH_PREFIX = re.compile(r"^(?:[0-9]*>>?&?|&>>?|--[A-Za-z-]+=)")


def word_reason(word: str, *, network: bool, interp: bool, reads_text: bool, searcher: bool, data_only: bool = False) -> str:
    """Why one word of a simple command is refused: a Studio route, port or data-directory name. ``data_only`` skips the route and port rules
    (the exempt CLI may name its own base URL)."""
    if not data_only:
        if ROUTE.search(word) and not reads_text:
            return "a Studio API route"
        if (network or interp) and not reads_text and (PORT.search(word) or PORT_WORD.match(word)):
            return "a Studio port"
    if NATIVE_V2.search(word) or LOCK.search(word):
        return "the Studio's data directory"
    if BARE_NATIVE_V2.match(word) and not searcher:
        return "the Studio's data directory"
    if DATA_DIR_VAR.search(word) or STUDIO_DATA.search(word):
        return "the Studio's data directory"
    return ""


def checkout_data(word: str, cwd: Optional[str], root: str) -> bool:
    """Does the path in ``word`` (a redirect target, ``--log=PATH`` or a plain path) resolve into ``<checkout>/data``?"""
    path = PATH_PREFIX.sub("", word)
    if not path:
        return False
    given = os.path.expanduser(path)
    if not os.path.isabs(given):
        if not cwd:
            return False
        given = os.path.join(cwd, given)
    real = os.path.realpath(given)
    return real == os.path.join(root, "data") or real.startswith(os.path.join(root, "data") + os.sep)


def words_reason(words: List[str], payload: dict, project: str, depth: int = 0, interp: bool = False) -> str:
    """Why one simple command is refused (empty when it passes)."""
    original = words
    words = strip_prefixes(words)
    if not words or depth > 3:
        return ""
    base = os.path.basename(words[0])
    program = program_of(base)
    try:
        prefix = original[:original.index(words[0])]
    except ValueError:
        prefix = original  # an ``env -S`` string: judge the whole text
    args = is_tool_call(words, payload, project)
    if args is not None:
        if LOADER_VAR.search(" ".join(prefix)):
            return "a loader variable (NODE_*, TSX_*, LD_*, DYLD_*) in front of the publish CLI"
        cwd = None if payload.get("_cd_unknown") else str(payload.get("cwd") or project or os.getcwd())
        root = studio_root(os.path.dirname(os.path.dirname(os.path.dirname(absolute(words[0], cwd) or "/"))))
        for word in [*prefix, *words[1:]]:
            why = word_reason(word, network=True, interp=False, reads_text=False, searcher=False, data_only=True)
            if why or (root and checkout_data(word, cwd, root)):
                return why or "the Studio's data directory"
        return tool_reason(args, payload)
    for word in prefix:
        why = word_reason(word, network=program in NETWORK, interp=interp, reads_text=False, searcher=False)
        if why:
            return why
    if base == TOOL:  # run directly: the CLI runs only through tsx from a Studio checkout
        return "studio-publish.ts run directly or outside a Studio checkout"
    if (program in NETWORK or program in RUNNERS or program in SHELLS) and any(TOOL_WORD.search(w) for w in words[1:]):
        return "the publish CLI named other than as the exact tsx form in a Studio checkout"
    if program == "xargs":
        return words_reason(unwrap_xargs(words[1:]), payload, project, depth + 1)
    if program in SHELLS or program == "eval":
        for i, w in enumerate(words[1:], 1):
            if (program == "eval" and i == 1) or (program in SHELLS and SHELL_C.match(words[i - 1] if i else "")):
                for _op, inner in tokenize(w):
                    why = words_reason(inner, payload, project, depth + 1)
                    if why:
                        return why
        if program == "eval":
            for _op, inner in tokenize(" ".join(words[1:])):
                why = words_reason(inner, payload, project, depth + 1)
                if why:
                    return why
    searcher = program in SEARCHERS
    reads_text = program in SEARCH_ONLY or (program == "git" and git_reads(words))
    prose = False
    network = program in NETWORK
    for i, word in enumerate(words[1:], 1):
        if prose:
            prose = False
            continue
        if word in PROSE_OPTIONS:
            prose = True
            continue
        why = word_reason(word, network=network, interp=interp, reads_text=reads_text, searcher=searcher)
        if why:
            return why
    return ""


def runs_code(words: List[str]) -> bool:
    """Does this simple command run code (an interpreter, a shell, a network client or a task runner)?"""
    words = strip_prefixes(words)
    if not words:
        return False
    program = program_of(os.path.basename(words[0]))
    return program in NETWORK or program in SHELLS or program in RUNNERS


def prose_heredoc(command: str, match: "re.Match[str]") -> bool:
    """Is the command that opens this heredoc prose (``git commit -F - <<EOF``, ``gh ... --body-file - <<EOF``), whose body is a message, not code?"""
    start = command.rfind("\n", 0, match.start()) + 1
    end = command.find("\n", match.start())
    for _op, words in tokenize(command[start:end if end >= 0 else len(command)]):
        if any(w.startswith("<<") for w in words):
            words = strip_prefixes(words)
            return bool(words) and os.path.basename(words[0]) in ("git", "gh")
    return False


def follow_cd(payload: dict, segments: list, previous: int) -> dict:
    """The payload as segment ``previous + 1`` sees it: its cwd after the ``cd`` in segment ``previous``. A ``cd`` the guard cannot follow
    (a variable, ``-``, no argument, ``pushd``/``popd``, or one joined by ``||``, a pipe or ``&``) leaves the cwd unknown (``_cd_unknown``),
    so a relative path in the exempt form is refused."""
    if previous < 0:
        return payload
    words = strip_prefixes(segments[previous][1])
    if not words or os.path.basename(words[0]) not in ("cd", "pushd", "popd", "chdir"):
        return payload
    following = segments[previous + 1][0] if previous + 1 < len(segments) else ""
    target = words[1] if len(words) > 1 else ""
    if payload.get("_cd_unknown") or os.path.basename(words[0]) != "cd" or following in ("||", "|", "|&", "&") or not target or target.startswith("-") or "$" in target or "`" in target:
        return dict(payload, _cd_unknown=True)
    given = os.path.expanduser(target)
    base = str(payload.get("cwd") or "")
    return dict(payload, cwd=os.path.normpath(given if os.path.isabs(given) else os.path.join(base, given)))


def command_reason(command: str, payload: dict, project: str) -> str:
    """Why a Bash command is refused (empty when it passes).

    When any simple command runs code (an interpreter, shell, network client or task runner), every heredoc body is read for routes, ports, the data
    directory and the tool's name, whatever line opens it: ``python3 - <<EOF``, ``cat <<EOF | python3 -``, and ``cat > x.py <<EOF`` followed by
    ``python3 x.py`` (write, then run). Only a heredoc whose own command is prose (``git commit -F -``, ``gh ... --body-file -``) is skipped.
    A command piped into or out of code has its ports read too (``echo '...:4801...' | python3 -``)."""
    segments = tokenize(command)
    code = [runs_code(words) for _op, words in segments]
    for i, (_op, words) in enumerate(segments):
        payload = follow_cd(payload, segments, i - 1)
        # a command that feeds, or is fed by, code through a pipe counts as part of that code's input
        piped = (i > 0 and segments[i][0].startswith("|") and code[i - 1]) or (i + 1 < len(segments) and segments[i + 1][0].startswith("|") and code[i + 1])
        why = words_reason(words, payload, project, interp=bool(piped))
        if why:
            return why
    if any(code):
        for match in HEREDOC.finditer(command):
            if prose_heredoc(command, match):
                continue
            body = match.group(3)
            if ROUTE.search(body) or PORT.search(body) or NATIVE_V2.search(body) or LOCK.search(body) or TOOL_WORD.search(body) or DATA_DIR_VAR.search(body):
                return "a heredoc in a command that runs code names the Studio"
    return ""


def path_reason(tool_input: dict) -> str:
    """Why a file tool is refused: the path (``~`` and symlinks resolved) is in the Studio's data directory."""
    path = str(tool_input.get("file_path") or tool_input.get("notebook_path") or tool_input.get("path") or "")
    pattern = str(tool_input.get("pattern") or "")
    for text in (path, os.path.realpath(os.path.expanduser(path)) if path else "", pattern):
        if text and (NATIVE_V2.search(text) or LOCK.search(text) or STUDIO_DATA.search(text)):
            return "the Studio's data directory"
    return ""


def main(argv: Optional[List[str]] = None) -> int:
    """Read the hook payload from stdin; exit 2 with ``MESSAGE`` to block."""
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        return 0
    if triage_session:
        triage_session.apply(payload)
    tool = payload.get("tool_name")
    if tool not in ("Bash", *PATH_TOOLS) or not agent_session(payload):
        return 0
    tool_input = payload.get("tool_input") or {}
    project = os.path.realpath(os.environ.get("CLAUDE_PROJECT_DIR") or str(payload.get("cwd") or os.getcwd()))
    if tool == "Bash":
        why = command_reason(str(tool_input.get("command") or ""), payload, project)
    else:
        why = path_reason(tool_input)
    if why:
        print(f"{MESSAGE} (matched: {why})", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
