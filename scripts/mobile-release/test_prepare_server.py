import unittest
from prepare_server import next_version


class ServerVersionTest(unittest.TestCase):
    def test_mobile_and_non_release_tags_do_not_affect_server(self):
        self.assertEqual(next_version(['v1.9.0', 'v1.10.2', 'mobile-v99.0.0', 'v2.0.0-beta'], 'patch'), 'v1.10.3')
        self.assertEqual(next_version([], 'minor'), 'v0.1.0')
        self.assertEqual(next_version(['v1.9.0'], 'major'), 'v2.0.0')
        with self.assertRaises(ValueError): next_version([], 'invalid')
