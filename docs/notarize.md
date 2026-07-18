# Notarizing Format

To publish `Format.app` on GitHub in a form macOS opens without the right-click → Open dance, it needs a **Developer ID** signature and an Apple-issued notarization ticket. One-time setup, then `./scripts/release.sh` produces a notarized `.zip` on every run.

## Prerequisites

- Apple Developer Program membership ($99 / year)
- macOS + Xcode

## 1. Get the Developer ID Application certificate

This is a **different** certificate from the "Apple Distribution" one used for the App Store — you probably don't have it yet even if you ship other apps.

In Xcode:

1. **Settings** (⌘,) → **Accounts** → click your Apple ID → **Manage Certificates…**
2. Click the **`+`** in the bottom-left → **Developer ID Application**
3. Xcode generates and downloads the cert into your login Keychain.

Verify from a terminal:

```bash
security find-identity -v -p codesigning
# Should list: "Developer ID Application: YOUR NAME (TEAMID)"
```

Note the `TEAMID` in parentheses — you'll need it in step 3.

## 2. Create an app-specific password

Apple's notary tool authenticates as your Apple ID. Rather than juggle your real password + 2FA, use an app-specific password:

1. https://account.apple.com/account/manage → **Sign-In and Security** → **App-Specific Passwords**
2. Generate one, name it e.g. `Format notary`
3. Copy it (looks like `abcd-efgh-ijkl-mnop`) — you can't view it again after leaving the page.

## 3. Store the credential in Keychain

```bash
xcrun notarytool store-credentials formatc-notary \
  --apple-id you@example.com \
  --team-id ABCD1234 \
  --password abcd-efgh-ijkl-mnop
```

- `formatc-notary` is the profile name — `release.sh` reads it via `$NOTARY_PROFILE` (override if you name it something else).
- `--team-id` is the string in parens from step 1.
- `--password` is the app-specific password from step 2.

The credential is stored in your login Keychain; the password is never on disk in plaintext.

## 4. Cut a notarized release

```bash
./scripts/release.sh
```

The script signs with the Developer ID cert, submits the zip to Apple's notary service, waits for the ticket (usually 30–120s), staples it into `Format.app`, and re-zips. The result at `dist/Format.zip` is what you upload to GitHub Releases.

If step 1 was skipped, the script falls back to ad-hoc signing and skips notarization automatically — the build still works locally, but downloaders will see the Gatekeeper dialog and need the right-click → Open workaround.

## Troubleshooting

**"Failed to authenticate for authentication mode Keychain profile":**
The profile name doesn't exist. Re-run step 3.

**Notarization takes too long:**
Rare, but Apple's queue can lag. Check status:
```bash
xcrun notarytool history --keychain-profile formatc-notary
xcrun notarytool log <submission-id> --keychain-profile formatc-notary
```

**"The signature of the binary is invalid":**
Usually means a nested executable wasn't signed with hardened runtime. `codesign --verify --deep --strict --verbose=2 Format.app` will point at the offender.
