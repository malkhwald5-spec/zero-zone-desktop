# Android signing key

`zerozone.keystore` signs the Android test builds made by
`.github/workflows/build-android.yml` (alias `zerozone`, password `zerozone`).
It is public on purpose: it only lets phones install updates over an earlier
test build. A store release (Google Play) needs a new, private key kept in the
repository's secrets instead.
