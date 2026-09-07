import unittest
from publish_android import check_package, android_version_code


class ApkIdentityTest(unittest.TestCase):
    package = "package: name='tj.yourtj.forum_app' versionCode='12' versionName='1.2.0'"
    certificate = 'ab' * 32

    def test_flutter_split_version_codes(self):
        self.assertEqual(android_version_code('2', 'arm64-v8a'), '2002')
        self.assertEqual(android_version_code('2', 'armeabi-v7a'), '1002')
        self.assertEqual(android_version_code('2', 'x86_64'), '4002')
        with self.assertRaises(ValueError): android_version_code('2100000000', 'arm64-v8a')

    def test_accepts_verified_release_identity(self):
        check_package(self.package, 'Signer #1 certificate SHA-256 digest: ' + self.certificate,
                      '1.2.0', '12', self.certificate)

    def test_rejects_wrong_identity_or_debug_certificate(self):
        signature = 'Signer #1 certificate SHA-256 digest: ' + self.certificate
        for package, signed in [(self.package.replace('forum_app', 'other'), signature),
                                (self.package.replace("'12'", "'11'"), signature),
                                (self.package, signature.replace(self.certificate, 'cd' * 32)),
                                (self.package, ''),
                                (self.package, signature + '\nSigner #2 certificate SHA-256 digest: ' + 'cd' * 32)]:
            with self.subTest(package=package), self.assertRaises(ValueError):
                check_package(package, signed, '1.2.0', '12', self.certificate)


if __name__ == '__main__':
    unittest.main()
