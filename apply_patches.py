"""Patches the Gradle files that `flutter create` generated so Firebase and the
native Kotlin code build. Safe to run more than once."""
import os
import re
import sys

APP = os.path.join("android", "app", "build.gradle.kts")
SETTINGS = os.path.join("android", "settings.gradle.kts")

if not (os.path.exists(APP) and os.path.exists(SETTINGS)):
    print("Could not find android/app/build.gradle.kts or android/settings.gradle.kts.")
    print("Run this from inside the focus_family project folder.")
    sys.exit(1)

# ---- android/settings.gradle.kts : declare the google-services plugin
s = open(SETTINGS, encoding="utf-8").read()
if "com.google.gms.google-services" not in s:
    s, n = re.subn(
        r'(id\("org\.jetbrains\.kotlin\.android"\)[^\n]*\n)',
        r'\1    id("com.google.gms.google-services") version "4.4.2" apply false\n',
        s, count=1)
    if n == 0:
        print("!! Could not patch settings.gradle.kts automatically. Add this line inside plugins { }:")
        print('    id("com.google.gms.google-services") version "4.4.2" apply false')
    else:
        open(SETTINGS, "w", encoding="utf-8").write(s)
        print("patched settings.gradle.kts")

# ---- android/app/build.gradle.kts
a = open(APP, encoding="utf-8").read()
changed = False

if "com.google.gms.google-services" not in a:
    a, n = re.subn(
        r'(id\("dev\.flutter\.flutter-gradle-plugin"\)[^\n]*\n)',
        r'\1    id("com.google.gms.google-services")\n',
        a, count=1)
    if n == 0:
        print('!! Add id("com.google.gms.google-services") to the plugins { } block of android/app/build.gradle.kts')
    changed = changed or n > 0

if "minSdk = flutter.minSdkVersion" in a:
    a = a.replace("minSdk = flutter.minSdkVersion", "minSdk = 23")
    changed = True

if "firebase-bom" not in a:
    a += '''

dependencies {
    implementation(platform("com.google.firebase:firebase-bom:33.4.0"))
    implementation("com.google.firebase:firebase-firestore")
    implementation("com.google.firebase:firebase-auth")
}
'''
    changed = True

if changed:
    open(APP, "w", encoding="utf-8").write(a)
    print("patched app/build.gradle.kts")
print("done")
