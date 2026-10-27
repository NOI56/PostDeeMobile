# TikTok Native Connection: Proposed Design and Setup

Date: 2026-10-21

## Goal and current boundary

Let a customer tap Connect in PostDee, authorize through the installed TikTok
app using its signed-in account, and return to PostDee. Use an official browser
authorization flow when native authorization is unavailable. A customer still
grants permission, and TikTok can request additional identity verification.

For a future direct connection, start with TikTok and migrate one platform at a
time. Developer registration and sandbox setup must precede that system's
implementation. This document is a proposal only. No native social SDK, native
API/mobile contract, direct token exchange/storage, or direct publisher is
implemented. At the initial inspection, no developer credentials or registered
callback were found in the checked project configuration.

The active first experiment instead keeps managed PostPeer authorization and
publishing: Android Custom Tabs with external-browser fallback, plus automatic
backend status refresh after a pending attempt leaves and returns to the same
signed-in session. Manual refresh remains available. This does not add an
automatic browser-to-app redirect, native social SDK authorization, or a
guarantee of password-free login. See
[the managed mobile trial](2026-10-25-postpeer-mobile-connection-trial.md).

Existing PostPeer connections remain provider-owned. PostPeer's public API
currently exposes an OAuth URL flow, not a documented native SDK code/token
import. A future direct TikTok connection needs its own provider identity and
publisher routing; it must not be saved as a fake PostPeer integration ID.

## Proposed contract and mobile behavior

These shapes and behaviors are a draft for later implementation, not currently
available routes or response fields. Finalize them against the registered
developer app and SDK before changing the API.

- Consider extending `POST /social-connections/TIKTOK/connect` with
  `nativeAuthorization: { sessionId, state, clientKey, redirectUri, scopes }`
  while keeping an official browser `connectUrl` for fallback.
- Consider an authenticated
  `POST /social-connections/TIKTOK/native/complete` accepting `sessionId`,
  `state`, `authorizationCode`, and `codeVerifier`. This endpoint does not exist
  in the current runtime.
- Consider native authorization only for TikTok with server-provided metadata.
  Unavailable/unsupported native capability may open the official browser URL.
  User cancellation, denial, or native completion failure must not silently
  start browser authorization.
- The direct connection's browser fallback must check whether the URL actually
  opened and refresh server-side connection state on return, keeping manual
  refresh available. The managed PostPeer trial already adds this behavior
  through its existing refresh endpoint; that does not implement this draft
  direct connection contract. Opening an app/browser is not connection success.
- Capture the starting auth-session generation. Discard late results after
  sign-out/account change and do not submit them with a replacement user's
  credentials. Do not log codes, verifiers, states, or tokens.

## Registration, sandbox, implementation, and review

Creating the developer account/app is the setup step. Platform review of the
login and publishing use case is a separate, more detailed step; no review
duration or approval date is promised. Use permitted sandbox/development
accounts while preparing and testing before production approval.

1. **Register first.** Register PostDee in TikTok for Developers, add Login Kit and Content Posting
   API, and obtain the client key and server-only client secret. Configure
   permitted development/test users. The client key is public configuration;
   the client secret belongs only in the backend secret store.
2. **Configure the registered app.** Register Android identities separately: release
   `com.postdee.postdee_mobile` and debug/staging
   `com.postdee.postdee_mobile.staging`, with their actual signing certificates
   and package identities. Never substitute a guessed certificate or callback.
3. Choose a controlled HTTPS callback domain and register the exact redirect
   URI. Configure Android verified App Links and host the corresponding
   `assetlinks.json` for the correct package/certificates.
4. For iOS `com.postdee.postdeeMobile`, configure the registered universal link,
   Associated Domains, and the domain's Apple app-site-association file. Verify
   the SDK and return path on a physical iPhone using macOS/Xcode.
5. **Prepare sandbox access.** Use the available sandbox/development mode and
   approved test users to check permitted scopes, registered callbacks, and
   available platform capabilities before writing the integration.
6. **Implement and test.** Once the credentials, callback identities, and
   security requirements below are settled, add the official mobile SDKs,
   owner-bound backend token lifecycle, and direct publishing. Test with the
   isolated development accounts and capture the demonstration required for
   review.
7. **Request production review.** Request only necessary scopes:
   `user.info.basic` for identity and `video.publish` for Direct Post. Complete
   the applicable app/scope review and Direct Post audit before customer
   activation. Unreviewed public publishing is not enabled; a draft upload
   requiring the customer to finish in TikTok is not scheduled posting.

## Security plan required for activation

These are design and release requirements. None of the real token lifecycle
described here has been implemented by this proposal.

1. **Start an owner-bound attempt.** Authenticate the PostDee user, check the
   active-owner/deletion barrier, and create a cryptographically random,
   short-lived session/state. Store the owner, requested scopes, fixed
   registered redirect URI, expiry, one-time consumption status, and required
   PKCE binding. Do not accept a caller-selected redirect URL.
2. **Verify native completion.** Accept the SDK code only through the bound
   authenticated completion endpoint. Validate owner/session/state, expiry,
   PKCE, platform response, and actual granted scopes. Atomically consume the
   attempt and fence the final credential write against account deletion.
   Wrong-user, expired, canceled, or replayed attempts create no connection.
3. **Keep secrets on the server.** Exchange codes server-side with the client
   secret. Encrypt access/refresh tokens at rest using a separate managed key
   or equivalent secret-store policy with key rotation. Never put the client
   secret or refresh tokens in the app, source files, screenshots, logs, URLs,
   or ordinary connection responses. Retain only the minimum session data on
   mobile and clear it after completion/cancellation.
4. **Manage the complete lifecycle.** Support refresh-token rotation,
   concurrency-safe refresh, expiry/revocation/reconnect, provider-first
   disconnect, and account-deletion cleanup. Every operation must use the
   connection owned by the post's authenticated owner. Late callbacks and
   queued jobs must not recreate a deleted account or its credentials.
5. **Route publishing by the stored provider.** Preserve PostPeer accounts and
   explicitly distinguish direct TikTok accounts. Add direct publisher
   validation, required per-post choices/consent, outcome reconciliation, and
   safe retries. A successful login alone must not enable posting.

## Browser fallback and staged rollout

The current system continues using the existing PostPeer browser URL and
PostPeer publishing. Once direct TikTok is implemented, native and browser
authorization for that direct connection must use the same registered TikTok
developer app and validated session. Do not exchange a native code through
PostPeer or silently switch the account's publishing provider after a failed
attempt.

Start with isolated credentials and disposable accounts. Validate installed,
missing and signed-out TikTok app cases; browser fallback; cancellation/denial;
callback return; replay/expiry; auth-account switches; deletion races; and
network interruption. Verify secure credential storage/rotation and a full
controlled publish before enabling customer access. A default-closed release
gate must check all required configuration and verified capabilities.

## Remaining implementation

- Official Android/iOS native SDK adapters and verified return links.
- A real owner-bound authorization/session repository and token exchange.
- Encrypted direct-connection persistence, refresh/revoke/deletion cleanup.
- Provider-aware connection status, disconnect, and publisher routing.
- Direct TikTok publishing with current creator settings and per-post consent.
- Approved credentials/scopes and controlled physical-device end-to-end tests.

## Primary references

- [TikTok Android Login Kit](https://developers.tiktok.com/docs/en/login-kit-android-quickstart-v2)
- [TikTok iOS Login Kit](https://developers.tiktok.com/docs/en/login-kit-ios-quickstart)
- [User access token management](https://developers.tiktok.com/docs/en/oauth-user-access-token-management)
- [Direct Post setup](https://developers.tiktok.com/docs/en/content-posting-api-get-started)
- [Content sharing guidelines](https://developers.tiktok.com/docs/en/content-sharing-guidelines)
- [PostPeer connection flow](https://www.postpeer.dev/docs/social-accounts/connect)
