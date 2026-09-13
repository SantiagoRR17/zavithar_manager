# Deployment Plan

## Environments
- **Dev:** local Flutter run + Firebase Emulator Suite (Firestore, Auth, Functions) for fast iteration without touching real data.
- **Prod:** a real Firebase project (Spark/free plan initially), single environment since this is a single-user app — no separate staging needed at this scale, though one can be added later by creating a second Firebase project if desired.

## Android deployment
- Build a release APK (`flutter build apk --release`) signed with a personal keystore.
- Since this is a single-user app, no Play Store listing is required — install the APK directly on your phone (sideload), or optionally use Firebase App Distribution for easier install/update pushes.
- Keep the keystore file backed up somewhere safe (losing it means future updates can't be installed over the old app without uninstalling first).

## Windows desktop deployment
- Build a release executable (`flutter build windows --release`).
- Run directly from the build output folder, or package as an installer later (e.g. with Inno Setup) if double-click installation is wanted — not required for personal use.

## Firebase deployment
- Deploy Firestore security rules: `firebase deploy --only firestore:rules`.
- Deploy Cloud Functions (notification scheduler): `firebase deploy --only functions`.
- Configure Firestore composite indexes as prompted during development, then `firebase deploy --only firestore:indexes` to make them reproducible.

## Release process (each milestone)
1. Finish and manually test the milestone per `testing-plan.md`.
2. Bump app version (`pubspec.yaml`).
3. Build release Android APK and Windows executable.
4. Deploy any changed Firestore rules/indexes/functions.
5. Install/replace the build on both devices.
6. Verify the real-time sync + notification checks one more time post-deploy.

## Cost monitoring
- Check Firebase usage dashboard periodically (Firestore reads/writes, Functions invocations) to confirm usage stays within the free Spark plan tier for single-user volume.
- Set a billing alert if upgrading to the Blaze (pay-as-you-go) plan is ever needed (e.g. to enable scheduled Cloud Functions, which require Blaze even at $0 usage in some configurations — confirm this requirement when Milestone 3 is reached).
