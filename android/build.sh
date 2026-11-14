#!/bin/bash
# 「爱豆」Android 版：不依赖 Gradle，直接用 Android SDK 的 aapt2 / javac / d8 / zipalign / apksigner 手动打包
set +e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

LOG="$ROOT/build-android.log"
: > "$LOG"
exec > >(tee -a "$LOG") 2>&1

echo "=== 环境 ==="
java -version 2>&1 | head -3
which javac keytool zip
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/usr/local/lib/android/sdk}}"
echo "sdk=$SDK"
ls "$SDK" 2>&1 | head -10

PLATFORM=$(ls -d "$SDK"/platforms/android-* 2>/dev/null | sort -V | tail -1)
BT=$(ls -d "$SDK"/build-tools/* 2>/dev/null | sort -V | tail -1)
echo "platform=$PLATFORM"
echo "build-tools=$BT"
if [ -z "$PLATFORM" ] || [ -z "$BT" ]; then
  echo "!!! 找不到 Android platform 或 build-tools"
  exit 0
fi

AAPT2="$BT/aapt2"
D8="$BT/d8"
ZIPALIGN="$BT/zipalign"
APKSIGNER="$BT/apksigner"
ls -la "$AAPT2" "$D8" "$ZIPALIGN" "$APKSIGNER" 2>&1

APP="$ROOT/android"
OUT="$ROOT/out-android"
rm -rf "$OUT"
mkdir -p "$OUT/gen" "$OUT/classes" "$OUT/dex"

echo "=== 1) aapt2 compile ==="
"$AAPT2" compile --dir "$APP/res" -o "$OUT/res.zip"
echo "exit=$?"

echo "=== 2) aapt2 link ==="
"$AAPT2" link -o "$OUT/base.apk" \
  -I "$PLATFORM/android.jar" \
  --manifest "$APP/AndroidManifest.xml" \
  -R "$OUT/res.zip" \
  --java "$OUT/gen" \
  --min-sdk-version 21 \
  --target-sdk-version 34 \
  --version-code 1 \
  --version-name 1.0
echo "exit=$?"

echo "=== 3) javac ==="
find "$APP/src" "$OUT/gen" -name "*.java" > "$OUT/sources.txt"
cat "$OUT/sources.txt"
javac -encoding UTF-8 -source 8 -target 8 -nowarn \
  -bootclasspath "$PLATFORM/android.jar" \
  -classpath "$PLATFORM/android.jar" \
  -d "$OUT/classes" @"$OUT/sources.txt"
JC=$?
echo "javac exit=$JC"
if [ $JC -ne 0 ]; then
  echo "!!! Java 编译失败，见上方错误"
  exit 0
fi

echo "=== 4) d8 ==="
find "$OUT/classes" -name "*.class" > "$OUT/classlist.txt"
"$D8" --release --min-api 21 --lib "$PLATFORM/android.jar" --output "$OUT/dex" $(cat "$OUT/classlist.txt")
echo "d8 exit=$?"

echo "=== 5) 把 classes.dex 放进 apk ==="
cd "$OUT/dex" || exit 1
zip -q "$OUT/base.apk" classes.dex
echo "zip exit=$?"
cd "$ROOT" || exit 1

echo "=== 6) zipalign ==="
"$ZIPALIGN" -f 4 "$OUT/base.apk" "$OUT/aligned.apk"
echo "exit=$?"

echo "=== 7) 生成签名密钥并签名 ==="
keytool -genkeypair -keystore "$OUT/aidou.keystore" -storepass aidou123 -keypass aidou123 \
  -alias aidou -keyalg RSA -keysize 2048 -validity 10000 \
  -dname "CN=AiDou, OU=AiDou, O=AiDou, L=CN, ST=CN, C=CN" > /dev/null 2>&1
echo "keytool exit=$?"
"$APKSIGNER" sign --ks "$OUT/aidou.keystore" --ks-pass pass:aidou123 --key-pass pass:aidou123 \
  --min-sdk-version 21 --out "$ROOT/AiDou.apk" "$OUT/aligned.apk"
echo "apksigner exit=$?"

echo "=== 检查 ==="
ls -la "$ROOT/AiDou.apk"
"$APKSIGNER" verify --print-certs "$ROOT/AiDou.apk" 2>&1 | head -6
python3 - <<'PY'
import os, zipfile
p = os.path.join(os.environ['PWD'], 'AiDou.apk')
if not os.path.exists(p):
    print('APK_MISSING')
else:
    z = zipfile.ZipFile(p)
    names = z.namelist()
    print('apk bytes:', os.path.getsize(p), 'entries:', len(names))
    print('has classes.dex:', 'classes.dex' in names)
    print('has AndroidManifest:', 'AndroidManifest.xml' in names)
    print('APK_OK' if 'classes.dex' in names and 'AndroidManifest.xml' in names else 'APK_BAD')
PY
echo "=== 完成 ==="
