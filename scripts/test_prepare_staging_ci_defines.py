import copy
from contextlib import redirect_stdout
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


SCRIPT = Path(__file__).with_name("prepare_staging_ci_defines.py")
SPEC = importlib.util.spec_from_file_location("staging_ci_defines", SCRIPT)
HELPER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(HELPER)
KEY_ENV = "POSTDEE_REVENUECAT_TEST_STORE_ANDROID_API_KEY"
SYNTHETIC_KEY = "test_synthetic_unit_test_key_only"
BASE = {
    "API_BASE_URL": "https://postdee-api-staging.onrender.com",
    "POSTDEE_STAGING_BUILD": True,
    "ENABLE_FIREBASE_AUTH": True,
    "ALLOW_LOCAL_MOCK_AUTH": False,
    "GOOGLE_SERVER_CLIENT_ID": "synthetic.apps.googleusercontent.com",
    "ENABLE_REVENUECAT_BILLING": False,
    "ENABLE_EXPERIMENTAL_BEAT_SYNC": False,
    "ENABLE_EXPERIMENTAL_AI_HOOK": False,
    "STORE_STARTER_MONTHLY_PRODUCT_ID": "postdee_starter_monthly",
    "STORE_PRO_MONTHLY_PRODUCT_ID": "postdee_pro_monthly",
}


class PrepareStagingDefinesTests(unittest.TestCase):
    def test_default_preserves_disabled_base_without_embedding_a_supplied_key(self):
        original = copy.deepcopy(BASE)
        result = HELPER.prepare_defines(BASE, sdk_key=SYNTHETIC_KEY)
        self.assertEqual(result, BASE)
        self.assertEqual(BASE, original)
        self.assertNotIn(SYNTHETIC_KEY, json.dumps(result))

    def test_opt_in_changes_only_billing_and_android_public_sdk_key(self):
        original = copy.deepcopy(BASE)
        result = HELPER.prepare_defines(
            BASE, test_store_billing=True, sdk_key=SYNTHETIC_KEY
        )
        expected = {**BASE, "ENABLE_REVENUECAT_BILLING": True,
                    "REVENUECAT_ANDROID_API_KEY": SYNTHETIC_KEY}
        self.assertEqual(result, expected)
        self.assertEqual(BASE, original)
        self.assertNotIn("REVENUECAT_API_KEY", result)

    def test_opt_in_requires_a_nonempty_test_store_public_key(self):
        for key in (None, "", " ", "test_", "goog_live_key", "appl_live_key",
                    "sk_private_key", "test_line\nbreak", "test_" + "x" * 508):
            with self.subTest(key_type=type(key).__name__):
                with self.assertRaises(HELPER.ConfigError) as failure:
                    HELPER.prepare_defines(BASE, test_store_billing=True, sdk_key=key)
                if key and len(key.strip()) > 5:
                    self.assertNotIn(key, str(failure.exception))

    def test_production_mock_or_wrongly_typed_identity_is_rejected(self):
        cases = [
            ("API_BASE_URL", "https://postdee-api.onrender.com"),
            ("POSTDEE_STAGING_BUILD", False),
            ("POSTDEE_STAGING_BUILD", "true"),
            ("POSTDEE_STAGING_BUILD", 1),
            ("ENABLE_FIREBASE_AUTH", False),
            ("ENABLE_FIREBASE_AUTH", "true"),
            ("ALLOW_LOCAL_MOCK_AUTH", True),
            ("ALLOW_LOCAL_MOCK_AUTH", 0),
            ("ENABLE_REVENUECAT_BILLING", True),
            ("ENABLE_REVENUECAT_BILLING", "false"),
            ("GOOGLE_SERVER_CLIENT_ID", ""),
            ("GOOGLE_SERVER_CLIENT_ID", "wrong-client"),
        ]
        for field, value in cases:
            with self.subTest(field=field, value_type=type(value).__name__):
                with self.assertRaises(HELPER.ConfigError):
                    HELPER.prepare_defines({**BASE, field: value})

    def test_missing_required_identity_is_rejected(self):
        for field in ("API_BASE_URL", "POSTDEE_STAGING_BUILD", "ENABLE_FIREBASE_AUTH",
                      "ALLOW_LOCAL_MOCK_AUTH", "GOOGLE_SERVER_CLIENT_ID",
                      "ENABLE_REVENUECAT_BILLING"):
            with self.subTest(field=field):
                config = {name: value for name, value in BASE.items() if name != field}
                with self.assertRaises(HELPER.ConfigError):
                    HELPER.prepare_defines(config)

    def test_server_secrets_and_base_sdk_keys_are_rejected_without_echoing_them(self):
        for field in ("GEMINI_API_KEY", "DATABASE_URL", "REVENUECAT_REST_API_V1_KEY",
                      "REVENUECAT_WEBHOOK_AUTH_TOKEN", "GOOGLE_PLAY_SERVICE_ACCOUNT_KEY_JSON",
                      "REVENUECAT_ANDROID_API_KEY", "REVENUECAT_API_KEY",
                      "untrusted_name_" + SYNTHETIC_KEY):
            with self.subTest(field_type="unsupported"):
                with self.assertRaises(HELPER.ConfigError) as failure:
                    HELPER.prepare_defines({**BASE, field: SYNTHETIC_KEY})
                self.assertNotIn(SYNTHETIC_KEY, str(failure.exception))

    def test_only_an_object_and_boolean_mode_are_accepted(self):
        for config in (None, [], "untrusted_config"):
            with self.assertRaises(HELPER.ConfigError):
                HELPER.prepare_defines(config)
        with self.assertRaises(HELPER.ConfigError):
            HELPER.prepare_defines(BASE, test_store_billing="true")

    def test_build_number_accepts_only_empty_or_bounded_canonical_positive_integer(self):
        for number in ("", "1", "12026", "2100000000"):
            self.assertEqual(HELPER.validate_build_number(number), number)
        for number in ("0", "-1", "+1", "01", "2100000001", "1.0", "1e3",
                       " 12026", "12026\n", "$(echo unsafe)", "１２", None, 12026):
            with self.subTest(value_type=type(number).__name__):
                with self.assertRaises(HELPER.ConfigError):
                    HELPER.validate_build_number(number)

    def run_cli(self, base, *, enabled=False, key=None, raw_json=False, build_number=""):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        base_path = root / "base.json"
        base_path.write_text(base if raw_json else json.dumps(base), encoding="utf-8")
        environment = os.environ.copy()
        environment.pop(KEY_ENV, None)
        if key is not None:
            environment[KEY_ENV] = key
        environment["RUNNER_TEMP"] = str(root)
        environment["POSTDEE_STAGING_BUILD_NUMBER"] = build_number
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "--base", str(base_path),
             "--test-store-billing", str(enabled).lower()],
            env=environment, capture_output=True, text=True, check=False,
        )
        return result, root / "postdee-staging-defines.json"

    def test_cli_default_writes_only_safe_base_to_runner_temp(self):
        result, output = self.run_cli(BASE, key=SYNTHETIC_KEY)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(output.read_text(encoding="utf-8")), BASE)
        self.assertNotIn(SYNTHETIC_KEY, result.stdout + result.stderr)

    def test_cli_enabled_writes_overlay_without_logging_key_or_config(self):
        result, output = self.run_cli(BASE, enabled=True, key=SYNTHETIC_KEY)
        self.assertEqual(result.returncode, 0, result.stderr)
        config = json.loads(output.read_text(encoding="utf-8"))
        self.assertTrue(config["ENABLE_REVENUECAT_BILLING"])
        self.assertEqual(config["REVENUECAT_ANDROID_API_KEY"], SYNTHETIC_KEY)
        self.assertNotIn(SYNTHETIC_KEY, result.stdout + result.stderr)
        self.assertNotIn(BASE["GOOGLE_SERVER_CLIENT_ID"], result.stdout + result.stderr)
        if os.name != "nt":
            self.assertEqual(output.stat().st_mode & 0o777, 0o600)

    def test_cli_fails_closed_if_test_store_key_is_missing(self):
        result, output = self.run_cli(BASE, enabled=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(output.exists())

    def test_cli_rejects_server_configuration_without_leaking_it(self):
        result, output = self.run_cli({**BASE, "DATABASE_URL": SYNTHETIC_KEY})
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(output.exists())
        self.assertNotIn(SYNTHETIC_KEY, result.stdout + result.stderr)

    def test_cli_malformed_json_does_not_echo_input(self):
        result, output = self.run_cli("{\"" + SYNTHETIC_KEY, raw_json=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(output.exists())
        self.assertNotIn(SYNTHETIC_KEY, result.stdout + result.stderr)

    def test_cli_invalid_build_number_fails_before_writing_config(self):
        result, output = self.run_cli(BASE, build_number="0")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(output.exists())


class WorkflowReceiptTests(unittest.TestCase):
    def run_receipt(self, *, package="com.postdee.postdee_mobile.staging", version="12026"):
        workflow = SCRIPT.parents[1] / ".github" / "workflows" / "ci.yml"
        lines = workflow.read_text(encoding="utf-8").splitlines()
        start = next(index for index, line in enumerate(lines)
                     if line.strip() == "python3 - <<'PY'") + 1
        end = next(index for index in range(start, len(lines)) if lines[index].strip() == "PY")
        receipt_code = "\n".join(line[10:] for line in lines[start:end])

        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        artifact = root / "build" / "staging-apk"
        artifact.mkdir(parents=True)
        (artifact / "app-debug.apk").write_bytes(b"synthetic APK bytes")
        (artifact / "flutter-version.json").write_text(json.dumps({
            "frameworkVersion": "test-framework", "dartSdkVersion": "test-sdk",
        }), encoding="utf-8")
        runner_temp = root / "runner-temp"
        runner_temp.mkdir()
        defines_bytes = json.dumps({**BASE, "REVENUECAT_ANDROID_API_KEY": SYNTHETIC_KEY}).encode()
        (runner_temp / "postdee-staging-defines.json").write_bytes(defines_bytes)
        aapt = root / "android" / "build-tools" / "35.0.0" / "aapt"
        aapt.parent.mkdir(parents=True)
        aapt.touch()
        environment = {
            "ANDROID_HOME": str(root / "android"), "RUNNER_TEMP": str(runner_temp),
            "GITHUB_SHA": "b" * 40, "GITHUB_RUN_ID": "123456",
            "POSTDEE_STAGING_BUILD_NUMBER": "12026",
            "POSTDEE_STAGING_TEST_STORE_BILLING": "true",
        }

        def command_output(arguments, **unused):
            if arguments == ["git", "rev-parse", "HEAD"]:
                return "a" * 40 + "\n"
            self.assertEqual(arguments, [str(aapt), "dump", "badging",
                                         str(Path("build") / "staging-apk" / "app-debug.apk")])
            return f"package: name='{package}' versionCode='{version}' versionName='fixture'\n"

        previous_directory = Path.cwd()
        stdout = io.StringIO()
        try:
            os.chdir(root)
            with mock.patch.dict(os.environ, environment), \
                    mock.patch("subprocess.check_output", side_effect=command_output), \
                    redirect_stdout(stdout):
                exec(compile(receipt_code, str(workflow), "exec"), {})
        finally:
            os.chdir(previous_directory)
        return json.loads((artifact / "receipt.json").read_text()), stdout.getvalue(), defines_bytes

    def test_receipt_records_actual_identity_hashes_and_flags_without_key(self):
        receipt, output, defines_bytes = self.run_receipt()
        self.assertEqual(receipt["sourceSha"], "a" * 40)
        self.assertEqual(receipt["workflowSha"], "b" * 40)
        self.assertEqual(receipt["applicationId"], "com.postdee.postdee_mobile.staging")
        self.assertEqual(receipt["buildNumber"], 12026)
        self.assertEqual(receipt["requestedBuildNumber"], 12026)
        self.assertTrue(receipt["stagingTestStoreBilling"])
        self.assertIn("--build-number=12026", receipt["buildFlags"])
        self.assertEqual(receipt["dartDefineFileSha256"], hashlib.sha256(defines_bytes).hexdigest())
        self.assertEqual(receipt["sha256"], hashlib.sha256(b"synthetic APK bytes").hexdigest())
        self.assertNotIn(SYNTHETIC_KEY, output + json.dumps(receipt))

    def test_receipt_rejects_a_wrong_package(self):
        with self.assertRaisesRegex(RuntimeError, "required Staging identity"):
            self.run_receipt(package="com.postdee.postdee_mobile")

    def test_receipt_rejects_a_wrong_apk_version(self):
        with self.assertRaisesRegex(RuntimeError, "version code differs"):
            self.run_receipt(version="1")


if __name__ == "__main__":
    unittest.main()
