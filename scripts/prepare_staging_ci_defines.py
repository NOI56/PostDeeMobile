"""Prepare guarded Staging Dart defines in RUNNER_TEMP without logging values."""

import argparse
import json
import os
from pathlib import Path
import re
import sys


KEY_ENV = "POSTDEE_REVENUECAT_TEST_STORE_ANDROID_API_KEY"
OUTPUT_NAME = "postdee-staging-defines.json"
ALLOWED_BASE_FIELDS = frozenset({
    "API_BASE_URL", "POSTDEE_STAGING_BUILD", "ENABLE_FIREBASE_AUTH",
    "ALLOW_LOCAL_MOCK_AUTH", "GOOGLE_SERVER_CLIENT_ID", "ENABLE_REVENUECAT_BILLING",
    "ENABLE_EXPERIMENTAL_BEAT_SYNC", "ENABLE_EXPERIMENTAL_AI_HOOK",
    "STORE_STARTER_MONTHLY_PRODUCT_ID", "STORE_PRO_MONTHLY_PRODUCT_ID",
})


class ConfigError(ValueError):
    """Fixed messages must never interpolate configuration or secret values."""


def validate_build_number(value):
    if value == "":
        return value
    if (not isinstance(value, str) or not re.fullmatch(r"[1-9][0-9]{0,9}", value)
            or int(value) > 2100000000):
        raise ConfigError("Build number must be empty or an integer from 1 to 2100000000.")
    return value


def prepare_defines(config, *, test_store_billing=False, sdk_key=None):
    if not isinstance(config, dict) or type(test_store_billing) is not bool:
        raise ConfigError("Expected a base object and a boolean billing mode.")
    if set(config) - ALLOWED_BASE_FIELDS:
        raise ConfigError("Base Staging configuration contains unsupported fields.")
    if config.get("API_BASE_URL") != "https://postdee-api-staging.onrender.com":
        raise ConfigError("The base API must be the PostDee Staging endpoint.")
    required_booleans = {
        "POSTDEE_STAGING_BUILD": True,
        "ENABLE_FIREBASE_AUTH": True,
        "ALLOW_LOCAL_MOCK_AUTH": False,
        "ENABLE_REVENUECAT_BILLING": False,
    }
    if any(config.get(field) is not expected
           for field, expected in required_booleans.items()):
        raise ConfigError("Staging, Firebase, mock-auth or base-billing guards failed.")
    client_id = config.get("GOOGLE_SERVER_CLIENT_ID")
    if (not isinstance(client_id, str)
            or not client_id.endswith(".apps.googleusercontent.com")
            or client_id == ".apps.googleusercontent.com"):
        raise ConfigError("The base Google Web OAuth client must be present.")
    for field in ("ENABLE_EXPERIMENTAL_BEAT_SYNC", "ENABLE_EXPERIMENTAL_AI_HOOK"):
        if field in config and type(config[field]) is not bool:
            raise ConfigError("Experimental feature settings must be boolean.")
    for field in ("STORE_STARTER_MONTHLY_PRODUCT_ID", "STORE_PRO_MONTHLY_PRODUCT_ID"):
        if field in config and (not isinstance(config[field], str) or not config[field]):
            raise ConfigError("Store product identifiers must be nonempty strings.")

    result = dict(config)
    if test_store_billing:
        key = sdk_key.strip() if isinstance(sdk_key, str) else ""
        if not re.fullmatch(r"test_[A-Za-z0-9_-]{1,507}", key):
            raise ConfigError("Test Store billing requires a public test_ SDK key.")
        result["ENABLE_REVENUECAT_BILLING"] = True
        result["REVENUECAT_ANDROID_API_KEY"] = key
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", type=Path, required=True)
    parser.add_argument("--test-store-billing", choices=("false", "true"), default="false")
    args = parser.parse_args(argv)
    enabled = args.test_store_billing == "true"
    try:
        validate_build_number(os.environ.get("POSTDEE_STAGING_BUILD_NUMBER", ""))
        runner_temp = os.environ.get("RUNNER_TEMP")
        if not runner_temp or not Path(runner_temp).is_absolute():
            raise ConfigError("An absolute RUNNER_TEMP directory is required.")
        output_dir = Path(runner_temp).resolve(strict=True)
        if not output_dir.is_dir():
            raise ConfigError("RUNNER_TEMP must be an existing directory.")
        config = json.loads(args.base.read_text(encoding="utf-8"))
        merged = prepare_defines(
            config, test_store_billing=enabled,
            sdk_key=os.environ.get(KEY_ENV) if enabled else None,
        )
        # Validate everything first; never replace an existing configuration.
        descriptor = os.open(output_dir / OUTPUT_NAME, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as output:
            json.dump(merged, output, indent=2, sort_keys=True)
            output.write("\n")
    except ConfigError as error:
        print(f"Staging CI defines validation failed: {error}", file=sys.stderr)
        return 1
    except (OSError, ValueError):
        print("Could not read or write Staging CI configuration.", file=sys.stderr)
        return 1
    print("Prepared validated Staging CI defines (Test Store billing "
          + ("enabled" if enabled else "disabled") + ").")
    return 0


if __name__ == "__main__":
    sys.exit(main())
