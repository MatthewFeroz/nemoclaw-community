# SPDX-FileCopyrightText: Copyright (c) 2026 Merge. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
"""Exercise key issuance without contacting Agent Handler."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

RECIPE = Path(__file__).resolve().parents[1]


class KeyIssuanceTests(unittest.TestCase):
    def test_keys_use_stdin_and_files_are_private(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            shutil.copytree(RECIPE / "scripts", root / "scripts")
            envfile = root / ".env"
            envfile.write_text("MERGE_AH_TOOL_PACK_ID=reader\n"
                               "MERGE_AH_REGISTERED_USER_ID=test-user\n"
                               "MERGE_AH_ADMIN_KEY=old-management-value\n"
                               "MERGE_AH_MCP_TOKEN=old-runtime-value\n")
            envfile.chmod(0o644)
            bindir = root / "bin"
            bindir.mkdir()
            curl = bindir / "curl"
            curl.write_text("#!/usr/bin/env python3\n" +
                "import json, os, sys\n" +
                "assert 'MERGE_AH_ADMIN_KEY' not in os.environ\n" +
                "assert 'entered-management-value' not in str(sys.argv)\n" +
                "assert sys.stdin.read().strip() == 'Authorization: Bearer entered-management-value'\n" +
                "body = json.loads(sys.argv[sys.argv.index('--data') + 1])\n" +
                "assert body['tool_pack_ids'] == ['reader']\n" +
                "assert body['registered_user_ids'] == ['test-user']\n" +
                "assert body['scopes'] == ['runtime:all']\n" +
                "print(json.dumps({'key': \"runtime-test-$(touch SHOULD_NOT_EXIST)'value\"}))\n")
            curl.chmod(0o755)
            # Record Python argv to catch accidental key exposure to the writer.
            python = bindir / "python3"
            python.write_text("#!/bin/sh\nprintf '%s\\n' \"$@\" >> \"$ARGV_LOG\"\nexec " +
                              shutil.which("python3") + " \"$@\"\n")
            python.chmod(0o755)
            env = dict(os.environ, PATH=str(bindir) + os.pathsep + os.environ['PATH'],
                       ARGV_LOG=str(root / "argv.log"))
            result = subprocess.run(['bash', str(root / 'scripts/issue-runtime-key.sh')],
                                    input='entered-management-value\n', text=True,
                                    capture_output=True, env=env, cwd=root)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn('entered-management-value', result.stdout + result.stderr)
            self.assertNotIn('runtime-test-', result.stdout + result.stderr)
            self.assertNotIn('runtime-test-', (root / 'argv.log').read_text())
            for path in [envfile, root / '.env.bak']:
                self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            loaded = subprocess.run(['bash', '-c', '. "$1"; printf %s "$MERGE_AH_MCP_TOKEN"',
                                     'test', str(envfile)], capture_output=True, text=True, cwd=root)
            self.assertEqual(loaded.stdout, "runtime-test-$(touch SHOULD_NOT_EXIST)'value")
            self.assertFalse((root / 'SHOULD_NOT_EXIST').exists())


if __name__ == '__main__':
    unittest.main()
