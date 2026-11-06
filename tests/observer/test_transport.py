# SPDX-License-Identifier: Apache-2.0
from pathlib import Path
import os
import socket
from unittest.mock import patch
import sys
import tempfile
import time
import unittest
from observer.transport import ObserverError, bounded, decode_json


class JsonBoundaryTests(unittest.TestCase):
    def test_duplicate_members_and_nonfinite_numbers_are_rejected(self):
        for data in [b'{"fresh":true,"fresh":false}', b'{"sampled_at":NaN}', b'{"sampled_at":Infinity}',
                     b'{"value":1e400}', b'{"value":-1e400}']:
            with self.assertRaises(ObserverError):
                decode_json(data)


@unittest.skipUnless(sys.platform == 'linux', 'Linux process-group/WAITID contract')
class ProcessBoundaryTests(unittest.TestCase):
    def test_ssh_does_not_execute_an_inherited_path_substitute(self):
        from observer.transport import ssh_json
        if not Path('/usr/bin/ssh').is_file():
            self.skipTest('system OpenSSH unavailable')
        with tempfile.TemporaryDirectory(prefix='nbh-path-') as directory, socket.socket() as reserved:
            fake = Path(directory)/'ssh'
            fake.write_text('#!/bin/sh\necho invoked > "$0.invoked"\nprintf "{}"\n')
            fake.chmod(0o700)
            reserved.bind(('127.0.0.1', 0))
            spec = dict(host='127.0.0.1', port=reserved.getsockname()[1], user='root',
                        identity_file=directory+'/key', known_hosts_file=directory+'/hosts')
            with patch.dict(os.environ, {'PATH': directory}):
                with self.assertRaises(ObserverError):
                    ssh_json(spec, 2)
            self.assertFalse(Path(str(fake)+'.invoked').exists())

    def test_output_limit_is_combined_and_fails_closed(self):
        with self.assertRaisesRegex(ObserverError, 'OUTPUT_LIMIT'):
            bounded([sys.executable, '-c', 'import os;os.write(1,b"a"*700);os.write(2,b"b"*700)'], 2, 1024)

    def test_closing_both_pipes_does_not_bypass_the_deadline(self):
        with self.assertRaisesRegex(ObserverError, 'COMMAND_TIMEOUT'):
            bounded([sys.executable, '-c', 'import os,time;os.close(1);os.close(2);time.sleep(5)'], .25)

    def test_successful_leader_cannot_leave_a_delayed_writer(self):
        script = '''import os,sys,time
from pathlib import Path
root=Path(sys.argv[1])
r,w=os.pipe()
pid=os.fork()
if pid:
 os.close(w);os.read(r,1);os._exit(0)
os.close(r)
(root/'ready').write_text('child-started')
os.write(w,b'1');os.close(w)
os.close(1);os.close(2)
time.sleep(1)
(root/'late').write_text('orphan-write')
'''
        with tempfile.TemporaryDirectory(prefix='nbh-observer-process-') as directory:
            result = bounded([sys.executable, '-c', script, directory], 2)
            self.assertEqual(result['exit'], 0)
            self.assertTrue((Path(directory)/'ready').exists())
            time.sleep(1.2)
            self.assertFalse((Path(directory)/'late').exists())


if __name__ == '__main__':
    unittest.main()
