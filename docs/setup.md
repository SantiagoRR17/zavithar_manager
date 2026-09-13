# Setup — from a bare Windows machine to a running app

Everything needed to build and run Zavithar Manager. Written from the actual install on 2026-08-22/23, not from memory — the version numbers below are what is really in use.

> **Package manager note:** this project uses **pnpm** and never npm. See [ADR 0007](adr/0007-pnpm-only.md). Every Node command below is a `pnpm` command; translate accordingly if you are following Firebase's own docs, which are written with npm.

---

## What is installed

| Tool | Version in use | Why |
|---|---|---|
| Flutter (stable) | 3.47.1 (Dart 3.13.1) | the client framework |
| Android SDK platform | android-36 | Flutter 3.47 requires it |
| Android build-tools | 36.0.0 | |
| Android platform-tools | 37.0.1 | `adb` |
| Node.js | 22.12.0 | runs the Firebase CLI |
| pnpm | 10.33.4 | the only Node package manager used here |
| firebase-tools | 15.28.1 | Firebase CLI |
| flutterfire_cli | 1.4.1 | generates `firebase_options.dart` |
| Visual Studio Build Tools 2022 | 17.14 (**incomplete**) | Windows desktop builds — not finished yet |

---

## 1. Flutter

Download the stable Windows zip from <https://docs.flutter.dev/get-started/install/windows> and extract it. On this machine:

```
%USERPROFILE%\develop\flutter\
```

Do **not** extract into a path that needs elevated permissions (anything under `C:\Program Files\`) — Flutter writes to its own directory constantly.

Verify the download before extracting, especially over a flaky connection — it is ~1.8 GB:

```bash
unzip -t flutter_windows_3.47.1-stable.zip
```

### PATH and environment

Add to the **user** PATH (System Properties → Environment Variables):

```
%USERPROFILE%\develop\flutter\bin
%LOCALAPPDATA%\Pub\Cache\bin          # for globally activated Dart tools
```

Set:

```
ANDROID_HOME = %LOCALAPPDATA%\Android\Sdk
```

> A shell opened *before* the PATH change will not see it. Open a **new** terminal and confirm `flutter --version` works with no path prefix before believing anything is wrong.

---

## 2. Android SDK

The SDK itself comes with Android Studio, or from the command-line tools alone. Flutter 3.47.1 needs **SDK 36**; an existing android-34 install is not enough.

```bash
cd "$ANDROID_HOME/cmdline-tools/latest/bin"
./sdkmanager.bat --install "platforms;android-36" "build-tools;36.0.0" "platform-tools"
```

Then accept the licences. This is interactive by design, so pipe answers in:

```bash
yes | flutter doctor --android-licenses
```

> **Gotcha.** Piping `y` from PowerShell did not work — the child process saw EOF and stopped at the first prompt. Running it through Git Bash with `yes |` worked. If licences will not accept, try the other shell before anything else.

> **Second gotcha.** `sdkmanager` prints `Warning: This version only understands SDK XML versions up to 3 but an SDK XML file of version 4 was encountered`. Harmless. Trying to fix it with `sdkmanager --install "cmdline-tools;latest"` fails partway, because sdkmanager cannot overwrite the jars it is currently running from. Ignore it, or update cmdline-tools through Android Studio's SDK Manager.

Check:

```bash
flutter doctor
```

`[√] Android toolchain` is what you are after.

### Windows desktop (not done yet)

`flutter doctor` will also flag Visual Studio as incomplete. Windows builds need the **"Desktop development with C++"** workload, added through the Visual Studio Installer GUI — several GB, and not scriptable. Deferred; see [ADR 0005](adr/0005-android-first.md).

Windows builds with plugins also need **Developer Mode** on, for symlink support:

```
start ms-settings:developers
```

---

## 3. A device

**Physical phone** (what this project uses):

1. Settings → About phone → tap **Build number** seven times to unlock Developer options.
2. Settings → System → Developer options → enable **USB debugging**.
3. Plug it in and accept the *"Allow USB debugging?"* prompt on the phone.

```bash
adb devices     # want "device", not "unauthorized"
flutter devices
```

`unauthorized` means the on-phone prompt was not accepted — unplug, replug, and watch the screen.

**Emulator**, if no phone is available: create an AVD with `avdmanager`, or through Android Studio's Device Manager. Slower, and it is not the real target.

---

## 4. Node tooling

```bash
pnpm add -g firebase-tools
firebase --version
```

Then the FlutterFire CLI (a Dart tool, so pub not pnpm):

```bash
dart pub global activate flutterfire_cli
```

`flutterfire` must be on PATH — that is what `%LOCALAPPDATA%\Pub\Cache\bin` in step 1 is for.

---

## 5. Firebase project

Several steps here need a browser and a human; they cannot be scripted.

```bash
firebase login                       # opens a browser — use the project's account
```

> Being signed into the Firebase **console** in a browser is *not* the same as being signed into the **CLI**. The CLI keeps its own credential on the machine, and the login has to be started from the terminal — which then opens the browser. `firebase login:list` tells you which one you actually have.

```bash
firebase projects:create zavithar-manager --display-name "Zavithar Manager"
```

> **`Error: Failed to create project`** with `Callers must accept Terms of Service` in `firebase-debug.log` means the Google Cloud ToS has never been accepted on this account. It is a one-time browser step — accepting it while creating a project through the Firebase console clears it, after which the CLI works too. The CLI's own error message does not mention the ToS at all, so read the debug log rather than guessing.

Then, in the [Firebase console](https://console.firebase.google.com/):

1. **Firestore Database** → Create database.
   - **Standard edition**, not Enterprise. Enterprise is Firestore with MongoDB compatibility, aimed at server-side apps using MongoDB drivers; it is not what the client SDKs, real-time `snapshots()` listeners and Security Rules in this project are built on.
   - **Production mode** — the rules in this repo are deployed over it in step 6.
   - Region: **cannot be changed later.** This project uses `us-east1`.
2. **Authentication** → Get started → Sign-in method → enable **Google** and **Email/Password**. There is no CLI command for this.
   - Enabling Google asks for a **project support email**. That address is *public* — it appears on Google's consent screen. The dropdown only offers accounts that are Owners of the project, plus Google Groups you manage, so to use something other than a personal address, create a Google Group first and pick that. It can be changed later under Project settings → General.

Wire the app to the project:

```bash
cd app
flutterfire configure --project=zavithar-manager --platforms=android,windows
```

This writes `app/lib/firebase_options.dart` and `app/android/app/google-services.json`. Both are **committed on purpose** — [ADR 0008](adr/0008-committing-firebase-config.md) explains why the "API key" in them is not a secret.

### SHA-1 for Google sign-in

Google sign-in on Android only works for an APK signed by a registered certificate, including your local debug keystore:

```bash
cd app/android
./gradlew signingReport
```

Copy the **SHA1** under `Variant: debug` into Firebase console → Project settings → Your apps → the Android app → **Add fingerprint**, then re-download `google-services.json` into `app/android/app/`.

> Skip this and Google sign-in fails as **"cancelled"**, exactly as if you had dismissed the account picker. It is the most confusing failure in the whole setup — check the fingerprint first.

---

## 6. Deploy the security rules

From the repository root:

```bash
firebase use zavithar-manager
firebase deploy --only firestore:rules
```

`firestore.rules` is the real access-control layer for this app. Read [lesson 04](learning/04-firebase-auth-and-firestore-rules.md) before changing it.

---

## 7. Run

```bash
cd app
flutter pub get
flutter devices                # find your device id
flutter run -d <device-id>
```

While it runs: `r` hot reload · `R` hot restart · `q` quit.

Add a plugin or change native config → full stop and re-run; hot restart is not enough.

---

## Troubleshooting

| Symptom | Cause |
|---|---|
| `flutter` not found in a new terminal | PATH edit not picked up — open a *new* terminal, or check it went into the **user** PATH |
| `flutterfire: command not found` in Git Bash | it is installed as `flutterfire.bat`; Git Bash will not resolve a bare name to a `.bat`. Run it from PowerShell, or call `flutterfire.bat` explicitly |
| `Failed to create project` from the CLI | Google Cloud Terms of Service never accepted on the account — see step 5. The real reason is only in `firebase-debug.log` |
| `adb devices` shows `unauthorized` | the on-phone "Allow USB debugging?" prompt was not accepted |
| Google sign-in does nothing, reports "cancelled" | debug SHA-1 not registered in Firebase, or `google-services.json` is stale |
| `serverClientId must be provided on Android` | `google-services.json` has no web OAuth client (`client_type: 3`) — enable Google sign-in in the console, then re-download |
| `PERMISSION_DENIED` on any Firestore read | rules not deployed, or the path is not under `users/{your-uid}/` |
| `Building with plugins requires symlink support` | enable Developer Mode (`start ms-settings:developers`) — only affects Windows builds |
| Licences will not accept from PowerShell | use Git Bash: `yes \| flutter doctor --android-licenses` |
