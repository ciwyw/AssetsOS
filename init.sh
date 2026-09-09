#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$ROOT_DIR/AssetsOS.xcodeproj"
SCHEME="AssetsOS"
CONFIG="Debug"
BUILD_DIR="$ROOT_DIR/build/harness"
DERIVED_DATA="$ROOT_DIR/build/DerivedData-harness"

echo "=== Harness 初始化 ==="
echo "项目: $PROJECT"
echo "Scheme: $SCHEME"
echo "配置:  $CONFIG"
echo ""

mkdir -p "$BUILD_DIR" "$DERIVED_DATA"

echo "=== 项目检查 ==="
xcodebuild -list -project "$PROJECT" >/dev/null

echo "=== 模拟器构建验证 ==="
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath "$DERIVED_DATA" \
  SYMROOT="$BUILD_DIR" \
  build

echo "=== 验证结束 ==="
echo ""
echo "下一步:"
echo "1. 阅读 docs/spec/README.md，定位要改的模块"
echo "2. 阅读 TODO.md 了解未解决问题，阅读 CHANGELOG.md 了解该模块最近的改动和已否决的方向"
echo "3. 改完默认再跑一次 ./init.sh；只有用户明确要求时才运行 ./deploy.sh --sim"
echo "4. 结束前更新 docs/spec/ 对应模块，并在 CHANGELOG.md 追加一条"
