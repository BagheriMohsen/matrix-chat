import importlib.util
import tempfile
import time
import unittest
from pathlib import Path


SPEC = importlib.util.spec_from_file_location("analytics_server", Path(__file__).parents[1] / "src/analytics/server.py")
analytics = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(analytics)


class AnalyticsCollectionTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        analytics.DATA_DIR = Path(self.directory.name)
        analytics.LAST_SUMMARY = None
        analytics.LAST_COLLECT_AT = 0

    def tearDown(self):
        self.directory.cleanup()

    def test_uses_last_seen_and_paginates(self):
        now = int(time.time() * 1000)
        calls = []

        def fake_request(path, token=None, body=None, timeout=8):
            calls.append(path)
            if "v2/users" in path:
                return {"users": [{"name": "@recent:test", "last_seen_ts": now - 1000}, {"name": "@old:test", "last_seen_ts": now - 9 * 86400000}]}
            if "v1/rooms" in path:
                return {"rooms": [{"room_id": "!one:test"}]}
            if "statistics/users/media" in path:
                return {"users": [{"media_count": 2, "media_length": 42}]}
            raise AssertionError(path)

        original = analytics.request_json
        analytics.request_json = fake_request
        try:
            result = analytics.collect("server-admin-token")
        finally:
            analytics.request_json = original
        self.assertEqual(result["users"], 2)
        self.assertEqual(result["rooms"], 1)
        self.assertEqual(result["activity"]["5m"], 1)
        self.assertEqual(result["activity"]["7d"], 1)
        self.assertEqual(result["media_files"], 2)
        self.assertEqual(result["media_bytes"], 42)
        self.assertTrue(any("statistics/users/media" in call for call in calls))


if __name__ == "__main__":
    unittest.main()
