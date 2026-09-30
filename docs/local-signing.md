# Signing your personal build

LookFocus needs a stable app identity because Camera and Accessibility approvals are associated with the signed app. An ad hoc rebuild can invalidate prior approvals. Use the same certificate and installation path for subsequent builds.

Supply your own code-signing identity from your login Keychain through `LOOKFOCUS_SIGNING_IDENTITY`. This may be a suitable local self-signed code-signing identity for personal use, or an Apple-issued identity you already have. A local self-signed build is not a notarized public distribution.

If you need a local identity, Keychain Access has Certificate Assistant → Create a Certificate. Create a self-signed certificate with certificate type **Code Signing**, stored in your login Keychain. Use its name as the build variable. Keep the private key in your Keychain; never add it to this repository or send it to another person. You do not need to make it a system root certificate or disable system security protections.

```sh
LOOKFOCUS_SIGNING_IDENTITY="Your Code Signing Identity" bash scripts/build-app.sh
```

Grant Camera and Accessibility permissions yourself after launching your installed build. A change of certificate, bundle identity, or installation path may require fresh approvals. No original author's certificate or private key is needed.
