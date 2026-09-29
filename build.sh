#!/bin/bash
set -e

TIMESTAMP=$(date "+%d%m%y%H%M%S")
OUTPUT_APP="./Builds/Paicord-${TIMESTAMP}.app"
mkdir -p Builds

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -workspace Paicord.xcworkspace \
  -scheme Paicord \
  -configuration Release \
  -destination 'platform=macOS,arch=x86_64' \
  -derivedDataPath .build/DerivedData \
  ARCHS="x86_64" \
  ONLY_ACTIVE_ARCH=YES \
  COMPILER_INDEX_STORE_ENABLE=NO \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=YES \
  -IDEBuildOperationMaxNumberOfConcurrentCompileTasks=$(sysctl -n hw.ncpu) \
  build

rm -rf "${OUTPUT_APP}"
cp -R .build/DerivedData/Build/Products/Release/Paicord.app "${OUTPUT_APP}"
codesign --force --deep --sign - "${OUTPUT_APP}"
xattr -cr "${OUTPUT_APP}"
echo "Build complete: ${OUTPUT_APP}"
