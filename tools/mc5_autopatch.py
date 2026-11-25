"""Automatic compatibility patch for Mod Constructor 5 generated Python.

Covers the two known MC5 generation bugs (D:\Memories\KNOWN_BUGS.md):

1.1 InstanceManager injections (AddSuperAffordances / AddMixer / ...):

    def ..._AddSuperAffordances_Phone(original, self, packs_to_load=None):
        original(self, packs_to_load)

The current Sims 4 build calls InstanceManager.load_data_into_class_instances()
with only self, so the generated call raises TypeError and breaks
tuning_instance_manager during lot loading. The signature becomes
(original, self, *args, **kwargs) and the call original(self, *args, **kwargs).

3.8 ActionTrigger injection (SimInfoManager.on_loading_screen_animation_finished):

    def ..._activate_action_triggers(original, self, *args, **kwargs):
        for objective in ...

The generated function receives original but never calls it, so the game
method is fully replaced (e.g. the whole family travels when one sim travels).
The patch inserts result = original(self, *args, **kwargs), wraps the body in
try/except and returns result.

This module hooks py_compile.compile(), which is used by
`python -m compileall` during MC5 export. It rewrites the generated source
before compilation, so both the .py and .pyc inside the exported .ts4script
are correct. It only touches files that contain the exact MC5 patterns.
"""

import datetime
import io
import os
import py_compile
import re
import tokenize

LOG_PATH = r"C:\Users\User\Documents\The Sims 4 Mod Constructor\Projects\_Tools\mc5_autopatch.log"

_SIGNATURE_RE = re.compile(r"def (\w+)\(original, self, packs_to_load=None\):")
_CALL_RE = re.compile(r"(?m)^([ \t]+)original\(self, packs_to_load\)[ \t]*\r?$")
_ACTION_TRIGGER_RE = re.compile(
    r"(?m)^def (\w+_activate_action_triggers)\(original, self, \*args, \*\*kwargs\):"
    r"[ \t]*\r?\n((?:(?:[ \t]+[^\r\n]*)?\r?\n)*)"
)


def _log(message):
    try:
        os.makedirs(os.path.dirname(LOG_PATH), exist_ok=True)
        with open(LOG_PATH, "a", encoding="utf-8") as log_file:
            timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            log_file.write("%s %s\n" % (timestamp, message))
    except Exception:
        pass


def _has_code_name(text, name):
    """True if `name` is used as a Python name, ignoring comments and strings."""
    try:
        for token in tokenize.generate_tokens(io.StringIO(text).readline):
            if token.type == tokenize.NAME and token.string == name:
                return True
    except (IndentationError, tokenize.TokenError):
        return name in text
    return False


def _patch_packs_to_load(text):
    """Bug 1.1: packs_to_load=None signature and call -> *args, **kwargs."""
    if "packs_to_load" not in text or "load_data_into_class_instances" not in text:
        return text, 0, 0, False
    text, defs = _SIGNATURE_RE.subn(r"def \1(original, self, *args, **kwargs):", text)
    text, calls = _CALL_RE.subn(r"\1original(self, *args, **kwargs)", text)
    if defs == 0 and calls == 0:
        return text, 0, 0, False
    # Ignore comments/strings that mention packs_to_load (the projects contain
    # explanatory comments). Refuse only if an actual code reference remains.
    if _has_code_name(text, "packs_to_load"):
        return text, 0, 0, True
    return text, defs, calls, False


def _patch_action_trigger(text, newline):
    """Bug 3.8: wrap ActionTrigger injections that never call original."""
    count = 0

    def _fix(match):
        nonlocal count
        name, body = match.group(1), match.group(2)
        if "original(" in body:
            return match.group(0)
        body = body.replace("\r\n", "\n").replace("\r", "\n").rstrip("\n")
        indented = newline.join(
            ("    " + line) if line.strip() else ""
            for line in body.split("\n")
        )
        count += 1
        return (
            "def %s(original, self, *args, **kwargs):%s"
            "    result = original(self, *args, **kwargs)%s"
            "    try:%s"
            "%s%s"
            "    except Exception:%s"
            "        import traceback%s"
            "        traceback.print_exc()%s"
            "    return result"
            % (name, newline, newline, newline, indented, newline,
               newline, newline, newline)
        ) + newline

    text = _ACTION_TRIGGER_RE.sub(_fix, text)
    return text, count


def _patch_source(path):
    try:
        with open(path, "rb") as source_file:
            raw = source_file.read()
    except Exception:
        return False

    try:
        text = raw.decode("utf-8-sig")
    except Exception:
        return False
    newline = "\r\n" if "\r\n" in text else "\n"

    text, defs, calls, refused = _patch_packs_to_load(text)
    if refused:
        _log("SKIP %s: pattern remains after partial rewrite" % path)
        return False
    text, triggers = _patch_action_trigger(text, newline)

    if defs == 0 and calls == 0 and triggers == 0:
        return False

    try:
        compile(text, path, "exec")
    except SyntaxError as exc:
        _log("SKIP %s: patched source does not compile: %r" % (path, exc))
        return False

    output = text.encode("utf-8-sig" if raw.startswith(b"\xef\xbb\xbf") else "utf-8")
    with open(path, "wb") as source_file:
        source_file.write(output)

    _log("PATCHED %s defs=%d calls=%d action_triggers=%d" % (path, defs, calls, triggers))
    return True


_original_compile = py_compile.compile


def _compile(file, *args, **kwargs):
    _patch_source(file)
    return _original_compile(file, *args, **kwargs)


py_compile.compile = _compile
