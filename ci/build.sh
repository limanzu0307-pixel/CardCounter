#!/bin/bash
# 运行测试并打出未签名 IPA，GitHub Actions 和 Codemagic 共用。
set -euo pipefail

brew install xcodegen ldid
xcodegen generate

UDID=$(xcrun simctl list devices available -j | python3 -c "
import json, sys
devices = json.load(sys.stdin)['devices']
print(next(d['udid'] for runtime, items in devices.items() if 'iOS' in runtime for d in items if d['name'].startswith('iPhone')))
")

xcodebuild test \
  -project CardCounter.xcodeproj \
  -scheme CardCounter \
  -destination "platform=iOS Simulator,id=$UDID" \
  CODE_SIGNING_ALLOWED=NO

xcodebuild build \
  -project CardCounter.xcodeproj \
  -scheme CardCounter \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO

APP=build/Build/Products/Release-iphoneos/CardCounter.app
# 未签名包不带权限声明，这里写入 App Group，供安装工具重签时读取
ldid -SBroadcast/Broadcast.entitlements "$APP/PlugIns/Broadcast.appex/Broadcast"
ldid -SApp/CardCounter.entitlements "$APP/CardCounter"
rm -rf Payload
mkdir Payload
cp -R "$APP" Payload/
zip -qry CardCounter.ipa Payload
