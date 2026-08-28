#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause

import json
import sys
from pathlib import Path
from typing import NoReturn


def fail(message: str) -> NoReturn:
    raise SystemExit(f"Refusing: {message}")


if len(sys.argv) != 2:
    fail("expected one luci-mod-system ACL path")

path = Path(sys.argv[1])
try:
    acl = json.loads(path.read_text(encoding="utf-8"))
except (OSError, UnicodeError, json.JSONDecodeError) as error:
    fail(f"cannot parse LuCI mount ACL: {error}")

try:
    file_grants = acl["luci-mod-system-mounts"]["write"]["file"]
except (KeyError, TypeError):
    fail("LuCI mount ACL has an unexpected structure")

if not isinstance(file_grants, dict):
    fail("LuCI mount ACL file grants are not an object")

if "/etc/crontabs/root" in file_grants:
    fail("LuCI mount ACL can still write the root crontab")
