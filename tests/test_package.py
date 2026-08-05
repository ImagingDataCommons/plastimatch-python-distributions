from __future__ import annotations

import importlib.metadata

import plastimatch as m


def test_version():
    assert importlib.metadata.version("plastimatch") == m.__version__
