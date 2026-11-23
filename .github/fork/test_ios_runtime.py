import tempfile
from pathlib import Path
import unittest
from unittest.mock import patch

from verify_ios_runtime import verify


class RuntimeTest(unittest.TestCase):
    def test_missing_framework_is_rejected_before_tool_invocation(self):
        with tempfile.TemporaryDirectory() as temp, patch('subprocess.check_output') as tool:
            with self.assertRaisesRegex(RuntimeError, 'Missing rhttp'):
                verify(Path(temp))
            tool.assert_not_called()

    def test_static_binary_and_missing_api_are_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            app = Path(temp)
            binary = app / 'Frameworks/rhttp.framework/rhttp'
            binary.parent.mkdir(parents=True)
            binary.touch()
            with patch('subprocess.check_output', return_value='MH_OBJECT'):
                with self.assertRaisesRegex(RuntimeError, 'dynamic Mach-O'):
                    verify(app)
            with patch('subprocess.check_output', side_effect=['DYLIB', '_unrelated']):
                with self.assertRaisesRegex(RuntimeError, 'entry point'):
                    verify(app)
            with patch('subprocess.check_output', side_effect=[
                    'DYLIB', '_frb_get_rust_content_hash']):
                with self.assertRaisesRegex(RuntimeError, 'Rust API'):
                    verify(app)


if __name__ == '__main__':
    unittest.main()
