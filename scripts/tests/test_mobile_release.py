"""Offline orchestration tests. Never invokes Flutter, signing tools or store APIs."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
MOCK_TOOL = r'''
import json, os, pathlib, shutil, sys
tool = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ['MOCK_LOG'], 'a') as log:
    log.write(json.dumps({'tool': tool, 'args': args,
        'ipa': os.environ.get('CHECKY_IPA_PATH'),
        'aab': os.environ.get('CHECKY_AAB_PATH'),
        'status': os.environ.get('CHECKY_ANDROID_STATUS')}) + '\n')
if tool == 'uname':
    print('Darwin')
if tool == 'flutter' and args == ['clean']:
    shutil.rmtree('build', ignore_errors=True)
if tool == 'flutter' and args and args[0] == 'build':
    if os.environ.get('MOCK_BUILD_FAILURE') == args[1]:
        sys.exit(23)
    if os.environ.get('MOCK_STALE') != args[1]:
        mode = next((arg[2:] for arg in args if arg in ['--release', '--debug', '--profile']), 'release')
        target = {'ipa': 'build/ios/ipa/Checky.ipa',
            'appbundle': f'build/app/outputs/bundle/{mode}/app-{mode}.aab',
            'apk': f'build/app/outputs/flutter-apk/app-{mode}.apk'}[args[1]]
        path = pathlib.Path(target)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b'fake signed artifact')
if tool == 'fastlane' and os.environ.get('MOCK_UPLOAD_FAILURE') in args:
    sys.exit(24)
'''


class MobileReleaseTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='checky release tests ')
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name) / 'repo with spaces'
        self.scripts = self.repo / 'scripts'
        self.scripts.mkdir(parents=True)
        for name in ['release-mobile.sh', 'build-android.sh']:
            shutil.copy2(ROOT / 'scripts' / name, self.scripts / name)
        self.mobile = self.repo / 'apps/mobile'
        (self.mobile / 'android').mkdir(parents=True)
        self.pubspec = self.mobile / 'pubspec.yaml'
        self.pubspec.write_text('name: test\nversion: 1.7.0+69\n')
        (self.mobile / 'android/key.properties').write_text(
            'storePassword=fake\nkeyPassword=fake\nkeyAlias=fake\nstoreFile=fake.jks\n')
        (self.mobile / 'android/fake.jks').write_text('fake')
        self.bin = Path(self.temp.name) / 'bin'
        self.bin.mkdir()
        for name in ['flutter', 'dart', 'fastlane', 'xcrun', 'uname']:
            path = self.bin / name
            path.write_text(f'#!{sys.executable}\n' + MOCK_TOOL)
            path.chmod(0o755)
        self.env = os.environ.copy()
        for key in ['BUILD_NAME', 'BUILD_NUMBER', 'API_BASE_URL', 'KAKAO_NATIVE_APP_KEY']:
            self.env.pop(key, None)
        self.log = Path(self.temp.name) / 'commands.jsonl'
        self.env.update(PATH=str(self.bin) + os.pathsep + self.env['PATH'],
                        MOCK_LOG=str(self.log), ASC_KEY_ID='fake-id', ASC_ISSUER_ID='fake-issuer')
        for key, file in [('ASC_KEY_FILE', 'AuthKey_fake.p8'), ('GOOGLE_PLAY_JSON_KEY', 'google-play.json')]:
            path = Path(self.temp.name) / file
            path.write_text('FAKE-PRIVATE-KEY-MUST-NOT-BE-PRINTED')
            self.env[key] = str(path)

    def run_script(self, *args, old=False, ok=True):
        script = self.scripts / ('build-android.sh' if old else 'release-mobile.sh')
        result = subprocess.run(['/bin/bash', str(script), *args], env=self.env,
                                cwd=self.temp.name, text=True, capture_output=True, timeout=20)
        self.assertEqual(result.returncode == 0, ok, result.stdout + result.stderr)
        self.assertNotIn('FAKE-PRIVATE-KEY-MUST-NOT-BE-PRINTED', result.stdout + result.stderr)
        return result

    def calls(self, tool=None):
        calls = [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []
        return [call for call in calls if tool is None or call['tool'] == tool]

    def test_both_build_before_upload_and_validate_once(self):
        result = self.run_script('--clean', '--build-name', '1.7.0', '--build-number', '70')
        calls = self.calls()
        builds = [i for i, call in enumerate(calls) if call['args'][:1] == ['build']]
        uploads = [i for i, call in enumerate(calls) if call['tool'] == 'fastlane']
        self.assertLess(max(builds), min(uploads))
        for args in [['clean'], ['pub', 'get'], ['analyze'], ['test']]:
            self.assertEqual(sum(call['args'] == args for call in self.calls('flutter')), 1)
        for i in builds:
            self.assertIn('--build-name=1.7.0', calls[i]['args'])
            self.assertIn('--build-number=70', calls[i]['args'])
        self.assertEqual([call['args'] for call in self.calls('fastlane')], [['upload_ios'], ['upload_android']])
        self.assertIn('no review submitted', result.stdout)
        self.assertIn('internal testing (completed)', result.stdout)

    def test_dry_run_does_not_run_tools_or_write_state(self):
        result = self.run_script('--dry-run')
        self.assertIn('Version: 1.7.0 (70)', result.stdout)
        self.assertEqual(self.calls(), [])
        self.assertFalse((self.repo / '.release-state').exists())

    def test_auto_number_persists_through_clean_failure_and_explicit_override(self):
        self.run_script('--platform', 'android', '--build-only', '--no-analyze', '--no-test')
        self.env['MOCK_BUILD_FAILURE'] = 'appbundle'
        self.run_script('--platform', 'android', '--build-only', '--clean', ok=False)
        del self.env['MOCK_BUILD_FAILURE']
        result = self.run_script('--platform', 'android', '--build-only')
        self.assertIn('(72)', result.stdout)
        self.run_script('--platform', 'android', '--build-only', '--build-number', '90')
        self.assertIn('(91)', self.run_script('--platform', 'android', '--build-only').stdout)
        self.assertEqual(self.pubspec.read_text(), 'name: test\nversion: 1.7.0+69\n')
        self.assertFalse((self.repo / '.release-state/lock').exists())

    def test_legacy_android_command_stays_build_only(self):
        self.run_script('--clean', '--build-name', '1.6.0', '--build-number', '41', old=True)
        self.assertFalse(self.calls('fastlane'))
        self.assertNotIn(['test'], [call['args'] for call in self.calls('flutter')])
        self.assertIn('--build-number=41', self.calls('flutter')[-1]['args'])
        self.run_script('--mode', 'debug', '--format', 'apk', old=True)
        self.assertIn('--build-number=69', self.calls('flutter')[-1]['args'])

    def test_missing_credentials_stops_before_build_and_number_reservation(self):
        del self.env['GOOGLE_PLAY_JSON_KEY']
        self.run_script(ok=False)
        self.assertFalse(self.calls('flutter'))
        self.assertFalse((self.repo / '.release-state').exists())

    def test_second_build_failure_does_not_upload_first_platform(self):
        self.env['MOCK_BUILD_FAILURE'] = 'appbundle'
        self.run_script(ok=False)
        self.assertFalse(self.calls('fastlane'))

    def test_stale_ipa_is_not_uploaded_even_when_flutter_exits_zero(self):
        ipa = self.mobile / 'build/ios/ipa/Checky.ipa'
        ipa.parent.mkdir(parents=True)
        ipa.write_bytes(b'old ipa')
        os.utime(ipa, (1, 1))
        self.env['MOCK_STALE'] = 'ipa'
        result = self.run_script('--platform', 'ios', ok=False)
        self.assertIn('stale build', result.stderr)
        self.assertFalse(self.calls('fastlane'))

    def test_partial_upload_reports_success_and_retry_does_not_rebuild(self):
        self.env['MOCK_UPLOAD_FAILURE'] = 'upload_android'
        result = self.run_script(ok=False)
        self.assertIn('iOS: uploaded to App Store Connect', result.stdout)
        self.assertIn('Android: upload not confirmed', result.stdout)
        self.assertIn('NOT rolled back', result.stderr)
        before = len(self.calls('flutter'))
        del self.env['MOCK_UPLOAD_FAILURE']
        aab = self.mobile / 'build/app/outputs/bundle/release/app-release.aab'
        self.run_script('--platform', 'android', '--upload-only', '--aab', str(aab))
        self.assertEqual(len(self.calls('flutter')), before)
        self.assertEqual(self.calls('fastlane')[-1]['args'], ['upload_android'])
        self.assertEqual(Path(self.calls('fastlane')[-1]['aab']).resolve(), aab.resolve())

    def test_build_only_needs_no_store_credentials(self):
        for key in ['ASC_KEY_ID', 'ASC_ISSUER_ID', 'ASC_KEY_FILE', 'GOOGLE_PLAY_JSON_KEY']:
            del self.env[key]
        self.run_script('--build-only')
        self.assertFalse(self.calls('fastlane'))

    def test_internal_draft_is_explicit(self):
        self.run_script('--platform', 'android', '--android-status', 'draft')
        self.assertEqual(self.calls('fastlane')[-1]['status'], 'draft')

    def test_ios_upload_only_does_not_build_or_allocate_a_number(self):
        ipa = Path(self.temp.name) / 'App with spaces.ipa'
        ipa.write_bytes(b'fake signed IPA')
        self.run_script('--platform', 'ios', '--upload-only', '--ipa', str(ipa))
        self.assertFalse(self.calls('flutter'))
        self.assertEqual([call['args'] for call in self.calls('fastlane')], [['upload_ios']])
        self.assertFalse((self.repo / '.release-state/build-number').exists())

    def test_stale_android_bundle_is_not_uploaded(self):
        aab = self.mobile / 'build/app/outputs/bundle/release/app-release.aab'
        aab.parent.mkdir(parents=True)
        aab.write_bytes(b'old bundle')
        os.utime(aab, (1, 1))
        self.env['MOCK_STALE'] = 'appbundle'
        self.run_script('--platform', 'android', ok=False)
        self.assertFalse(self.calls('fastlane'))

    def test_invalid_options_fail_without_side_effects(self):
        for args in [('--platform',), ('--platform', 'production'), ('--track', 'production'),
                     ('--android-status', 'production'), ('--build-number', '0'),
                     ('--build-number', '01'), ('--build-number', '2100000001'),
                     ('--build-only', '--upload-only'), ('--upload-only',),
                     ('--mode', 'debug'), ('--format', 'apk'), ('--build-name', 'wrong')]:
            with self.subTest(args=args):
                self.run_script(*args, ok=False)
        self.assertFalse(self.calls('flutter'))
        self.assertFalse(self.calls('fastlane'))

    def test_lock_prevents_parallel_release(self):
        (self.repo / '.release-state/lock').mkdir(parents=True)
        result = self.run_script('--build-only', ok=False)
        self.assertIn('Another release', result.stderr)
        self.assertTrue((self.repo / '.release-state/lock').exists())
        self.assertFalse(self.calls('flutter'))


class FastlaneSafetyTest(unittest.TestCase):
    def test_promotion_environment_is_rejected_before_any_upload(self):
        ruby = r'''
module UI
  def self.user_error!(message); raise message; end
end
class Recorder
  def opt_out_usage; end
  def skip_docs; end
  def lane(name, &block); @android = block if name == :upload_android; end
  def run; instance_eval(&@android); end
end
r = Recorder.new
r.instance_eval(File.read(ARGV[0]), ARGV[0])
r.run
'''
        for name in ['SUPPLY_TRACK_PROMOTE_TO', 'SUPPLY_UPDATE_ROLLOUT']:
            env = os.environ.copy()
            env.pop('SUPPLY_TRACK_PROMOTE_TO', None)
            env.pop('SUPPLY_UPDATE_ROLLOUT', None)
            env[name] = 'production'
            result = subprocess.run(['ruby', '-e', ruby, str(ROOT / 'scripts/fastlane/Fastfile')],
                                    env=env, text=True, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(f'Unset {name}', result.stderr)

    def test_lane_options_without_loading_fastlane_or_contacting_stores(self):
        # Execute the actual Fastfile against a tiny recording DSL, not fastlane.
        ruby = r'''
require 'json'
class Recorder
  attr_reader :lanes, :calls
  def initialize; @lanes = {}; @calls = []; end
  def opt_out_usage; end
  def skip_docs; end
  def lane(name, &block); @lanes[name] = block; end
  def app_store_connect_api_key(**args); @calls << ['key', args]; :fake_key; end
  def upload_to_testflight(**args); @calls << ['ios', args]; end
  def upload_to_play_store(**args); @calls << ['android', args]; end
end
r = Recorder.new
r.instance_eval(File.read(ARGV[0]), ARGV[0])
r.instance_eval(&r.lanes[:upload_ios])
r.instance_eval(&r.lanes[:upload_android])
puts JSON.generate(r.calls)
'''
        env = os.environ.copy()
        env.pop('SUPPLY_TRACK_PROMOTE_TO', None)
        env.pop('SUPPLY_UPDATE_ROLLOUT', None)
        env.update(ASC_KEY_ID='fake', ASC_ISSUER_ID='fake', ASC_KEY_FILE='/fake/key.p8',
                   CHECKY_IPA_PATH='/fake/app.ipa', CHECKY_AAB_PATH='/fake/app.aab',
                   GOOGLE_PLAY_JSON_KEY='/fake/key.json', CHECKY_ANDROID_STATUS='completed')
        result = subprocess.run(['ruby', '-e', ruby, str(ROOT / 'scripts/fastlane/Fastfile')],
                                env=env, text=True, capture_output=True, check=True)
        calls = dict(json.loads(result.stdout))
        self.assertTrue(calls['ios']['skip_submission'])
        self.assertTrue(calls['ios']['skip_waiting_for_build_processing'])
        self.assertFalse(calls['ios']['distribute_external'])
        self.assertEqual(calls['android']['track'], 'internal')
        self.assertEqual(calls['android']['release_status'], 'completed')
        self.assertFalse(calls['android']['rescue_changes_not_sent_for_review'])
        for role in ['metadata', 'changelogs', 'images', 'screenshots']:
            self.assertTrue(calls['android'][f'skip_upload_{role}'])


if __name__ == '__main__':
    unittest.main()
