"""
plastimatch: Python distribution of the plastimatch medical image processing tools.

The wheels wrap official plastimatch command line executables. This module exposes each
of them both as a console script (installed on PATH by pip) and as a callable, so that

    plastimatch synth --output sphere.mha --pattern sphere

and

    from plastimatch import plastimatch

behave the same way.
"""

from __future__ import annotations

import subprocess
import sys
from collections.abc import Callable
from importlib.metadata import distribution
from pathlib import Path
from typing import NoReturn

from ._version import version as __version__

# Suffixes that identify a launchable executable inside plastimatch/bin. The Windows
# wheels also ship MSVC runtime DLLs in that directory; those are dependencies of the
# executables, not tools, and must not be turned into console scripts.
_EXECUTABLE_SUFFIXES = frozenset({"", ".exe"})


def _lookup(name: str) -> Path:
    executable_path = f"plastimatch/bin/{name}"
    files = distribution("plastimatch").files
    if files is not None:
        for _file in files:
            if str(_file).startswith(executable_path):
                return Path(_file.locate()).resolve(strict=True)
    msg = f"Failed to lookup '{executable_path}` directory."
    raise FileNotFoundError(msg)


def _program(name: str, args: list[str]) -> int:
    return subprocess.call([_lookup(name), *args], close_fds=False)


def _make_wrapper(name: str) -> Callable[[], NoReturn]:
    def _wrapper() -> NoReturn:
        raise SystemExit(_program(name, sys.argv[1:]))

    _wrapper.__name__ = name
    _wrapper.__qualname__ = name
    _wrapper.__doc__ = (
        f"Run the {name} executable with arguments passed to a Python script."
    )
    return _wrapper


def _discover_binaries() -> list[str]:
    """Return names of all executables installed in plastimatch/bin/."""
    files = distribution("plastimatch").files
    if files is None:
        return []
    binaries = []
    for _file in files:
        parts = Path(str(_file)).parts
        if len(parts) == 3 and parts[0] == "plastimatch" and parts[1] == "bin":
            path = Path(parts[2])
            if path.suffix.lower() in _EXECUTABLE_SUFFIXES:
                binaries.append(path.stem)
    return sorted(binaries)


# Dynamically create wrapper functions for each installed binary
_binaries = _discover_binaries()
for _name in _binaries:
    globals()[_name] = _make_wrapper(_name)

__all__ = ["__version__", *_binaries]  # noqa: PLE0604
