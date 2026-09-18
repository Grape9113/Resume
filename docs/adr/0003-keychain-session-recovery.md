---
status: accepted
---
# Retain the password in Keychain to rebuild expired sessions

For the single PikaPods Connection, Resume retains the Audiobookshelf password in Keychain as well as the rotating token pair so a definitively invalid refresh session can be rebuilt once without making the listener recreate the Connection. This accepts retaining a reusable secret in the OS credential store in exchange for low-friction recovery; transport outages do not trigger password-login churn, and rejected saved credentials require inline recovery.

Reconstructed from [the original specification](https://github.com/Grape9113/Resume/issues/1) and existing authentication implementation/tests. OIDC and permanent API-token authentication remain outside scope. The client recovery mechanism and its UI error routing have different verification coverage; see the baseline register.
