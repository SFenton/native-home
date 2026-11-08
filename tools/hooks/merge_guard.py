#!/usr/bin/env python3
"""PreToolUse hook for Bash: agents land pull requests only through ``tools/pr_land.sh``.

On a private Free repository GitHub enforces no rulesets, so `pr_land.sh` (the configured checks and an independent recorded review) is the
gate and this hook closes the bypasses: ``gh pr merge``, ``gh api …/pulls/N/merge`` (and ``…/merges``), the GraphQL
merge mutations, a PUT or DELETE on ``/contents/`` and a ``git push`` that lands on main or master.

A command that is exactly ``tools/pr_land.sh ARGS`` (also ``./tools/…`` or this repository's absolute path) with no
shell metacharacters is allowed. Any other command is scanned whole: it is split into simple commands on ``; && || | &``,
parentheses, braces, backticks, ``$(`` and the keywords ``then do else elif if while until``; wrappers (``env``,
``command``, ``exec``, ``nohup``, ``time``, ``xargs``, ``sudo``, ``VAR=`` prefixes) are stripped; the program is compared
by basename; ``git`` global options are skipped; ``bash -c`` and ``eval`` strings are scanned too.

Headless allow-list (``FENTON_HEADLESS=1``, the triage runner's sessions; owner decision 2026-11-02, the runner merges and
the agent does not): a ``git push`` is allowed only as ``git push [harmless flags] origin REFSPEC...`` where every refspec
targets ``refs/heads/agents/*`` (``agents/x``, ``HEAD:agents/x``, ``refs/heads/agents/x``). Everything else is blocked: a bare
``git push``, a ``HEAD`` or branch-name refspec whose destination depends on the checkout, any ``+`` or ``--force*``,
``--all``, ``--mirror``, ``--tags``, ``--delete``, glob or delete refspecs, another remote or URL, a push inside ``-C``,
``git -c ...``, ``xargs``, ``timeout`` and other wrappers, subshells, ``bash -c`` and ``eval``, an alias (``-c alias.*``,
``git config alias.*``), ``git send-pack`` and ``http-push``, ``tools/lane_land.py`` (the runner lands), ``hass_triage.py ack-base`` (owner only), writes to the git
refs, branches, merges or contents API, and any command that mentions ``git`` and ``push`` through a shell expansion or that
cannot be parsed. Merging locally is harmless now: only the runner, from its own land clone, moves the workflow base.

Request-repo writes (owner decision 2026-11-03, headless only; the repository comes from ``tools/request_repo.py``: ``FENTON_REQUEST_REPO`` or the local ``request_repo`` file, see
.agents/workflow/triage-agent.md; with none configured every guarded write is refused against any repository): a
headless session may not ``gh issue edit`` an issue of the request repository, and may ``gh issue create`` there only with a
``Workflow`` label (``--label Workflow``, ``-l Workflow``, ``--label=Workflow``, ``-lWorkflow``, or a comma list holding it). The
target is the ``-R``/``--repo`` value (``--repo=X``, ``-RX``), a ``GH_REPO=`` prefix, or any argument naming the repository
(an issue URL). The same holds for ``gh api`` writes to ``repos/<request repo>/issues``. Words come from a quote-aware lexer, so
a title or body that merely mentions ``--label Workflow`` does not count. An interactive owner session is never affected.

Going public (owner, 2026-11-07, end-to-end autonomy): the only way is exactly ``tools/go_public.sh SNAPSHOT_DIR OWNER/REPO``, which runs
``tools/go_public_gate.py`` first. ``gh repo create --public|--internal``, ``gh repo edit --visibility`` (but ``private``), a visibility change through ``gh api``
and a ``git push`` to a remote other than this repository's origin are refused in every session; an agent session may run ``go_public.sh`` only in that
form, from a checkout whose ``go_public.sh``, ``go_public_gate.py``, ``house_scan.py`` and config equal the base's. An agent session also runs
``tools/lane_land.py`` only from a checkout whose ``lane_land.py``, ``release_closure.py`` and config equal the base's.

One exemption (owner decision 2026-11-04, merge-guard false positives): the raw scan above stays the decision for everything, and
a block is dropped only when ``exempt`` holds: every simple command of the whole input is a grep, rg, cat, head, tail, less, ls,
wc, echo, mkdir, ``git log|show|diff|status|commit``, ``gh pr view|list`` or ``python3`` of a script in ``EXEMPT_SCRIPTS`` (tools/tasks.py
and a few more that never run their arguments), and the input has no ``$'``/``$"``/``${``/``printf -v``, substitution, subshell, ``/dev/stdin``, shell, other interpreter, ``find``,
``sed``, ``awk``, ``xargs``, ``env`` or other wrapper, and no heredoc but ``cat > file <<WORD``, ``cat <<WORD > file``, ``git commit -F - <<WORD`` and ``gh pr create|comment --body-file - <<WORD`` (whose body is then data).
Anything else, and any parse failure, keeps the raw verdict.

Out of scope (the model could still reach a merge): ``curl``, interpreters (``python -c``) and script files that call
GitHub. The deny list in the triage config and the owner's review of the diff cover those. Exit 2 sends the message back.
"""

from __future__ import annotations

import json
import os
import re
import shlex
import subprocess
import sys
from pathlib import Path
from typing import Dict, List, Optional

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import request_repo as request_repo_module  # noqa: E402
from shell_parse import FEEDERS, scan_shell, strip_prefixes, tokenize as _tokenize, unwrap_xargs  # noqa: E402

MESSAGE = (
    "Blocked: agents merge only through `tools/pr_land.sh N` (its gate: the configured checks and a recorded independent review), never with "
    "`gh pr merge`, `gh api …/merge` or a push to main. Run the reviewer (tools/review/record.py) then "
    "`tools/pr_land.sh N`. The one exception is SFenton/native-home: `gh pr merge N -R SFenton/native-home --squash --auto "
    "--match-head-commit SHA` after the reviewer's pass comment for that head (or `--disable-auto` to disarm). See .agents/workflow/pr-lifecycle.md."
)

REQUEST_MESSAGE = (
    "Blocked: a headless session may not edit issues of the request repository, and creates one there only with the "
    "`Workflow` label (`gh issue create --label Workflow ...`). Owner requests are the owner's to change; file agent work as a "
    "`Workflow` issue. See .agents/workflow/agent-roster.md (what code enforces today)."
)

LAND_MESSAGE = (
    "Blocked: landing is the owner's path. Agents run exactly `tools/pr_land.sh N [--dry-run]` from a checkout whose pr_land matches the "
    "base branch; `--owner-ack`, a pty wrapper, changing FENTON_HEADLESS/HASS_TRIAGE_* and wrapping pr_land are refused. "
    "See .agents/workflow/agent-roster.md (what code enforces today)."
)

REPO = Path(__file__).resolve().parents[2]
METACHARS = re.compile(r"[;&|(){}`$<>\\\n\r\"']")
SPLIT = re.compile(r"&&|\|\||\$\(|[;|&(){}`\n]|\b(?:then|do|else|elif|if|while|until)\b")
#: Wrapper programs and the options of each that take a value (so ``env -u X gh …`` still finds ``gh``).
WRAPPERS = {"env": {"-u", "-C", "-S", "--unset", "--chdir"}, "command": set(), "exec": {"-a"}, "nohup": set(),
            "time": {"-f", "-o"}, "xargs": {"-I", "-n", "-L", "-P", "-d", "-E", "-s"},
            "sudo": {"-u", "-g", "-C", "-h", "-p", "-r", "-t", "-U"}, "nice": {"-n"}, "builtin": set()}
SHELL_C = re.compile(r"^-[A-Za-z]*c[A-Za-z]*$")
PIPE_TO_SHELL = re.compile(r"\|\s*(?:env\s+)?(?:\S*/)?(?:bash|sh|zsh|dash)(?:\s|$)")
HERE_TO_SHELL = re.compile(r"(?:^|[\s;&|(])(?:\S*/)?(?:bash|sh|zsh|dash)\b[^\n;&|]*<<")
API_WHOLE = re.compile(r"\bgh\b.*\bapi\b", re.S)
SHELLS = {"bash", "sh", "zsh", "dash"}
MAIN_REF = re.compile(r"^\+?(?:[^:]*:)?(?:refs/heads/)?(?:main|master)$")
MERGE_URL = re.compile(r"/pulls/[^/\s]+/merge|/merges\b|/git/refs/heads/(?:main|master)\b")
GRAPHQL_MERGE = re.compile(r"mergePullRequest|enablePullRequestAutoMerge")
WRITE_METHOD = re.compile(r"(?:-X\s*|--method[ =]\s*)(?:PUT|DELETE)\b", re.I)
GIT_VALUE_OPTS = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--super-prefix", "--exec-path"}
GH_VALUE_OPTS = {"-R", "--repo", "--hostname"}


LANE_MESSAGE = (
    "Blocked: a headless session pushes only lane branches: `git push origin HEAD:agents/NAME` or `git push origin agents/NAME` "
    "(explicit `agents/*` refspecs, no force). The runner reviews, tests and merges the lane into the workflow base; "
    "list the branch in the status file's `lanes`."
)
#: Push flags that cannot change which refs are updated.
SAFE_PUSH_FLAGS = {"-u", "--set-upstream", "-q", "--quiet", "-v", "--verbose", "-n", "--dry-run", "--no-verify", "--verify",
                   "--porcelain", "--progress", "--no-progress", "--thin", "--no-thin", "--atomic", "--no-atomic"}
AGENT_DEST = re.compile(r"^(?:refs/heads/)?agents/[A-Za-z0-9][A-Za-z0-9._/-]*$")
EXPANSION = re.compile(r"\$|`")
GIT_WORD = re.compile(r"\bgit\b")
PUSH_WORD = re.compile(r"\bpush\b")
GH_REF_API = re.compile(r"/git/(?:refs|commits|trees|tags|blobs)|/merges\b|/contents/|/branches/|/refs/heads/")
GH_WRITE = re.compile(r"(?:-X\s*|--method[ =]\s*)(?!GET\b)\w+|(?:^|\s)-[fF]\b|--field\b|--raw-field\b|--input\b", re.I)
#: Directory of the payload being scanned (set by ``reason``) so ``-C`` can be resolved.
_CWD: Optional[str] = None
#: The payload had an ``agent_type`` or ``agent_id`` (an agent session that is not necessarily the runner's headless one).
_AGENT = False


def agent_session() -> bool:
    """Headless runner session, or any session whose payload carries ``agent_type``/``agent_id`` (a ``--agent`` main thread, a subagent)."""
    return _AGENT or headless()


def headless() -> bool:
    """Is this the triage runner's headless session (the agent may only push lane branches)?"""
    return os.environ.get("FENTON_HEADLESS") == "1"


# MARK: - pr_land, lane_land and the session markers (headless)

OWNER_OPTION = re.compile(r"--owner", re.I)
#: Taking the headless markers away from a command: unset/env -u/env -i, or an assignment of anything but `FENTON_HEADLESS=1`.
ENV_TAMPER = (
    re.compile(r"\bunset\b[^;&|\n]*\b(?:FENTON_HEADLESS|HASS_TRIAGE_\w+)\b"),
    re.compile(r"\benv\s+(?:(?:-[A-Za-z]+|--\S+|\w+=\S*)\s+)*(?:-[A-Za-z]*i|--ignore-environment|-u\s*(?:FENTON_HEADLESS|HASS_TRIAGE_\w+)|"
               r"--unset[= ]\s*(?:FENTON_HEADLESS|HASS_TRIAGE_\w+)|-)(?=\s|$)"),
    re.compile(r"\bFENTON_HEADLESS\s*=\s*(?!1\b)"),
    re.compile(r"\bHASS_TRIAGE_(?:ISSUE|INTAKE|PAUSED_FILE|BIN|STATUS_FILE)\s*="),
    re.compile(r"\b(?:export|declare|typeset)\s+-[a-zA-Z]*n?\s*(?:FENTON_HEADLESS|HASS_TRIAGE_\w+)\s*$"),
)
PTY_WRAPPER = re.compile(r"(?:^|[\s;&|(`])(?:\S*/)?(?:script|expect|unbuffer|faketty|socat|screen|tmux)(?=\s|$)")
LAND_WORDS = re.compile(r"pr_land|lane_land|ack[-_]?base")
INTERPRETERS = re.compile(r"^(?:python[\d.]*|bash|sh|zsh|dash|source|\.)$")


def runs_pr_land(command: str) -> bool:
    """Does a simple command of ``command`` execute ``pr_land.sh``/``pr_land.py`` (directly, or through an interpreter)?"""
    for _op, words in _tokenize(command):
        words = strip_prefixes(list(words))
        if not words:
            continue
        names = [os.path.splitext(os.path.basename(w))[0] for w in words]
        if names[0] == "pr_land" or (INTERPRETERS.match(os.path.basename(words[0])) and "pr_land" in names[1:4]):
            return True
    return False


def runs_script(command: str, name: str) -> Optional[str]:
    """The path word of ``name`` (``lane_land``, ``go_public``) when a simple command of ``command`` executes it (directly or through an
    interpreter), else ``None``."""
    for _op, words in _tokenize(command):
        words = strip_prefixes(list(words))
        if not words:
            continue
        for index, word in enumerate(words[:4]):
            if os.path.splitext(os.path.basename(word))[0] == name and (index == 0 or INTERPRETERS.match(os.path.basename(words[0]))):
                return word
    return None


def base_refs() -> List[str]:
    """The branches a ``pr_land`` copy may match: ``product_base`` and ``workflow_base`` from the triage config."""
    try:
        cfg = json.loads((REPO / "tools" / "triage" / "config.json").read_text())
    except (OSError, ValueError):
        cfg = {}
    return list(dict.fromkeys([str(cfg.get("product_base") or "main"), str(cfg.get("workflow_base") or "main")]))


def git_out(top: str, *args: str) -> str:
    proc = subprocess.run(["git", "-C", top, *args], capture_output=True, text=True, timeout=20)
    if proc.returncode != 0:
        raise OSError(proc.stderr.strip()[:200] or f"git {' '.join(args[:2])} failed")
    return proc.stdout.strip()


#: Files each landing tool is hashed with (beside its own folder): the tool, what it loads, and ``tools/triage/config.json`` (it names the
#: product repo, the protected paths and the bases the tools clone and trust).
PINNED_WITH = {
    "pr_land.sh": ("pr_land.sh", "pr_land.py", "house_scan.py"),
    "lane_land.py": ("lane_land.py", "release_closure.py", "agent_eval_measure.py", "request_repo.py"),
    "go_public.sh": ("go_public.sh", "go_public_gate.py", "house_scan.py"),
}


def pr_land_matches_base(command: str, script_word: Optional[str] = None) -> bool:
    """Is the landing script this command runs (``tools/pr_land.sh``, ``tools/lane_land.py`` or ``tools/go_public.sh``: see
    :data:`PINNED_WITH` for what it is hashed with) byte-identical to ``origin/<base>``'s? An edited copy, a missing remote branch or
    any git error is a no. ``script_word`` is the script path when it is not the command's first word."""
    try:
        script = Path(script_word or command.split()[0])
        script = script if script.is_absolute() else Path(_CWD or os.getcwd()) / script
        folder = script.resolve().parent
        top = git_out(str(folder), "rev-parse", "--show-toplevel")
        rel = folder.relative_to(Path(top).resolve()).as_posix()
        names = [f"{rel}/{n}" for n in PINNED_WITH.get(script.name, PINNED_WITH["pr_land.sh"])] + ["tools/triage/config.json"]
        local = [git_out(top, "hash-object", "--", n) for n in names]
        for base in base_refs():
            try:
                if [git_out(top, "rev-parse", "--verify", "-q", f"refs/remotes/origin/{base}:{n}") for n in names] == local:
                    return True
            except OSError:
                continue
    except (OSError, ValueError, IndexError, subprocess.SubprocessError):
        return False
    return False


def headless_land_reason(command: str) -> Optional[str]:
    """Agent sessions (headless, or a payload with ``agent_type``/``agent_id``): ``pr_land`` runs only in its exact sanctioned form
    and only when this checkout's ``pr_land.sh`` and ``pr_land.py`` equal the base branch's; nothing may take the session markers
    away, and no pty wrapper may run the landing tools. ``--owner-ack`` (and any abbreviation of an ``--owner*`` option given to
    ``pr_land`` or ``lane_land``) is the owner's, never an agent's."""
    if re.search(r"owner[-_]ack", command) or (OWNER_OPTION.search(command) and re.search(r"pr_land|lane_land", command)):
        return "owner-ack: --owner-ack is the owner's, never an agent session's"
    if any(pattern.search(command) for pattern in ENV_TAMPER):
        return "landing: the session markers FENTON_HEADLESS and HASS_TRIAGE_* are not for a command to unset or change"
    if PTY_WRAPPER.search(command) and LAND_WORDS.search(command):
        return "landing: script/expect/unbuffer around pr_land, lane_land or ack-base (a pty would fake a terminal)"
    lane = runs_script(command, "lane_land")
    if lane and not re.search(r"ack[-_]?base", command) and not pr_land_matches_base(command, lane):  # ack-base has its own refusal
        return ("landing: this checkout's tools/lane_land.py, release_closure.py or triage/config.json differs from origin/" + "|".join(base_refs())
                + " (or git could not say): run the lander from a checkout whose copy is the base branch's")
    public = runs_script(command, "go_public")
    if public:
        if not GO_PUBLIC_FORM.match(command.strip()):
            return "going public: runs only as exactly `tools/go_public.sh SNAPSHOT_DIR OWNER/REPO` (no wrapper, prefix, chain or substitution)"
        if not pr_land_matches_base(command, public):
            return ("going public: this checkout's tools/go_public.sh, go_public_gate.py, house_scan.py or triage/config.json differs from origin/"
                    + "|".join(base_refs()) + " (or git could not say)")
    if runs_pr_land(command):
        if not is_sanctioned(command):
            return "landing: pr_land runs only as exactly `tools/pr_land.sh N [--dry-run]` (no wrapper, prefix, chain or substitution)"
        if not pr_land_matches_base(command):
            return ("landing: this checkout's tools/pr_land.sh, pr_land.py, house_scan.py or triage/config.json differs from origin/" + "|".join(base_refs())
                    + " (or git could not say): land from a checkout whose pr_land is the base branch's")
    return None


# MARK: - Going public (the gate is tools/go_public.sh)

GO_PUBLIC_FORM = re.compile(r"^(?:\./)?(?:\S*/)?tools/go_public\.sh\s+[\w./~+-]+\s+[\w.-]+/[\w.-]+$")
GO_PUBLIC_MESSAGE = (
    "Blocked: a repository goes public only through `tools/go_public.sh SNAPSHOT_DIR OWNER/REPO`, which runs tools/go_public_gate.py first "
    "(trusted base config, every file type, one orphan commit, gitleaks, a denylist of 20+ terms) and only then creates, pushes and publishes. "
    "`gh repo create --public`, `gh repo edit --visibility`, a visibility change through `gh api` and a `git push` to a remote other than this "
    "repository's origin are refused. See .agents/workflow/pr-lifecycle.md (Going public)."
)
VISIBILITY_WORDS = re.compile(r"private\W{0,4}false|visibility|updateRepository|setRepositoryVisibility|changeVisibility", re.I)
REPO_SLUG = re.compile(r"[:/]([\w.-]+)/([\w.-]+?)(?:\.git)?/?$")
PUSH_REMOTE_OPTS = {"-o", "--push-option", "--receive-pack", "--exec", "--signed", "--force-with-lease", "--recurse-submodules"}


def product_slug() -> str:
    """``owner/repo`` of the product repository (the triage config's ``product_repo``), lower-cased."""
    try:
        value = json.loads((REPO / "tools" / "triage" / "config.json").read_text()).get("product_repo")
    except (OSError, ValueError):
        value = None
    return str(value or "SFenton/Fenton-HASS-Native").lower()


def go_public_whole(command: str) -> Optional[str]:
    """Visibility changes seen on the whole command text (before splitting, so quotes and braces cannot hide them)."""
    if re.search(r"\bgh\b[^\n;&|]*\brepo\b[^\n;&|]*\bcreate\b[^\n;&|]*--(?:public|internal)\b", command):
        return "going public: gh repo create --public"
    if re.search(r"\bgh\b[^\n;&|]*\brepo\b[^\n;&|]*\bedit\b[^\n;&|]*--visibility(?:[= ]+(?!private\b))", command):
        return "going public: gh repo edit --visibility"
    if re.search(r"\bgh\b[^\n;&|]*\brepo\b[^\n;&|]*\bedit\b[^\n;&|]*--visibility\s*$", command):
        return "going public: gh repo edit --visibility"
    if re.search(r"\bgh\b[^\n;&|]*\bgist\b[^\n;&|]*\bcreate\b[^\n;&|]*(?:--public|\s-p\b)", command):
        return "going public: gh gist create --public"
    if re.search(r"\bgh\b[^\n;&|]*\bgist\b[^\n;&|]*\bedit\b[^\n;&|]*(?:--public|--visibility|\s-p\b)", command):
        return "going public: gh gist edit making a gist public"
    if re.search(r"\bgit\b[^\n;&|]*\bremote\b\s+(?:-\S+\s+)*(?:add|set-url|rename|set-head|remove|rm)\b", command):
        return "going public: git remote add, set-url or rename (the only push target is origin)"
    if re.search(r"\bgit\b[^\n;&|]*(?:\s-c\s*|--config-env[= ]\s*)['\"]?(?:remote\.|url\.)", command, re.I):
        return "going public: git -c remote.* or url.* (the only push target is origin)"
    for cfg in re.finditer(r"\bgit\b[^\n;&|]*\bconfig\b[^\n;&|]*", command):
        text = cfg.group(0)
        if re.search(r"(?:^|\s)['\"]?(?:remote\.[^\s'\"]*\.(?:push)?url|url\.[^\s'\"]*)['\"]?\s+['\"]?[^\s'\"-]", text, re.I) and not re.search(
                r"\s(?:--get\S*|--list|-l|--show-\S+|--unset\S*)(?:\s|$)", text):
            return "going public: git config remote.<name>.url or url.* (the only push target is origin)"
    if re.search(r"\bGIT_CONFIG_(?:KEY_\d+|VALUE_\d+|PARAMETERS|COUNT|GLOBAL|SYSTEM)\b", command):
        return "going public: GIT_CONFIG_* environment overrides (the only push target is origin)"
    if API_WHOLE.search(command) and VISIBILITY_WORDS.search(command):
        graphql = re.search(r"graphql", command, re.I)
        if (graphql and re.search(r"mutation", command, re.I)) or (not graphql and GH_WRITE.search(command)):
            return "going public: a visibility change through gh api"
    return None


def push_remote_reason(operands: List[str], workdir: Optional[str]) -> Optional[str]:
    """Why a ``git push`` (words after ``push``) targets anything but this repository's origin, or ``None``. Only the name
    ``origin`` (or no remote at all) is accepted, and only when origin's configured push URL is this repository: a URL, a path, any
    other name, or a remote that does not resolve is refused here, not left to git to fail."""
    remote: Optional[str] = None
    skip = False
    for index, word in enumerate(operands):
        if skip:
            skip = False
        elif word == "--repo" and index + 1 < len(operands):
            remote = operands[index + 1]
            break
        elif word.startswith("--repo="):
            remote = word[len("--repo="):]
            break
        elif word in PUSH_REMOTE_OPTS:
            skip = word in ("-o", "--push-option", "--receive-pack", "--exec")
        elif not word.startswith("-"):
            remote = word
            break
    remote = remote or "origin"
    if remote != "origin":
        return "going public: git push to a remote other than origin"
    try:
        url = git_out(workdir or _CWD or os.getcwd(), "remote", "get-url", "--push", "origin")
    except (OSError, subprocess.SubprocessError):
        return "going public: git push when origin cannot be resolved to this repository"
    match = REPO_SLUG.search(url.strip())
    if match and f"{match.group(1)}/{match.group(2)}".lower() == product_slug():
        return None
    return "going public: git push to a remote other than this repository's origin"


# MARK: - Request-repo writes (headless)

_REQUEST_REPO: Dict[str, str] = {}


def request_repo() -> str:
    """The request repository, lower-cased: ``tools/request_repo.py`` (environment variable, local file, then ``request_repo`` of
    ``tools/triage/config.json``, which is empty). The empty string means **not configured**: :func:`request_repo_unset`."""
    if "value" not in _REQUEST_REPO:
        try:
            value = json.loads((REPO / "tools" / "triage" / "config.json").read_text()).get("request_repo")
        except (OSError, ValueError):
            value = None
        _REQUEST_REPO["value"] = (request_repo_module.resolve(value) or "").lower()
    return _REQUEST_REPO["value"]


def request_repo_unset() -> bool:
    """Is no request repository configured? Then a headless session cannot tell which repository is the guarded one, so every guarded
    ``gh`` write (issue, label and repo writes, non-GET ``gh api`` calls) is refused against any repository."""
    return not request_repo()


def names_request_repo(text: str) -> bool:
    """Does ``text`` (a ``--repo`` value, a URL, a ``GH_REPO`` value) name the request repository?"""
    return request_repo_unset() or request_repo() in text.lower().removesuffix(".git").replace("\\", "/")


def option_values(args: List[str], long: str, short: str) -> List[str]:
    """Every value given for an option: ``--long V``, ``--long=V``, ``-s V``, ``-sV`` (and ``-s=V``)."""
    found: List[str] = []
    for i, word in enumerate(args):
        if word == long or word == f"-{short}":
            if i + 1 < len(args):
                found.append(args[i + 1])
        elif word.startswith(long + "="):
            found.append(word[len(long) + 1:])
        elif word.startswith(f"-{short}") and not word.startswith("--") and len(word) > 2:
            found.append(word[2:].lstrip("="))
    return found


PROSE_OPTS = {"--body", "-b", "--title", "-t", "--body-file", "-F"}


def without_prose(args: List[str]) -> List[str]:
    """``args`` without the values of title and body options: prose can mention a repository or a label."""
    kept: List[str] = []
    skip_next = False
    for word in args:
        if skip_next:
            skip_next = False
        elif word in PROSE_OPTS:
            skip_next = True
        elif not word.startswith(("--body=", "--title=", "--body-file=")):
            kept.append(word)
    return kept


def has_workflow_label(args: List[str]) -> bool:
    """Is ``Workflow`` among the ``--label``/``-l`` values (each may be a comma list; labels match case-insensitively)?"""
    values = option_values([w for w in without_prose(args) if not (w.startswith("-l") and w[2:3].isspace())], "--label", "l")
    return any(part.strip().lower() == "workflow" for value in values for part in value.split(","))


def api_method(args: List[str]) -> str:
    """The HTTP method of a ``gh api`` call: explicit, else POST when it sends fields or an input file, else GET."""
    for value in option_values(args, "--method", "X"):
        return value.upper()
    sends = any(w in ("-f", "-F", "--field", "--raw-field", "--input") or w.startswith(("--field=", "--raw-field=", "--input=", "-f", "-F"))
                for w in args if w.startswith("-"))
    return "POST" if sends else "GET"


UNRESOLVABLE = re.compile(r"[$`()*?\[{~]")
READ_ONLY_ISSUE = {"view", "list", "status"}
READ_ONLY_REPO = {"view", "list", "clone"}
READ_ONLY_LABEL = {"list", "view"}  # `gh label` has no view today; harmless if it grows one


def names_unresolved(text: str) -> bool:
    """Is this word a repository we cannot read from the command text (a variable, a substitution, a glob)?"""
    return bool(UNRESOLVABLE.search(text))


def request_target(args: List[str], env_values: List[str]) -> bool:
    """Does this ``gh`` command target the request repository? Yes when any ``-R``/``--repo`` value, ``GH_REPO`` value or other
    non-prose word names it, and **also when the target cannot be resolved** from the text (``-R $VAR``, ``-R $(...)``, a glob,
    a ``GH_REPO`` set in the command that is not a plain repository). A URL for it plus a conflicting ``-R`` counts. No repository
    given at all means the checkout's own (product) repository."""
    if request_repo_unset():
        return True
    repos = option_values(args, "--repo", "R")
    if args and args[-1] in ("-R", "--repo"):  # `-R $(...)`: the substitution ends the simple command, the value is missing
        return True
    scan = [w for w in without_prose(args) if not w.startswith("-")]
    if any(names_request_repo(c) for c in repos + env_values + scan):
        return True
    return any(names_unresolved(c) for c in repos + env_values) or any(names_unresolved(w) for w in scan)


def gh_request_reason(words: List[str], env_values: List[str]) -> Optional[str]:
    """The request-repo **allow-list** for one ``gh`` command (``words`` start at ``gh``). Against the request repository a headless
    session may only ``gh issue create`` with the ``Workflow`` label and read (``issue view|list|status``, ``label list|view``, ``repo view``, a
    ``gh api`` GET). Everything else is blocked: ``issue`` edit/close/reopen/delete/transfer/comment/lock/pin/develop, ``label``
    writes (``label list|view`` are reads), ``repo set-default`` (anywhere) and other ``repo`` writes, a non-GET ``gh api`` call to ``repos/<request repo>/**``
    or to an endpoint we cannot read, and any GraphQL mutation."""
    args = list(words[1:])
    positional = [w for w in without_prose(args) if not w.startswith("-")]
    group, sub = (positional + ["", ""])[:2]
    if group == "alias" and sub in ("set", "import"):
        return "request-repo: gh alias in a headless session"
    if group == "repo" and sub == "set-default":
        return "request-repo: gh repo set-default in a headless session (it silently retargets every later gh command)"
    if group == "api":
        joined = " ".join(args)
        if "graphql" in joined.lower() and (re.search(r"mutation", joined, re.I) or "@" in joined or "--input" in args):
            return "request-repo: gh api graphql mutation or unreadable query in a headless session"
        method = api_method(args)
        endpoints = [w for w in positional[1:] if "/" in w]
        names_it = request_repo_unset() or request_repo() in joined.lower() or any(names_unresolved(w) for w in endpoints) or any(
            names_request_repo(v) or names_unresolved(v) for v in env_values)
        if method != "GET" and names_it:
            if method == "POST" and re.search(r"repos/" + re.escape(request_repo()) + r"/issues(?=$|[\s?#\"'])", joined, re.I) \
                    and re.search(r"labels\[\]=workflow\b", joined, re.I):
                return None
            return f"request-repo: gh api {method} to the request repository (or to an endpoint that cannot be read)"
        return None
    if group not in ("issue", "label", "repo") or not request_target(args, env_values):
        return None
    if group == "issue" and sub == "create":
        return None if has_workflow_label(args) else "request-repo: gh issue create in the request repository without --label Workflow"
    if (group == "issue" and sub in READ_ONLY_ISSUE) or (group == "repo" and sub in READ_ONLY_REPO) \
            or (group == "label" and sub in READ_ONLY_LABEL):
        return None
    return f"request-repo: gh {group} {sub} against the request repository (only issue create with Workflow, and reads, are allowed)"


def request_repo_reason(command: str, depth: int = 0) -> Optional[str]:
    """Headless request-repo rules over the whole command (quote-aware; ``bash -c``/``eval`` strings recursed, ``gh`` found behind
    ``find -exec``, ``xargs`` and other wrappers)."""
    if depth > 3:
        return "request-repo: nested shell too deep to check"
    segments = _tokenize(command)
    # An unquoted `$(` or backtick (a quoted one becomes a `$_SUB` placeholder, e.g. `--body "$(cat f)"`, and is prose).
    code = scan_shell(command)[0]
    direct_sub = "$(" in code or "`" in code
    # Every GH_REPO assignment anywhere in the command (a prefix, `export GH_REPO=...`, an earlier `;` statement) retargets
    # every gh in it: its value is a candidate for each.
    env_values = [w.split("=", 1)[1] or "$(" for _op, words in segments for w in words if w.startswith("GH_REPO=")]
    for at, (_op, words) in enumerate(segments):
        stripped = strip_prefixes(list(words))
        if not stripped:
            continue
        if os.path.basename(stripped[0]) in FEEDERS:
            stripped = unwrap_xargs(stripped[1:]) or stripped
        program = os.path.basename(stripped[0])
        names = [os.path.basename(w) for w in stripped]
        if program in ("echo", "printf"):
            continue
        if program in SHELLS or program == "eval":
            strings = ([stripped[i + 1] for i, w in enumerate(stripped[:-1]) if SHELL_C.match(w)] if program in SHELLS
                       else [" ".join(stripped[1:])])
            for text in strings:
                why = request_repo_reason(text, depth + 1)
                if why:
                    return why
        if "gh" in names:  # gh itself, or behind find -exec, parallel, time, ...
            # a `$(...)` or backtick right after the command ends it early: the rest (maybe the repository) is unreadable
            tail = ["$("] if direct_sub and at + 1 < len(segments) and segments[at + 1][0] == "(" else []
            why = gh_request_reason(stripped[names.index("gh"):], env_values + tail)
            if why:
                return why
    return None


def push_reason(operands: List[str]) -> Optional[str]:
    """Why ``git push`` with these words (after ``push``) is not a plain push of ``agents/*`` lane branches, or ``None``."""
    refs: List[str] = []
    for word in operands:
        if EXPANSION.search(word):
            return "git push with a shell expansion"
        if word.startswith("-"):
            if word not in SAFE_PUSH_FLAGS:
                return f"git push option {word} outside the lane allow-list"
        else:
            refs.append(word)
    if len(refs) < 2 or refs[0] != "origin":
        return "git push must name `origin` and explicit agents/* refspecs"
    for ref in refs[1:]:
        if ref.startswith("+"):
            return "git push of a forced refspec"
        src, colon, dest = ref.partition(":")
        if colon and not src:
            return "git push that deletes a ref"
        target = dest if colon else ref
        if ".." in target or target.endswith(("/", ".lock")) or not AGENT_DEST.match(target):
            return f"git push of {ref} (only refs/heads/agents/* may be pushed)"
    return None


def headless_git_reason(args: List[str], configs: List[str], rest: List[str]) -> Optional[str]:
    """The headless allow-list for one git command (``args`` after the global options, ``configs`` the ``-c`` values)."""
    if any(c.lower().startswith("alias.") for c in configs) or any(w.startswith("--config-env") for w in rest):
        return "git alias or config-env in a headless session"
    if not args:
        return None
    if args[0] == "config" and any("alias." in a.lower() for a in args[1:]):
        return "git config alias in a headless session"
    if args[0] in ("send-pack", "http-push"):
        return f"git {args[0]} in a headless session"
    if args[0] == "push":
        return push_reason(args[1:])
    return None


def is_sanctioned(command: str) -> bool:
    """Is ``command`` exactly ``tools/pr_land.sh ARGS`` with nothing else in it?"""
    text = command.strip()
    if METACHARS.search(text):
        return False
    words = text.split()
    if not words:
        return False
    script = words[0]
    roots = {REPO}
    if os.environ.get("CLAUDE_PROJECT_DIR"):
        roots.add(Path(os.environ["CLAUDE_PROJECT_DIR"]).resolve())
    allowed = {"tools/pr_land.sh", "./tools/pr_land.sh"} | {str(r / "tools/pr_land.sh") for r in roots}
    return script in allowed


def strip_wrappers(words: List[str]) -> List[str]:
    """Drop leading ``VAR=value`` words and wrapper programs with their options."""
    while words:
        head = os.path.basename(words[0])
        if re.match(r"^\w+=", words[0]):
            words = words[1:]
        elif head in WRAPPERS:
            takes_value = WRAPPERS[head]
            words = words[1:]
            while words and (words[0].startswith("-") or re.match(r"^\w+=", words[0])):
                option = words[0]
                words = words[1:]
                if option in takes_value and words:
                    words = words[1:]
        else:
            break
    return words


# MARK: - The one allowed merge (native-home auto-merge, owner 2026-11-08)

AUTOMERGE_REPO = "sfenton/native-home"
AUTOMERGE_AUTHOR = "SFenton"
SHA40 = re.compile(r"^[0-9a-fA-F]{40}$")
AUTOMERGE_FLAGS = {"--squash", "-s", "--auto"}
AUTOMERGE_VALUE_FLAGS = {"-R", "--repo", "--match-head-commit", "--subject", "-t", "--body", "-b", "--body-file", "-F"}
AUTOMERGE_UNSAFE = re.compile(r"[$`;&|<>(){}\n\r\\]")
PR_NUMBER = re.compile(r"[0-9]+")
#: True while a nested command string (``eval``, ``bash -c``) is scanned: the allowed merge is a top-level command only.
_NESTED = False
#: The command text the allowed-merge check accepted; its one segment is then not flagged as ``gh pr merge``.
_AUTOMERGE_OK: Optional[str] = None
GH_TIMEOUT = 20


def gh_json(path: str) -> object:
    """``gh api PATH`` (all pages, flattened) parsed as JSON; raises on any error, timeout or bad output (the caller fails closed)."""
    out = subprocess.run(["gh", "api", "--paginate", "--slurp", path], capture_output=True, text=True, timeout=GH_TIMEOUT, check=True).stdout
    data = json.loads(out)
    if isinstance(data, list) and data and all(isinstance(page, list) for page in data):
        return [item for page in data for item in page]
    if isinstance(data, list) and len(data) == 1:
        return data[0]
    return data


def automerge_form(command: str) -> Optional[Dict[str, str]]:
    """Parse ``command`` when it is exactly the one allowed ``gh pr merge`` form (shape only), else ``None``.

    Shape: ``gh pr merge N -R SFenton/native-home --squash --auto --match-head-commit SHA [--subject S] [--body B | --body-file F]``.
    No shell metacharacter outside quotes, no prefix (env, wrapper, alias), no other flag (``--admin``, ``--delete-branch``, ``--merge``).
    """
    text = command.strip()
    if "\n" in text or "\r" in text:
        return None
    try:
        words = shlex.split(text)
    except ValueError:
        return None
    if words[:3] != ["gh", "pr", "merge"]:
        return None
    # No substitution, backslash, separator, redirect or newline anywhere, quoted or not (use --body-file for rich text).
    if AUTOMERGE_UNSAFE.search(text):
        return None
    found: Dict[str, str] = {}
    flags = set()
    rest = words[3:]
    i = 0
    while i < len(rest):
        word = rest[i]
        key, eq, inline = word.partition("=") if word.startswith("--") else (word, "", "")
        if key in AUTOMERGE_VALUE_FLAGS:
            if eq:
                value = inline
            elif i + 1 < len(rest):
                i += 1
                value = rest[i]
            else:
                return None
            key = {"--repo": "-R", "-t": "--subject", "-b": "--body", "-F": "--body-file"}.get(key, key)
            if key in found:
                return None
            found[key] = value
        elif word in AUTOMERGE_FLAGS or word == "--disable-auto":
            flags.add("--squash" if word in ("-s", "--squash") else word)
        elif PR_NUMBER.fullmatch(word) and "pr" not in found:
            found["pr"] = word
        else:
            return None
        i += 1
    if flags == {"--disable-auto"} and set(found) == {"pr", "-R"}:
        found["disable"] = "1"
        return found
    if flags != {"--squash", "--auto"} or "pr" not in found or "--match-head-commit" not in found or "-R" not in found:
        return None
    if "--body" in found and "--body-file" in found:
        return None
    return found


def automerge_repo(value: str) -> str:
    """``value`` of ``-R`` reduced to ``owner/name``, lower-case (the https URL form is accepted)."""
    return value.strip().lower().removeprefix("https://github.com/").rstrip("/").removesuffix(".git")


def verdict_events(sha: str, comments: List[dict], reviews: List[dict]) -> List[tuple]:
    """``(time, verdict)`` for every comment or review body with a ``Head: sha`` line and a ``Verdict:`` line, oldest first."""
    events = []
    head = re.compile(r"^\s*head:\s*" + re.escape(sha) + r"\s*$", re.I | re.M)
    verdict = re.compile(r"^\s*verdict:\s*(pass|fail)\s*$", re.I | re.M)
    for item, stamp in [(c, "created_at") for c in comments] + [(r, "submitted_at") for r in reviews]:
        if not isinstance(item, dict) or (item.get("user") or {}).get("login") != AUTOMERGE_AUTHOR:
            continue  # only the owner's account can speak for the review
        if item.get("author_association", "OWNER") != "OWNER" or str(item.get("state", "")).upper() in ("PENDING", "DISMISSED"):
            continue
        when = item.get(stamp)
        body = str(item.get("body") or "")
        match = verdict.search(body)
        if when and match and head.search(body):
            events.append((str(when), match.group(1).lower()))
    # A fail sorts after a pass at the same instant, so a tie refuses.
    return sorted(events, key=lambda e: (e[0], e[1] == "fail"))


def automerge_reason(command: str) -> Optional[str]:
    """``None`` when ``command`` is the allowed auto-merge and every fact holds at hook time, else why it is refused (fails closed)."""
    found = automerge_form(command)
    if found is None:
        return "gh pr merge"
    if automerge_repo(found["-R"]) != AUTOMERGE_REPO:
        return "gh pr merge outside SFenton/native-home"
    if "disable" in found:
        return None  # disarming auto-merge is always safe
    sha = found["--match-head-commit"]
    if not SHA40.match(sha):
        return "gh pr merge without a 40-hex --match-head-commit"
    sha = sha.lower()
    number = found["pr"]
    try:
        pr = gh_json(f"repos/SFenton/native-home/pulls/{number}")
        comments = gh_json(f"repos/SFenton/native-home/issues/{number}/comments")
        reviews = gh_json(f"repos/SFenton/native-home/pulls/{number}/reviews")
        author = pr["user"]["login"]
        base = pr["base"]["ref"]
        head = str(pr["head"]["sha"]).lower()
        if not isinstance(comments, list) or not isinstance(reviews, list):
            raise ValueError("unexpected shape")
    except Exception:  # noqa: BLE001 - any failure refuses
        return "gh pr merge (the PR facts could not be fetched)"
    if author != AUTOMERGE_AUTHOR:
        return "gh pr merge of a PR not authored by SFenton"
    if base != "main":
        return "gh pr merge of a PR not based on main"
    if head != sha:
        return "gh pr merge with a stale --match-head-commit"
    events = verdict_events(sha, comments, reviews)
    if not events or events[-1][1] != "pass":
        return "gh pr merge without a passing independent review of this head"
    return None


def nested_reason(command: str) -> Optional[str]:
    """``raw_reason`` of a command string inside ``eval`` or ``bash -c``, where the allowed merge never applies."""
    global _NESTED
    before = _NESTED
    _NESTED = True
    try:
        return raw_reason(command)
    finally:
        _NESTED = before


def segment_reason(segment: str) -> Optional[str]:
    """Why one simple command is a merge bypass, or ``None``."""
    try:
        words = shlex.split(segment)
    except ValueError:
        if headless() and GIT_WORD.search(segment) and PUSH_WORD.search(segment):
            return "unparseable git push in a headless session"
        words = segment.split()
    raw_words = words
    words = strip_wrappers(words)
    if not words:
        return None
    if headless():
        names = [os.path.basename(w) for w in raw_words]
        if "xargs" in names and "git" in names and "push" in raw_words:
            return "xargs git push in a headless session"
        if os.path.basename(words[0]).startswith(("python", "bash", "sh", "zsh", "lane_land")) and any(
                w.endswith("lane_land.py") for w in words):
            return "lane_land in a headless session (the runner lands)"
        if os.path.basename(words[0]) != "git" and "git" in [os.path.basename(w) for w in words]:
            at = [os.path.basename(w) for w in words].index("git")
            inner = segment_reason(" ".join(shlex.quote(w) for w in words[at:]))
            if inner:
                return inner
    program = os.path.basename(words[0])
    rest = words[1:]
    if program in SHELLS:
        for i, word in enumerate(rest[:-1]):
            if SHELL_C.match(word):
                return nested_reason(rest[i + 1])
    if program == "eval":
        return nested_reason(" ".join(rest))
    if program == "gh":
        args: List[str] = []
        skip = False
        for word in rest:
            if skip:
                skip = False
            elif word in GH_VALUE_OPTS:
                skip = True
            else:
                args.append(word)
        if args[:2] == ["pr", "merge"]:
            if _AUTOMERGE_OK is not None and segment.strip() == _AUTOMERGE_OK:
                return None
            return "gh pr merge"
        if args[:1] == ["api"]:
            joined = " ".join(rest)
            if MERGE_URL.search(joined):
                return "gh api merge call"
            if GRAPHQL_MERGE.search(joined):
                return "gh api graphql merge"
            if "/contents/" in joined and WRITE_METHOD.search(joined):
                return "gh api write to /contents/"
            if headless() and GH_REF_API.search(joined) and GH_WRITE.search(joined):
                return "gh api write to git refs, branches or contents in a headless session"
        return None
    if program == "git":
        args = []
        skip = False
        configs: List[str] = []
        previous = ""
        workdir: Optional[str] = None
        for word in rest:
            if skip:
                skip = False
                if previous == "-c":
                    configs.append(word)
                elif previous == "-C":
                    workdir = word if os.path.isabs(word) or not workdir else os.path.join(workdir, word)
                    if not os.path.isabs(workdir):
                        workdir = os.path.join(_CWD or os.getcwd(), workdir)
            elif word in GIT_VALUE_OPTS:
                skip = True
                previous = word
            else:
                args.append(word)
        while args and args[0].startswith("-"):
            args = args[1:]
        if headless():
            lane = headless_git_reason(args, configs, rest)
            if lane:
                return lane
        if args[:1] == ["push"]:
            for arg in args[1:]:
                if not arg.startswith("-") and MAIN_REF.search(arg):
                    return "git push to main"
            return push_remote_reason(args[1:], workdir)
    return None


# MARK: - The one exemption (a command that only reads, prints or runs a repo script)

#: Programs whose arguments are data. Anything else in the command, or any listed shape below, keeps the raw scan's verdict.
EXEMPT_PLAIN = {"grep", "rg", "cat", "head", "tail", "less", "ls", "wc", "echo", "mkdir"}
EXEMPT_GIT = {"log", "show", "diff", "status", "commit"}
EXEMPT_GIT_BAD_ARGS = {"-c", "--config-env", "--ext-diff", "--output", "--textconv"}
#: ``cat > file <<WORD`` or ``cat <<WORD > file``: the body is data written to a file (#370). A bare ``cat <<WORD`` is not covered.
CAT_HEREDOC = re.compile(r"^\s*cat(?:\s+>>?\s*([\w./~+-]+)\s*<<\s*(['\"]?)(\w+)\2|\s*<<\s*(['\"]?)(\w+)\4\s*>>?\s*([\w./~+-]+))\s*$")
#: ``git commit ... -F - <<WORD`` and ``gh pr create|comment ... --body-file - <<WORD``: the body is a message, not code (#370).
BODY_HEREDOC = re.compile(r"^\s*(?:git\s+commit|gh\s+(?:pr|issue)\s+(?:create|comment|edit))\b[^<>|;&$`]*\s(?:-F|--file|--body-file)(?:\s+|=)-\s*<<\s*(['\"]?)(\w+)\1\s*$")
EXEMPT_OPS = {"", ";", "&&", "||", "|"}


def lexes(text: str) -> bool:
    """Does the quote-aware lexer read ``text`` to its end (balanced quotes)?"""
    try:
        lexer = shlex.shlex(text.replace("\n", " ; "), posix=True, punctuation_chars=True)
        lexer.whitespace_split = True
        lexer.commenters = ""
        list(lexer)
    except ValueError:
        return False
    return True


def drop_cat_heredocs(command: str) -> Optional[str]:
    """``command`` without the bodies of its ``cat > file <<WORD`` heredocs, or ``None`` when any other heredoc or here-string is in it,
    a body is never closed, a quote or a backslash carries over a line end (so a marker could be inside a quote), or the file name
    is not a plain path."""
    lines = command.split("\n")
    kept: List[str] = []
    i = 0
    while i < len(lines):
        line = lines[i]
        i += 1
        if "<<" in line:
            marker = CAT_HEREDOC.match(line)
            body = BODY_HEREDOC.match(line) if not marker else None
            targets = [t for t in (marker.group(1), marker.group(6)) if t] if marker else []
            if not (marker or body) or any(".git" in t or ".." in t for t in targets):  # not a hook or config the next command could run
                return None
            word = (marker.group(3) or marker.group(5)) if marker else body.group(2)
            while i < len(lines) and lines[i] != word:
                i += 1
            if i >= len(lines):
                return None
            i += 1
            line = line[:line.index("<<")]
        if line.rstrip().endswith("\\") or not lexes(line):
            return None
        kept.append(line)
    return "\n".join(kept)


#: Repository scripts that never run their arguments (read: no subprocess or exec path takes a program from argv; those that call
#: ``git`` or ``gh`` fix the program and subcommand). ``agent_status.py`` and ``lane_base.py`` now exist but stay unexempt
#: until read (they write files and take paths from their arguments). Never ``bg_run.py``, ``devcap.py``, ``ship.sh``, ``pr_land``, ``lane_land`` (they run ``-- CMD``)
#: or anything under ``tools/triage``.
EXEMPT_SCRIPTS = {"tasks.py", "pr_note.py", "affected_tests.py", "jev_gate.py", "retro_digest.py"}


def repo_checkouts() -> List[Path]:
    """This checkout and the primary one (a lane worktree sits at ``<primary>/.claude/worktrees/<name>``)."""
    roots = [REPO.resolve()]
    parts = REPO.resolve().parts
    if ".claude" in parts:
        roots.append(Path(*parts[:parts.index(".claude")]))
    return roots


def repo_script(path: str, cwd: Optional[str]) -> bool:
    """Is ``path`` one of ``EXEMPT_SCRIPTS``, directly under ``tools/`` of this repository's checkouts (resolved real path, existing file)?"""
    if path.startswith("-") or re.search(r"[$`~*?\[{]", path):
        return False
    resolved = (Path(cwd or os.getcwd()) / path).resolve()
    return (resolved.is_file() and resolved.name in EXEMPT_SCRIPTS and resolved.parent.name == "tools"
            and any(resolved.parent.parent == root for root in repo_checkouts()))


def exempt_words(words: List[str], cwd: Optional[str]) -> bool:
    """Is this one simple command a non-executing program (see ``EXEMPT_PLAIN``) with arguments that cannot run anything?"""
    if not words or re.match(r"^\w+=", words[0]) or any("/dev/stdin" in w for w in words):
        return False
    program, args = words[0], words[1:]
    if program in EXEMPT_PLAIN:
        return not (program == "rg" and any(a.startswith("--pre") for a in args))
    if program == "git":
        return bool(args) and args[0] in EXEMPT_GIT and not any(a in EXEMPT_GIT_BAD_ARGS or a.startswith("--config-env") for a in args)
    if program == "gh":
        if args[:2] in (["pr", "create"], ["pr", "comment"]):  # a message body; never another repository
            return not any(a in ("-R", "--repo") or a.startswith("--repo=") for a in args)
        return args[:2] in (["pr", "view"], ["pr", "list"])
    if program == "python3":
        return bool(args) and repo_script(args[0], cwd)
    return False


def exempt(command: str, cwd: Optional[str] = None) -> bool:
    """Is every simple command of ``command`` a non-executing one, so the raw scan's block is a false positive? Narrow on purpose:
    ANSI-C quotes, substitutions, subshells, heredocs other than ``cat > file <<WORD``, ``/dev/stdin``, shells, interpreters,
    ``find``, ``sed``, ``awk``, ``xargs``, ``env`` and every other wrapper keep the raw verdict, as does any parse failure."""
    if "$'" in command or '$"' in command or "${" in command or re.search(r"[`]|\$\(|[<>]\(|\b(?:printf|print)\s+-v", command):
        return False
    text = drop_cat_heredocs(command)
    if text is None or "<<" in text:
        return False
    segments = _tokenize(text)
    return bool(segments) and all(op in EXEMPT_OPS and exempt_words(words, cwd) for op, words in segments)


def raw_reason(command: str, cwd: Optional[str] = None, agent: bool = False) -> Optional[str]:
    """Why ``command`` bypasses the gate, or ``None``. ``cwd`` is the session's directory (for a bare ``git merge``)."""
    global _CWD
    _CWD = cwd
    global _AGENT
    _AGENT = agent
    if agent_session():  # before the sanctioned form: `tools/pr_land.sh N --owner` must not slip through it
        why = headless_land_reason(command)
        if why:
            return why
    if is_sanctioned(command):
        return None
    global _AUTOMERGE_OK
    _AUTOMERGE_OK = None
    if not _NESTED and not headless() and automerge_form(command) is not None:
        why = automerge_reason(command)
        if why:
            return why
        _AUTOMERGE_OK = command.strip()  # the full scan below must agree: the one segment is then not a bypass
    # Checked on the whole string, before splitting: braces in a GraphQL query or in gh's `{owner}/{repo}` and
    # `${N}` placeholders would otherwise cut the `gh api` away from its URL.
    if API_WHOLE.search(command):
        if MERGE_URL.search(command):
            return "gh api merge call"
        if GRAPHQL_MERGE.search(command):
            return "gh api graphql merge"
        if "/contents/" in command and WRITE_METHOD.search(command):
            return "gh api write to /contents/"
    public = go_public_whole(command)
    if public:
        return public
    if PIPE_TO_SHELL.search(command) or HERE_TO_SHELL.search(command):
        return "script piped into a shell"
    if headless() and re.search(r"ack[-_]?base", command):
        return "ack-base in a headless session (headless: only the owner accepts a moved base)"
    if headless():
        why = request_repo_reason(command)
        if why:
            return why
    if headless() and EXPANSION.search(command) and GIT_WORD.search(command) and PUSH_WORD.search(command):
        return "git push through a shell expansion in a headless session"
    for segment in SPLIT.split(command):
        why = segment_reason(segment)
        if why:
            return why
    return None


def reason(command: str, cwd: Optional[str] = None, agent: bool = False) -> Optional[str]:
    """Why ``command`` bypasses the gate, or ``None``: the raw scan's verdict, dropped only when ``exempt`` says every simple command
    in it is a non-executing one (a ``grep`` for ``--owner-ack``, a ``cat > notes.md <<'EOF'`` whose text mentions ``lane_land``)."""
    why = raw_reason(command, cwd, agent)
    return None if why and exempt(command, cwd) else why


def main(argv: Optional[List[str]] = None) -> int:
    """Read the hook payload from stdin; exit 2 with ``MESSAGE`` to block."""
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        return 0
    if payload.get("tool_name") != "Bash":
        return 0
    why = reason(str((payload.get("tool_input") or {}).get("command", "")), payload.get("cwd"),
                 agent=bool(payload.get("agent_type") or payload.get("agent_id")))
    if why:
        message = (GO_PUBLIC_MESSAGE if why.startswith("going public") else REQUEST_MESSAGE if why.startswith("request-repo")
                   else LAND_MESSAGE if why.startswith(("landing:", "owner-ack:"))
                   else LANE_MESSAGE if "headless" in why or "git push" in why and headless() else MESSAGE)
        print(f"{message} (matched: {why})", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
