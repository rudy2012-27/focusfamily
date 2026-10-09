# FocusFamily - setup guide (Android first)

You need: a computer with **Flutter** and **Android Studio** installed (run `flutter doctor` until it is happy), and an Android phone with USB debugging on.

## 1. Create the Flutter project and copy these files in
```
flutter create --org com.focusfamily --project-name focus_family --platforms=android,ios focus_family
```
Unzip this package so its files **overwrite** the ones inside the new `focus_family` folder (pubspec.yaml, lib/, android/, test/).
Then, from inside `focus_family`:
```
python3 apply_patches.py
flutter pub get
```
(`apply_patches.py` edits the two Gradle files. If it prints a "!!" line, do that step by hand.)

## 2. Create the Firebase project (free plan is fine)
1. Go to https://console.firebase.google.com and create a project.
2. **Add an Android app** with package name exactly: `com.focusfamily.focus_family`
3. Get your debug SHA-1 key and add it to that Android app in Firebase (Project settings > Your apps > Add fingerprint):
   ```
   cd android
   ./gradlew signingReport      (Windows: gradlew.bat signingReport)
   ```
   Copy the `SHA1` under `Variant: debug`.
4. Download **google-services.json** and put it in `android/app/`.
5. Build > Authentication > Get started > turn on **Google** sign-in.
6. Build > Firestore Database > Create database (production mode).
7. Firestore > Rules tab > paste everything from `firestore.rules` > Publish.

## 3. Run it
```
flutter run
```
Test with two phones: one is the parent, one is the child.
1. Phone A: Login with Google > Parent > accept terms > **Add child** > type the child's Google email.
2. Phone B (Android): Login with that email > Child > accept terms. It links automatically.
3. Phone B: tap Allow on all four permission rows (Usage access, Accessibility, VPN, Battery).
   If the Accessibility switch is greyed out: Settings > Apps > FocusFamily > three dots > Allow restricted settings.
4. Phone A: open the child > Apps tab (the list appears within about a minute) > pick Instagram or YouTube > Lock now.
5. Phone B: opening the app shows the lock screen. Open the website in Chrome and it is blocked too.

## What works in this version
- Google login, Parent/Child roles, terms tick box, auto-linking by email
- Parent: lock now, lock for a duration, daily limit per app, whole-phone lock, bedtime hours, custom website blocking, usage report, approve "more time" requests, alerts when the child turns off a permission
- Child (Android): blocks apps however they are opened (Play Store, links, notifications), blocks the websites of locked apps in every browser (DNS filter), plus a backup check of Chrome/Brave/Edge/Samsung/Firefox/Opera address bars

## Not in this version yet (honest list)
- **iPhone as the child phone** (needs Apple's Screen Time entitlement, a Mac and a paid Apple developer account). The parent app can run on iPhone after you add the Firebase iOS config.
- **Uninstall protection** (Device Admin) and **push notifications to the parent** (needs Firebase Cloud Functions). Today the parent sees a warning on the child's card instead.
- Parents can lock the Settings app like any other app to stop a child switching things off.
- Play Store release needs the accessibility / VPN declaration forms and a lawyer-reviewed privacy policy and terms (`lib/legal.dart` is only a draft).

## If the build shows errors
This code was written without being able to compile it here. Copy the red error text and send it back: small fixes are normal on a first build.
