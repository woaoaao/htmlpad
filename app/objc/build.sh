#!/bin/bash
# 「HTML」本地 HTML 查看器 —— Ubuntu 交叉编译成未签名 ipa
set +e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT" || exit 1

LOG="$ROOT/build-viewer.log"
: > "$LOG"
exec > >(tee -a "$LOG") 2>&1

SDK="${SDK_PATH:-$ROOT/sdk/iPhoneOS14.5.sdk}"
APP="$ROOT/out-viewer/Payload/HTML.app"
IPA="$ROOT/HTML-viewer-unsigned.ipa"

echo "=== 环境 ==="
pwd
echo "sdk = $SDK"
ls "$SDK" > /dev/null 2>&1 && echo "sdk ok" || { echo "!!! SDK 缺失"; exit 0; }
clang --version | head -2

rm -rf "$ROOT/out-viewer" "$ROOT/build-viewer"
mkdir -p "$ROOT/build-viewer" "$APP"

CFLAGS=(-target arm64-apple-ios14.5 -isysroot "$SDK" -fobjc-arc -O2 -Wall -Wno-unused-parameter)

echo "=== 编译 viewer.m ==="
clang "${CFLAGS[@]}" -c "$ROOT/app/objc/viewer.m" -o "$ROOT/build-viewer/viewer.o"
CC=$?
echo "cc exit=$CC"
if [ $CC -ne 0 ]; then echo "!!! 编译失败"; exit 0; fi

echo "=== 链接 ==="
clang -target arm64-apple-ios14.5 -isysroot "$SDK" -fuse-ld=lld \
      "$ROOT/build-viewer/viewer.o" \
      -framework UIKit -framework Foundation -framework WebKit \
      -framework CoreGraphics -framework QuartzCore \
      -o "$APP/HTML"
LINK=$?
echo "link exit=$LINK"
if [ $LINK -ne 0 ]; then echo "!!! 链接失败"; exit 0; fi

echo "=== 组装 .app ==="
cp "$ROOT/app/objc/Info.plist" "$APP/Info.plist"

ICONS="$ROOT/HTMLPad/Assets.xcassets/AppIcon.appiconset"
if [ -d "$ICONS" ]; then
  cp "$ICONS/icon-60@2x.png" "$APP/AppIcon60x60@2x.png"
  cp "$ICONS/icon-60@3x.png" "$APP/AppIcon60x60@3x.png"
  cp "$ICONS/icon-76@2x.png" "$APP/AppIcon76x76@2x~ipad.png"
  cp "$ICONS/icon-40@2x.png" "$APP/AppIcon40x40@2x.png"
  cp "$ICONS/icon-40@3x.png" "$APP/AppIcon40x40@3x.png"
  cp "$ICONS/icon-29@2x.png" "$APP/AppIcon29x29@2x.png"
  cp "$ICONS/icon-29@3x.png" "$APP/AppIcon29x29@3x.png"
else
  echo "!!! 找不到图标目录"
fi

chmod 755 "$APP/HTML"

echo "=== 检查 ==="
file "$APP/HTML"
ls -la "$APP"
python3 -c "import plistlib; d=plistlib.load(open('$APP/Info.plist','rb')); print('plist ok:', d['CFBundleIdentifier'], d['CFBundleExecutable'], 'min', d['MinimumOSVersion'])"

echo "=== 打包 ipa ==="
rm -f "$IPA"
cd "$ROOT/out-viewer" || exit 1
zip -qry "$IPA" Payload
cd "$ROOT" || exit 1
ls -la "$IPA"
python3 - <<'PY'
import os, zipfile
p = os.path.join(os.environ['PWD'], 'HTML-viewer-unsigned.ipa')
z = zipfile.ZipFile(p)
names = z.namelist()
print('entries:', len(names))
for n in names:
    print('  ', n)
print('IPA_OK' if any(n.endswith('HTML.app/HTML') for n in names) else 'IPA_BAD')
PY

echo "=== 完成 ==="
