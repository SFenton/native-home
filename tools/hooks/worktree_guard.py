#!/usr/bin/env python3
"""Hook: one session, one worktree. Keep sessions out of a repository's shared primary checkout.

Owner decision (2026-10-30): every Claude session works in its own linked worktree (``EnterWorktree``, an Agent with
``isolation: "worktree"``, or the triage runner's ``~/hass-agents/worktrees/N``), never in the primary checkout that
other sessions share. A *primary* checkout is one whose ``git rev-parse --absolute-git-dir`` equals its
``--git-common-dir``; a linked worktree has a git dir inside the common one. Git decides, never a path or a device name.

Modes (the hook JSON is read from stdin; bad input or a git failure fails open: exit 0, no output):

- ``--session-start`` (SessionStart): when ``cwd`` is in a primary checkout, print ``additionalContext`` telling the
  session to call ``EnterWorktree`` before any edit, commit or branch change. Nothing otherwise.
- PreToolUse ``Edit|Write|MultiEdit|NotebookEdit``: deny a path inside a primary checkout unless git ignores it
  (``git check-ignore -q --no-index``: ``build/handoff``, ``.build`` and scratch output stay writable). Paths outside a
  repository, or in a linked worktree (including one nested under a primary, such as ``.claude/worktrees/x``), pass.
- PreToolUse ``Bash``: split the command into simple commands, follow ``cd``/``pushd``, ``git -C`` and ``env -C``, and
  deny, when the effective directory is in a primary checkout:
  ``git commit|add|rm|mv|restore|checkout|switch|reset|merge|rebase|pull|cherry-pick|revert|am|clean``, ``apply``
  (unless ``--check``/``--stat``), ``stash`` (unless ``list``/``show``); ``sed -i``, ``perl -i``, ``tee``, ``>``/``>>``
  redirects, ``touch``, the destination of ``cp``/``mv``/``ln``/``install``, the sources of ``mv`` and ``rm``/``rmdir``
  targets, when the target is in a primary checkout and not git-ignored; and ``tools/ship.sh`` run from there.
  ``/dev/*`` and file descriptors are fine. ``$PWD``, ``$(pwd)``, ``$HOME``, ``~`` and ``$CLAUDE_PROJECT_DIR`` expand
  first (``$PWD`` follows a ``cd``). ``bash -c`` and ``eval`` strings are scanned too.

Subagents in a session worktree: a payload with ``agent_id`` is a subagent (the main session never carries one). When
its worktree's HEAD branch is ``t3/*`` it is in the parent session's worktree, usually because its isolation worktree was
cleaned after it ended with no changes and a resume ran it in the parent's cwd. There ``git switch``, ``git checkout
<branch>``, ``git checkout -b`` (not ``git checkout -- f`` or ``git checkout <rev> -- f``), and ``tools/setup.sh`` are denied
with ``NO_WORKTREE_MESSAGE``. File edits are not: a subagent without a worktree may write git-ignored ``build/`` files.

Override: a real comment ``# worktree-ok: reason`` (not quoted, not in a heredoc body).

Not stopped: aliases and shell functions, a command or path held in a variable (``$cmd``, ``cd $DIR``), ``eval`` built
from variables, scripts and interpreters that write (``python -c "open(...)"``, ``make``, ``npm``), ``xargs`` and
``find -exec`` writers, ``dd``, ``mkdir`` and ``curl -o``, and a ``cd`` inside a sourced script. This stops a model by
accident or habit, not a determined one.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from typing import Dict, List, Optional, Tuple

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from shell_parse import (  # noqa: E402
    KEYWORDS, SHELLS, WRAPPERS, expand_vars, find_override, is_operator, lex, strip_prefixes,
)

MESSAGE = (
    "Blocked: this is the shared primary checkout of the repository, and other sessions work from it. One session, one "
    "worktree: call the EnterWorktree tool with a short kebab-case topic name (it branches from origin/main), then "
    "edit and commit there. Reading, `git fetch`, `gh pr view|create` and Agents with isolation \"worktree\" are fine from here. If this "
    "really is the intent, add `# worktree-ok: reason` to the command. See .agents/workflow/pr-lifecycle.md."
)
NO_WORKTREE_MESSAGE = (
    "You are in the parent session's worktree, probably because your isolation worktree was cleaned after you ended "
    "with no changes. Stop and report blocked with blocked_reason no_worktree; the orchestrator spawns you fresh."
)
#: The HEAD branches of the orchestrator's T3 session worktrees.
SESSION_BRANCH = re.compile(r"^t3/")


class SessionDenied(str):
    """A denial reason that is answered with ``NO_WORKTREE_MESSAGE`` instead of the primary-checkout ``MESSAGE``."""


OVERRIDE = re.compile(r"#\s*worktree-ok:\s*\S")
FILE_TOOLS = {"Edit", "Write", "MultiEdit", "NotebookEdit"}
GIT_MUTATING = {
    "commit", "add", "rm", "mv", "restore", "checkout", "switch", "reset", "merge", "rebase", "pull", "cherry-pick",
    "revert", "am", "apply", "clean", "stash",
}
APPLY_READONLY = {"--check", "--stat", "--numstat", "--summary"}
STASH_READONLY = {"list", "show"}
#: ``git`` options before the subcommand that take a separate value.
GIT_VALUE_OPTS = {"-c", "--git-dir", "--work-tree", "--namespace", "--super-prefix", "--exec-path", "--config-env"}
#: Options of the file writers that take a separate value.
COPY_VALUE = {"cp": {"-t"}, "mv": {"-t", "-S"}, "ln": {"-t", "-S"}, "install": {"-t", "-m", "-o", "-g", "-S"}}
TOUCH_VALUE = {"-t", "-d", "-r", "-A", "--date", "--reference"}
#: A long command is cut to the lines that can matter.
RELEVANT_LINE = re.compile(r"git|sed|perl|tee|touch|\bcp\b|\bmv\b|\bln\b|install|\brm|ship\.sh|>|cd\b|pushd|popd|env|\beval|sh\b")


# MARK: - Git

def _git_env() -> Dict[str, str]:
    """The environment for our own git calls: without the variables that select a repository."""
    return {k: v for k, v in os.environ.items() if k not in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR")}


def git(directory: str, *args: str) -> Optional[subprocess.CompletedProcess]:
    """Run git in ``directory`` with the repository-selecting environment removed; ``None`` if git cannot run."""
    try:
        return subprocess.run(["git", "-C", directory, *args], capture_output=True, text=True, timeout=10, env=_git_env())
    except (OSError, subprocess.SubprocessError):
        return None


#: The common git dir of the project's repository; only checkouts of that repository are guarded. ``None`` guards
#: every repository (direct use in tests); ``""`` means there is no project repository, so nothing is guarded.
_SCOPE: Optional[str] = None
_RAW_CACHE: Dict[str, Optional[Tuple[str, str, str]]] = {}


def raw_repo(directory: str) -> Optional[Tuple[str, str, str]]:
    """``(toplevel, git dir, common dir)``, all real paths, for the repository holding ``directory``, else ``None``."""
    key = os.path.realpath(directory)
    if key not in _RAW_CACHE:
        result: Optional[Tuple[str, str, str]] = None
        proc = git(key, "rev-parse", "--absolute-git-dir", "--git-common-dir", "--show-toplevel") if os.path.isdir(key) else None
        if proc and proc.returncode == 0:
            lines = proc.stdout.splitlines()
            if len(lines) == 3 and lines[2]:
                common = lines[1] if os.path.isabs(lines[1]) else os.path.join(key, lines[1])
                result = (os.path.realpath(lines[2]), os.path.realpath(lines[0]), os.path.realpath(common))
        _RAW_CACHE[key] = result
    return _RAW_CACHE[key]


def repo_info(directory: str) -> Optional[Tuple[str, bool]]:
    """``(toplevel, is_primary)`` for the repository holding ``directory``; ``None`` outside git or on any failure.

    ``is_primary`` is true only for the primary checkout of the project's repository (see ``_SCOPE``).
    """
    raw = raw_repo(directory)
    if not raw:
        return None
    top, git_dir, common = raw
    return top, git_dir == common and (_SCOPE is None or common == _SCOPE)


def git_dir_primary(path: str) -> Optional[str]:
    """The git dir ``path`` when it is the primary checkout's own git dir of the project's repository, else ``None``."""
    try:
        proc = subprocess.run(["git", "--git-dir=" + path, "rev-parse", "--absolute-git-dir", "--git-common-dir"],
                              capture_output=True, text=True, timeout=10, cwd="/", env=_git_env())
    except (OSError, subprocess.SubprocessError):
        return None
    lines = proc.stdout.splitlines() if proc.returncode == 0 else []
    if len(lines) != 2:
        return None
    git_dir, common = os.path.realpath(lines[0]), os.path.realpath(lines[1] if os.path.isabs(lines[1]) else os.path.join(git_dir, lines[1]))
    return git_dir if git_dir == common and (_SCOPE is None or common == _SCOPE) else None


def set_scope(payload: dict) -> None:
    """Scope the guard to the project's repository: ``$CLAUDE_PROJECT_DIR``'s, else the hook input's ``cwd``."""
    global _SCOPE
    candidates = [os.environ.get("CLAUDE_PROJECT_DIR") or str(payload.get("cwd") or os.getcwd())]
    _SCOPE = ""
    for candidate in candidates:
        raw = raw_repo(candidate) if candidate and os.path.isdir(candidate) else None
        if raw:
            _SCOPE = raw[2]
            break


def nearest_dir(path: str) -> Tuple[str, str]:
    """``(existing directory, real path)``: the directory itself or the nearest existing parent of ``path``."""
    path = os.path.normpath(path)
    current, tail = path, []
    while not os.path.isdir(current):
        parent, name = os.path.dirname(current), os.path.basename(current)
        if parent == current:
            break
        tail.insert(0, name)
        current = parent
    real = os.path.realpath(current)
    return real, os.path.join(real, *tail) if tail else real


def ignored_paths(top: str, reals: List[str]) -> set:
    """Which of ``reals`` (real paths in the checkout ``top``) git ignores, in one ``check-ignore --stdin`` call.

    A path that does not exist yet could be a directory, so ``path/`` is asked about too (for a pattern like ``build/``).
    """
    candidates: List[str] = []
    for real in reals:
        candidates.append(real)
        if not os.path.exists(real):
            candidates.append(real + "/")
    env = _git_env()
    try:
        proc = subprocess.run(["git", "-C", top, "check-ignore", "--no-index", "-z", "--stdin"],
                              input="\0".join(dict.fromkeys(candidates)) + "\0", capture_output=True, text=True,
                              timeout=30, env=env)
    except (OSError, subprocess.SubprocessError):
        return set()
    if proc.returncode not in (0, 1):
        return set()
    printed = set(proc.stdout.split("\0"))
    return {real for real in reals if real in printed or real + "/" in printed}


def first_blocked(paths: List[str]) -> Optional[Tuple[int, str]]:
    """``(index, toplevel)`` of the first path inside a primary checkout and not git-ignored there, else ``None``."""
    groups: Dict[str, List[Tuple[int, str]]] = {}
    for index, path in enumerate(paths):
        directory, real = nearest_dir(path)
        info = repo_info(directory)
        if info and info[1]:
            groups.setdefault(info[0], []).append((index, real))
    best: Optional[Tuple[int, str]] = None
    for top, items in groups.items():
        ignored = ignored_paths(top, [real for _, real in items])
        for index, real in items:
            if real not in ignored and (best is None or index < best[0]):
                best = (index, top)
    return best


def in_session_worktree(directory: Optional[str]) -> bool:
    """Whether ``directory`` is in a linked worktree of the project whose HEAD branch is ``t3/*``."""
    if not directory:
        return False
    real, _ = nearest_dir(directory)
    raw = raw_repo(real)
    if not raw or raw[1] == raw[2] or (_SCOPE and raw[2] != _SCOPE):
        return False
    proc = git(real, "symbolic-ref", "--short", "-q", "HEAD")
    return bool(proc and proc.returncode == 0 and SESSION_BRANCH.match(proc.stdout.strip()))


def primary_dir(directory: Optional[str]) -> Optional[str]:
    """The primary checkout's toplevel when ``directory`` is inside one, else ``None``."""
    if not directory:
        return None
    real, _ = nearest_dir(directory)
    info = repo_info(real)
    return info[0] if info and info[1] else None


# MARK: - Edit tools

def file_reason(payload: dict) -> Optional[str]:
    """Why an Edit/Write/MultiEdit/NotebookEdit target is refused, or ``None``."""
    tool_input = payload.get("tool_input") or {}
    target = str(tool_input.get("file_path") or tool_input.get("notebook_path") or "")
    if not target:
        return None
    cwd = str(payload.get("cwd") or os.getcwd())
    hit = first_blocked([target if os.path.isabs(target) else os.path.join(cwd, target)])
    return f"edit of {target} in the primary checkout {hit[1]}" if hit else None


# MARK: - Bash

def redirects(words: List[str]) -> Tuple[List[str], List[str]]:
    """``(words without redirects, write targets)``; fd duplications (``>&2``, ``2>&1``) are not targets."""
    kept: List[str] = []
    targets: List[str] = []
    i = 0
    while i < len(words):
        word = words[i]
        i += 1
        if re.fullmatch(r"[<>&|]+", word) and ("<" in word or ">" in word):
            if kept and kept[-1].isdigit():
                kept.pop()
            target = words[i] if i < len(words) else ""
            i += 1
            if ">" in word and target and not (word.endswith("&") and re.fullmatch(r"\d+|-", target)):
                targets.append(target)
        else:
            kept.append(word)
    return kept, targets


def positionals(args: List[str], value_opts: set) -> List[str]:
    """Non-option words, skipping the values of ``value_opts`` and honouring ``--``."""
    out: List[str] = []
    i = 0
    while i < len(args):
        arg = args[i]
        i += 1
        if arg == "--":
            out += args[i:]
            break
        if arg.startswith("-") and len(arg) > 1:
            if arg in value_opts:
                i += 1
        else:
            out.append(arg)
    return out


def edit_in_place(program: str, args: List[str]) -> List[str]:
    """The files ``sed -i`` / ``perl -i`` would rewrite (empty when it is not in-place)."""
    value_letters = "ef" if program == "sed" else "eE"
    inplace = script_given = False
    rest: List[str] = []
    i = 0
    while i < len(args):
        arg = args[i]
        i += 1
        if arg == "--":
            rest += args[i:]
            break
        if arg.startswith("--"):
            if arg.startswith("--in-place"):
                inplace = True
            elif arg in ("--expression", "--file"):
                script_given = True
                i += 1
            elif arg.startswith(("--expression=", "--file=")):
                script_given = True
        elif arg.startswith("-") and len(arg) > 1:
            letters = arg[1:]
            for at, ch in enumerate(letters):
                if ch == "i":
                    inplace = True
                    break
                if ch in value_letters:
                    script_given = True
                    if at == len(letters) - 1:
                        i += 1
                    break
        else:
            rest.append(arg)
    rest = [a for a in rest if a]
    return [] if not inplace else (rest if script_given else rest[1:])


def copy_targets(program: str, args: List[str]) -> List[str]:
    """Paths ``cp``/``mv``/``ln``/``install`` write (``mv`` also removes its sources)."""
    target_dir = ""
    for at, arg in enumerate(args):
        if arg == "-t" and at + 1 < len(args):
            target_dir = args[at + 1]
        elif arg.startswith("--target-directory="):
            target_dir = arg.split("=", 1)[1]
        elif arg == "--target-directory" and at + 1 < len(args):
            target_dir = args[at + 1]
    paths = positionals([a for a in args if not a.startswith("--target-directory")], COPY_VALUE[program])
    if program == "install" and "-d" in args:
        return paths
    if target_dir:
        return [target_dir] + (paths if program == "mv" else [])
    if len(paths) < 2:
        return []
    return [paths[-1]] + (paths[:-1] if program == "mv" else [])


def wrapper_info(words: List[str]) -> Tuple[Optional[str], Dict[str, str]]:
    """``(directory, git variables)`` from the leading words: ``env -C DIR`` / ``--chdir=DIR``, and ``GIT_DIR=…`` /
    ``GIT_WORK_TREE=…`` assignments (bare or after ``env``)."""
    chdir: Optional[str] = None
    assigns: Dict[str, str] = {}

    def assign(word: str) -> bool:
        m = re.match(r"^(\w+)=(.*)$", word, re.S)
        if m and m.group(1) in ("GIT_DIR", "GIT_WORK_TREE"):
            assigns[m.group(1)] = m.group(2)
        return bool(m)

    i = 0
    while i < len(words):
        word = words[i]
        base = os.path.basename(word)
        if word in KEYWORDS or assign(word):
            i += 1
        elif base in WRAPPERS:
            i += 1
            while i < len(words) and (words[i].startswith("-") or assign(words[i])):
                option = words[i]
                i += 1
                if base != "env" or not option.startswith("-"):
                    continue
                if option in ("-C", "--chdir") and i < len(words):
                    chdir = words[i]
                elif option.startswith("--chdir="):
                    chdir = option.split("=", 1)[1]
                elif re.match(r"^-[A-Za-z]*C.+$", option) and not option.startswith("--"):
                    chdir = option[option.index("C") + 1:]
        else:
            break
    return chdir, assigns


ARITHMETIC = re.compile(r"\$?\(\([^();]*\)\)")
CONDITIONAL = re.compile(r"\[\[.*?\]\]")


class Analyzer:
    """Walks one command line, keeping the effective directory, and records the first problem."""

    def __init__(self, cwd: str, project: str, home: str, subagent: bool = False) -> None:
        self.subagent = subagent
        self.project = project
        self.home = home
        self.initial = cwd
        self.why: Optional[str] = None
        self.targets: List[Tuple[str, str]] = []  # (absolute path, what) checked together at the end
        self.created: List[str] = []  # real paths of worktrees an earlier `git worktree add` made in this command

    # -- paths
    def resolve(self, raw: str, cur: Optional[str]) -> Optional[str]:
        """An absolute path for a word, or ``None`` when it depends on a variable or an unknown directory."""
        text = expand_vars(raw, cur or "", self.project, self.home)
        if not text or "$" in text or "`" in text:
            return None
        if os.path.isabs(text):
            return os.path.normpath(text)
        return os.path.normpath(os.path.join(cur, text)) if cur else None

    def is_created(self, path: str) -> bool:
        real = nearest_dir(path)[1]
        return any(real == c or real.startswith(c + os.sep) for c in self.created)

    def primary(self, directory: Optional[str]) -> Optional[str]:
        """The primary checkout's toplevel when ``directory`` is in one (and not a worktree this command created)."""
        if not directory or self.is_created(directory):
            return None
        return primary_dir(directory)

    def check_path(self, raw: str, cur: Optional[str], what: str) -> None:
        if not raw or raw.startswith("/dev/"):
            return
        path = self.resolve(raw, cur)
        if path and not self.is_created(path):
            self.targets.append((path, f"{what} {raw}"))

    def finish(self) -> Optional[str]:
        """The first problem found: a git or ship call, else the first unignored target in a primary checkout."""
        if self.why or not self.targets:
            return self.why
        hit = first_blocked([path for path, _ in self.targets])
        return f"{self.targets[hit[0]][1]} in the primary checkout {hit[1]}" if hit else None

    # -- git
    def git_command(self, args: List[str], cur: Optional[str], env_git: Dict[str, str]) -> None:
        directory = cur
        git_dir = env_git.get("GIT_DIR")
        work_tree = env_git.get("GIT_WORK_TREE")
        i = 0
        while i < len(args) and args[i].startswith("-"):
            option = args[i]
            i += 1
            if option == "-C" and i < len(args):
                target = self.resolve(args[i], directory)
                directory = target if target else None
                i += 1
            elif option.startswith("--work-tree=") or option.startswith("--git-dir=") or (
                    option in ("--work-tree", "--git-dir") and i < len(args)):
                value = option.split("=", 1)[1] if "=" in option else args[i]
                i += 0 if "=" in option else 1
                if option.startswith("--work-tree"):
                    work_tree = value
                else:
                    git_dir = value
            elif option in GIT_VALUE_OPTS and i < len(args):
                i += 1
        if i >= len(args):
            return
        sub, rest = args[i], args[i + 1:]
        if self.subagent and not self.why and self.branch_change(sub, rest) and in_session_worktree(directory):
            self.why = SessionDenied(f"git {sub} by a subagent in a session worktree")
            return
        if sub == "worktree":
            if rest[:1] == ["add"]:
                made = next(iter(positionals(rest[1:], {"-b", "-B", "--reason"})), "")
                path = self.resolve(made, directory) if made else None
                if path:
                    self.created.append(nearest_dir(path)[1])
            return
        mutating = sub in GIT_MUTATING or (sub == "branch" and any(a in ("-m", "-M", "--move") for a in rest))
        if not mutating or "--help" in rest or "-h" in rest:
            return
        if sub == "apply" and APPLY_READONLY & set(rest):
            return
        if sub == "stash" and next((a for a in rest if not a.startswith("-")), "") in STASH_READONLY:
            return
        top = None
        if work_tree is not None or git_dir is not None:
            if work_tree is not None:
                resolved = self.resolve(work_tree, directory)
                top = self.primary(resolved) if resolved else None
            if git_dir is not None and not top:
                resolved = self.resolve(git_dir, directory)
                top = git_dir_primary(resolved) if resolved else None
        else:
            top = self.primary(directory)
        if top:
            self.why = f"git {sub} in the primary checkout {top}"

    @staticmethod
    def branch_change(sub: str, rest: List[str]) -> bool:
        """Whether ``git <sub> <rest>`` switches or creates a branch (not a file restore: ``checkout [<rev>] -- f``)."""
        if "--help" in rest or "-h" in rest:
            return False
        if sub == "switch":
            return True
        if sub != "checkout" or "--" in rest:
            return False
        return any(a in ("-b", "-B", "--orphan", "--detach", "-d") for a in rest) or bool(positionals(rest, {"--conflict"}))

    # -- one simple command
    def simple(self, words: List[str], cur: Optional[str], depth: int) -> Optional[str]:
        """Check one simple command; returns the directory after it (``cd`` changes it)."""
        words, targets = redirects(words)
        for target in targets:
            self.check_path(target, cur, "redirect to")
        chdir, env_git = wrapper_info(words)
        if chdir is not None:
            resolved = self.resolve(chdir, cur)
            cur = resolved if resolved else None
        words = strip_prefixes(words)
        if not words:
            return cur
        program, args = os.path.basename(words[0]), words[1:]
        if program in ("cd", "pushd"):
            target = next((a for a in args if not a.startswith("-") or a == "-"), "")
            if not target:
                return self.home or None if program == "cd" else cur
            resolved = None if target == "-" else self.resolve(target, cur)
            return resolved if resolved else None
        if program == "popd":
            return None
        ships = program == "ship.sh" or (program in SHELLS and next((os.path.basename(a) for a in args if not a.startswith("-")), "") == "ship.sh")
        first_arg = next((os.path.basename(a) for a in args if not a.startswith("-")), "")
        runs_setup = program == "setup.sh" or (program in SHELLS and first_arg == "setup.sh")
        if runs_setup and self.subagent and in_session_worktree(cur):
            self.why = SessionDenied("tools/setup.sh by a subagent in a session worktree")
        elif ships:
            top = self.primary(cur)
            if top:
                self.why = f"tools/ship.sh from the primary checkout {top}"
        elif program in SHELLS and depth < 3:
            for at, arg in enumerate(args[:-1]):
                if re.match(r"^-[A-Za-z]*c[A-Za-z]*$", arg):
                    self.walk(args[at + 1], cur, depth + 1)
        elif program == "eval" and depth < 3:
            self.walk(" ".join(args), cur, depth + 1)
        elif program == "git":
            self.git_command(args, cur, env_git)
        elif program == "gh" and (args[:2] == ["pr", "checkout"] or args[:2] == ["repo", "sync"]):
            top = self.primary(cur)
            if top:
                self.why = f"gh {args[0]} {args[1]} changes the branch of the primary checkout {top}"
        elif program == "patch" and "--dry-run" not in args:
            top = self.primary(cur)
            if top:
                self.why = f"patch in the primary checkout {top}"
        elif program in ("sed", "perl"):
            for path in edit_in_place(program, args):
                self.check_path(path, cur, f"{program} -i on")
        elif program == "tee":
            for path in positionals(args, set()):
                self.check_path(path, cur, "tee to")
        elif program == "touch":
            for path in positionals(args, TOUCH_VALUE):
                self.check_path(path, cur, "touch")
        elif program == "truncate":
            for path in positionals(args, {"-s", "-r", "--size", "--reference"}):
                self.check_path(path, cur, "truncate")
        elif program in COPY_VALUE:
            for path in copy_targets(program, args):
                self.check_path(path, cur, f"{program} into")
        elif program in ("rm", "rmdir"):
            for path in positionals(args, set()):
                self.check_path(path, cur, f"{program} of")
        return cur

    def walk(self, command: str, start: Optional[str], depth: int = 0) -> None:
        """Walk the simple commands of ``command`` in order, tracking ``cd`` and subshell parentheses."""
        text = command.replace("$(pwd)", "${PWD}").replace("`pwd`", "${PWD}")
        text = CONDITIONAL.sub("true", ARITHMETIC.sub("0", text))  # `[[ a > b ]]` and `$((1>2))` are not redirects
        cur = start
        stack: List[Optional[str]] = []
        words: List[str] = []

        def flush() -> None:
            nonlocal cur, words
            if words and not self.why:
                cur = self.simple(words, cur, depth)
            words = []

        for token in lex(text, RELEVANT_LINE):
            if is_operator(token):
                flush()
                for ch in token:
                    if ch == "(":
                        stack.append(cur)
                    elif ch == ")" and stack:
                        cur = stack.pop()
            else:
                words.append(token)
        flush()


def bash_reason(command: str, cwd: str, subagent: bool = False) -> Optional[str]:
    """Why ``command`` changes a primary checkout, or ``None``."""
    if find_override(command, OVERRIDE):
        return None
    analyzer = Analyzer(cwd, os.environ.get("CLAUDE_PROJECT_DIR", ""), os.environ.get("HOME", ""), subagent)
    analyzer.walk(command, os.path.realpath(cwd) if cwd else None)
    return analyzer.finish()


# MARK: - Entry points

def session_start(payload: dict) -> int:
    """Print the SessionStart context when the session starts in a primary checkout."""
    cwd = str(payload.get("cwd") or os.getcwd())
    top = primary_dir(cwd)
    if not top:
        return 0
    context = (
        f"This session started in the shared primary checkout {top}. Before any edit, commit or branch change, call the "
        "EnterWorktree tool with a short kebab-case topic name (it branches from origin/main). Reading files, "
        "`git fetch`, `gh pr view|create` and launching agents with isolation \"worktree\" are fine from here; edits and commits here are "
        "blocked by worktree_guard (.agents/workflow/pr-lifecycle.md)."
    )
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": context}}))
    return 0


def main(argv: Optional[List[str]] = None) -> int:
    """Read the hook payload from stdin; exit 2 with ``MESSAGE`` to block a PreToolUse call."""
    argv = sys.argv[1:] if argv is None else argv
    try:
        payload = json.load(sys.stdin)
        if not isinstance(payload, dict):
            return 0
        set_scope(payload)
        if "--session-start" in argv:
            return session_start(payload)
        tool = payload.get("tool_name")
        why: Optional[str] = None
        if tool in FILE_TOOLS:
            why = file_reason(payload)
        elif tool == "Bash":
            command = str((payload.get("tool_input") or {}).get("command", ""))
            why = bash_reason(command, str(payload.get("cwd") or os.getcwd()), bool(payload.get("agent_id")))
    except Exception:  # a hook must never break the session: fail open
        return 0
    if why:
        reply = NO_WORKTREE_MESSAGE if isinstance(why, SessionDenied) else MESSAGE
        print(f"{reply} (matched: {why})", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
