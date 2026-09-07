import datetime
import unittest

from build_ios import validate_profile


class DistributionProfileTest(unittest.TestCase):
    def setUp(self):
        self.now = datetime.datetime(2026, 9, 7, tzinfo=datetime.timezone.utc)
        self.profile = {
            "UUID": "ad5aac45-d8c0-4efa-bad7-cd8e4023afd5",
            "ExpirationDate": datetime.datetime(2027, 1, 1),
            "TeamIdentifier": ["4HJTS3G3T2"],
            "Entitlements": {"application-identifier": "4HJTS3G3T2.tj.yourtj.forumApp", "get-task-allow": False},
        }

    def test_app_store_profile(self):
        validate_profile(self.profile, "4HJTS3G3T2", self.now)

    def test_rejects_wrong_team_bundle_expiry_or_profile_type(self):
        from copy import deepcopy
        variants = []
        for key, value in [
            ("TeamIdentifier", ["OTHERTEAM1"]),
            ("ExpirationDate", datetime.datetime(2026, 9, 6)),
            ("ProvisionedDevices", ["some-device"]),
            ("ProvisionsAllDevices", True),
            ("UUID", "../../profile"),
        ]:
            profile = deepcopy(self.profile)
            profile[key] = value
            variants.append(profile)
        for key, value in [("get-task-allow", True), ("application-identifier", "4HJTS3G3T2.other.app")]:
            profile = deepcopy(self.profile)
            profile["Entitlements"][key] = value
            variants.append(profile)
        for profile in variants:
            with self.subTest(profile=profile), self.assertRaises(ValueError):
                validate_profile(profile, "4HJTS3G3T2", self.now)


if __name__ == "__main__":
    unittest.main()
