"""Used by the cloud build. Makes the release build use our own signing key."""
import re

P = "android/app/build.gradle.kts"
s = open(P, encoding="utf-8").read()

if "keystoreProperties" not in s:
    s = "import java.util.Properties\nimport java.io.FileInputStream\n\n" + s

    props = '''val keystoreProperties = Properties()
val keystoreFile = rootProject.file("key.properties")
if (keystoreFile.exists()) keystoreProperties.load(FileInputStream(keystoreFile))

'''
    s = s.replace("android {\n", props + "android {\n", 1)

    signing = '''    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = file(keystoreProperties["storeFile"] as String)
            storePassword = keystoreProperties["storePassword"] as String
        }
    }

'''
    s = s.replace("    buildTypes {", signing + "    buildTypes {", 1)

    s = s.replace(
        'signingConfig = signingConfigs.getByName("debug")',
        'signingConfig = signingConfigs.getByName("release")\n'
        '            isMinifyEnabled = false\n'
        '            isShrinkResources = false',
        1,
    )
    open(P, "w", encoding="utf-8").write(s)
    print("signing patched")
else:
    print("already patched")
