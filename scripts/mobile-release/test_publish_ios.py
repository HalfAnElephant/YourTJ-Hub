from pathlib import Path
import os
import unittest
from unittest.mock import patch
import publish_ios as publisher


class IosResumeTest(unittest.TestCase):
    def setUp(self):
        self.env = patch.dict(os.environ, MOBILE_VERSION='1.0.1', MOBILE_BUILD_NUMBER='2', IOS_IPA_PATH='/unused.ipa')
        self.env.start()
        self.addCleanup(self.env.stop)

    def test_already_submitted_build_does_not_upload_or_resubmit(self):
        calls = []
        def asc(*args, **kwargs):
            calls.append(args)
            if args[:2] == ('builds', 'list'):
                return {'data': [{'id': 'build', 'attributes': {'processingState': 'VALID'}}]}
            if args[:3] == ('builds', 'beta-app-review-submission', 'view'):
                return {'data': {'attributes': {'betaReviewState': 'WAITING_FOR_REVIEW'}}}
            if args[:2] == ('versions', 'list'):
                return {'data': [{'id': 'version', 'attributes': {'appStoreState': 'WAITING_FOR_REVIEW'}, 'relationships': {'build': {'data': {'id': 'build'}}}}]}
            if args[:2] == ('builds', 'update'): return {}
            self.fail(f'Unexpected mutation: {args[:2]}')
        with patch.object(publisher, 'asc', side_effect=asc):
            publisher.main()
        self.assertFalse(any('upload' in call or 'submit' in call for call in calls))

    def test_incomplete_upload_reservation_requires_recovery_not_duplicate_upload(self):
        def asc(*args, **kwargs):
            if args[:2] == ('builds', 'list'): return {'data': []}
            if args[:3] == ('builds', 'uploads', 'list'):
                return {'data': [{'attributes': {'cfBundleShortVersionString': '1.0.1', 'cfBundleVersion': '2'}}]}
            self.fail('Unexpected upload')
        with patch.object(publisher, 'asc', side_effect=asc), self.assertRaisesRegex(ValueError, 'incomplete upload'):
            publisher.main()

    def test_invalid_processing_fails_without_waiting(self):
        with patch.object(publisher, 'find_build', return_value={'attributes': {'processingState': 'INVALID'}}), self.assertRaisesRegex(ValueError, 'rejected'):
            publisher.wait_for_build('1.0.1', '2')

    def test_new_version_creates_missing_review_details_and_submits(self):
        import json
        from tempfile import TemporaryDirectory
        calls = []
        def asc(*args, **kwargs):
            calls.append(args)
            prefix = args[:2]
            if prefix == ('builds', 'list'):
                return {'data': [{'id': 'build', 'attributes': {'processingState': 'VALID'}}]}
            if args[:3] == ('builds', 'beta-app-review-submission', 'view'):
                return {'data': None}
            if args[:3] == ('testflight', 'review', 'view'): return {'data': {'id': 'beta-details'}}
            if prefix == ('versions', 'list'): return {'data': []}
            if prefix == ('versions', 'create'): return {'data': {'id': 'version'}}
            if prefix == ('localizations', 'list'): return {'data': []}
            if prefix == ('localizations', 'create'): return {'data': {'id': 'locale'}}
            if prefix == ('review', 'details-for-version'):
                self.assertTrue(kwargs.get('allow_missing'))
                return {'data': None}
            if prefix == ('review', 'submit'): return {'submissionId': 'submission'}
            return {}
        contact = {key: 'example' for key in publisher.REVIEW_FIELDS}
        with TemporaryDirectory() as temp:
            store = Path(temp) / 'apps/mobile/store/zh-Hans'
            store.mkdir(parents=True)
            (store / 'metadata.json').write_text(json.dumps({'description': 'Community', 'whatsNew': 'Update'}))
            with patch.object(publisher, 'ROOT', Path(temp)), patch.object(publisher, 'asc', side_effect=asc), patch.dict(os.environ, IOS_REVIEW_JSON=json.dumps(contact)):
                publisher.main()
        self.assertIn(('review', 'details-create'), [call[:2] for call in calls])
        self.assertIn(('publish', 'testflight'), [call[:2] for call in calls])
        self.assertIn(('review', 'submit'), [call[:2] for call in calls])

    def test_cli_failures_do_not_echo_private_review_data(self):
        from subprocess import CompletedProcess
        with patch.object(publisher.subprocess, 'run', return_value=CompletedProcess([], 1, '', 'secret-demo-password')):
            with self.assertRaises(RuntimeError) as error:
                publisher.asc('review', 'details-update', '--demo-account-password', 'secret-demo-password')
        self.assertNotIn('secret-demo-password', str(error.exception))
