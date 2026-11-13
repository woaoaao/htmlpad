#!/bin/bash
# 在 ubuntu 上用 clang + ld64.lld 交叉编译 iOS App，产出未签名 ipa。
# 依赖：clang、lld、git-lfs，以及 sdk/iPhoneOS14.5.sdk
set +e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

LOG="$ROOT/build.log"
: > "$LOG"
exec > >(tee -a "$LOG") 2>&1

SDK="${SDK_PATH:-$ROOT/sdk/iPhoneOS14.5.sdk}"
APP="$ROOT/out/Payload/HTMLPad.app"
IPA="$ROOT/HTMLPad-unsigned.ipa"

echo "=== 环境 ==="
pwd
echo "sdk = $SDK"
ls "$SDK" > /dev/null 2>&1 && echo "sdk ok" || { echo "!!! SDK 缺失"; exit 0; }
clang --version | head -2

rm -rf "$ROOT/out" "$ROOT/build"
mkdir -p "$ROOT/build" "$APP"

CFLAGS=(-target arm64-apple-ios14.5 -isysroot "$SDK" -fobjc-arc -O2 -Wall
        -Wno-unused-parameter -I "$ROOT/objc")

echo "=== 编译 main.m ==="
clang "${CFLAGS[@]}" -c "$ROOT/objc/main.m" -o "$ROOT/build/main.o"
CC_STATUS=$?
echo "cc exit=$CC_STATUS"
if [ $CC_STATUS -ne 0 ]; then
  echo "!!! 编译失败，见上方错误"
  exit 0
fi

echo "=== 链接 ==="
clang -target arm64-apple-ios14.5 -isysroot "$SDK" -fuse-ld=lld \
      "$ROOT/build/main.o" \
      -framework UIKit -framework Foundation -framework WebKit -framework UniformTypeIdentifiers \
      -framework CoreGraphics -framework QuartzCore \
      -o "$APP/HTMLPad"
LINK_STATUS=$?
echo "link exit=$LINK_STATUS"
if [ $LINK_STATUS -ne 0 ]; then
  echo "!!! 链接失败，见上方错误"
  exit 0
fi

echo "=== 组装 .app ==="
cp "$ROOT/objc/Info.plist" "$APP/Info.plist"
cp "$ROOT/HTMLPad/editor.html" "$APP/editor.html"

ICONS="$ROOT/HTMLPad/Assets.xcassets/AppIcon.appiconset"
cp "$ICONS/icon-60@2x.png" "$APP/AppIcon60x60@2x.png"
cp "$ICONS/icon-60@3x.png" "$APP/AppIcon60x60@3x.png"
cp "$ICONS/icon-76@2x.png" "$APP/AppIcon76x76@2x~ipad.png"
cp "$ICONS/icon-40@2x.png" "$APP/AppIcon40x40@2x.png"
cp "$ICONS/icon-40@3x.png" "$APP/AppIcon40x40@3x.png"
cp "$ICONS/icon-29@2x.png" "$APP/AppIcon29x29@2x.png"
cp "$ICONS/icon-29@3x.png" "$APP/AppIcon29x29@3x.png"

chmod 755 "$APP/HTMLPad"

echo "=== 检查 ==="
file "$APP/HTMLPad"
ls -la "$APP"
python3 -c "import plistlib,sys; d=plistlib.load(open('$APP/Info.plist','rb')); print('plist ok:', d['CFBundleIdentifier'], d['CFBundleExecutable'], 'min', d['MinimumOSVersion'])"

echo "=== 打包 ipa ==="
rm -f "$IPA"
cd "$ROOT/out" || exit 1
zip -qry "$IPA" Payload
cd "$ROOT" || exit 1
ls -la "$IPA"
python3 - <<'PY'
import zipfile, os, sys
p = os.path.join(os.environ['PWD'], 'HTMLPad-unsigned.ipa')
z = zipfile.ZipFile(p)
names = z.namelist()
print('entries:', len(names))
for n in names:
    print('  ', n)
ok = any(n.endswith('HTMLPad.app/HTMLPad') for n in names)
print('IPA_OK' if ok else 'IPA_BAD')
PY

echo "=== 完成 ==="
