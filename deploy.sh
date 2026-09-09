#!/usr/bin/env bash
#
# 一键部署:编译 → 签名 → 安装 → 启动。默认走 self profile 对应的真机。
#
# 用法:
#   ./deploy.sh
#     默认部署到当前 profile 对应的真机。默认 profile 为 self。
#
#   ./deploy.sh --profile family
#     切到 family profile 对应的 Personal Team + Bundle ID + 默认设备。
#
#   ./deploy.sh --team <TEAM> --bundle-id <BUNDLE> --device-name <关键词>
#     不改 Xcode 工程，临时覆盖签名 team、Bundle ID 和目标设备。
#
#   ./deploy.sh --sim
#     只部署到模拟器。
#
#   ./deploy.sh --auto
#     同时部署到模拟器和目标真机。
#
#   ./deploy.sh --all-devices
#     使用当前签名配置安装到所有已连接真机。
#
#   ./deploy.sh --list-profiles
#     查看当前可用的 profile 别名配置。
#
#   ./deploy.sh --list-devices
#     查看当前已连接真机和它们的 Identifier。
#
#   ./deploy.sh --dry-run
#     只解析 profile / team / bundle / 设备，不实际编译和安装。
#
# 本地个性化配置写在 deploy.local.sh（已被 .gitignore 忽略）。

set -euo pipefail
cd "$(dirname "$0")"

PROJECT="AssetsOS.xcodeproj"
TARGET="AssetsOS"
CONFIG="Debug"
SRC_DIR="AssetsOS"
BUILD_DIR="$PWD/build"
SHOT_DIR="$BUILD_DIR/shots"
DEVICE_APP="$BUILD_DIR/$CONFIG-iphoneos/$TARGET.app"
SIM_APP="$BUILD_DIR/$CONFIG-iphonesimulator/$TARGET.app"
LOCAL_CONFIG="$PWD/deploy.local.sh"
DEFAULT_PROFILE="self"

# 模拟器机型:和本人真机保持一致,免得布局差异要来回换算
SIM_NAME="iPhone 15 Pro"
SIM_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-15-Pro"

NOISE='DVTPlugInLoading|DVTDownloads|Referenced from|Reason: tried|no such file|couldn.t be loaded|dyldError|UserInfo=|A required plugin|IDESimulator|ONLY_ACTIVE_ARCH'

PROFILE_NAMES=()

profile_key() {
  printf '%s' "${1//[^A-Za-z0-9_]/_}"
}

profile_var_name() {
  local key
  key="$(profile_key "$1")"
  printf 'PROFILE_%s_%s' "$key" "$2"
}

set_profile_field() {
  local var
  var="$(profile_var_name "$1" "$2")"
  printf -v "$var" '%s' "$3"
}

get_profile_field() {
  local var
  var="$(profile_var_name "$1" "$2")"
  eval "printf '%s' \"\${$var-}\""
}

profile_exists() {
  local wanted="$1" name idx
  for ((idx = 0; idx < ${#PROFILE_NAMES[@]}; idx++)); do
    name="${PROFILE_NAMES[$idx]}"
    [[ "$name" == "$wanted" ]] && return 0
  done
  return 1
}

register_profile() {
  local name="$1"
  local team="${2:-}"
  local bundle_id="${3:-}"
  local device_id="${4:-}"
  local device_name="${5:-}"
  local existing=0 item idx

  for ((idx = 0; idx < ${#PROFILE_NAMES[@]}; idx++)); do
    item="${PROFILE_NAMES[$idx]}"
    if [[ "$item" == "$name" ]]; then
      existing=1
      break
    fi
  done
  [[ "$existing" -eq 0 ]] && PROFILE_NAMES+=("$name")

  set_profile_field "$name" TEAM "$team"
  set_profile_field "$name" BUNDLE_ID "$bundle_id"
  set_profile_field "$name" DEVICE_ID "$device_id"
  set_profile_field "$name" DEVICE_NAME "$device_name"
}

# 仓库内置默认 profile；本机可在 deploy.local.sh 里覆盖/追加。
register_profile self "5U9667BR8R" "com.atw.AssetsOS"

if [[ -f "$LOCAL_CONFIG" ]]; then
  # shellcheck disable=SC1090
  source "$LOCAL_CONFIG"
fi

print_usage() {
  cat <<'EOF'
用法:
  ./deploy.sh
  ./deploy.sh --profile family
  ./deploy.sh --team <TEAM> --bundle-id <BUNDLE> --device-name <关键词>
  ./deploy.sh --sim
  ./deploy.sh --auto
  ./deploy.sh --all-devices
  ./deploy.sh --list-profiles
  ./deploy.sh --list-devices
  ./deploy.sh --dry-run

说明:
  - 默认模式是 device：只部署到当前 profile 对应的真机。
  - profile 具体配置来自 deploy.local.sh；脚本本体不再把多套 Personal Team 写死。
  - --team / --bundle-id / --device-name 可临时覆盖当前 profile，不改工程文件。
  - 如需恢复旧的“模拟器 + 真机一起跑”，使用 --auto。
EOF
}

require_arg() {
  if [[ $# -lt 2 || -z "${2-}" ]]; then
    echo "❌ 参数 $1 缺少值"
    exit 2
  fi
}

WATCH=0
SHOT=0
DRY_RUN=0
MODE="device"   # device | sim | auto
PROFILE="$DEFAULT_PROFILE"
DEVICE_ID=""
DEVICE_NAME=""
DEVICE_NAME_EXPLICIT=0
TEAM_OVERRIDE=""
BUNDLE_ID_OVERRIDE=""
ALL_DEVICES=0
LIST_PROFILES=0
LIST_DEVICES=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --watch|-w)
      WATCH=1
      shift
      ;;
    --shot|-s)
      SHOT=1
      shift
      ;;
    --sim)
      MODE="sim"
      shift
      ;;
    --device|-d)
      MODE="device"
      shift
      ;;
    --auto|--all-targets)
      MODE="auto"
      shift
      ;;
    --profile)
      require_arg "$1" "${2-}"
      PROFILE="$2"
      shift 2
      ;;
    --team)
      require_arg "$1" "${2-}"
      TEAM_OVERRIDE="$2"
      shift 2
      ;;
    --bundle-id)
      require_arg "$1" "${2-}"
      BUNDLE_ID_OVERRIDE="$2"
      shift 2
      ;;
    --device-name)
      require_arg "$1" "${2-}"
      DEVICE_NAME="$2"
      DEVICE_NAME_EXPLICIT=1
      MODE="device"
      shift 2
      ;;
    --all-devices)
      ALL_DEVICES=1
      MODE="device"
      shift
      ;;
    --list-profiles)
      LIST_PROFILES=1
      shift
      ;;
    --list-devices)
      LIST_DEVICES=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --help|-h)
      print_usage
      exit 0
      ;;
    -*)
      echo "❌ 未知参数:$1"
      print_usage
      exit 2
      ;;
    *)
      DEVICE_ID="$1"
      MODE="device"
      shift
      ;;
  esac
done

raw_device_list() {
  xcrun devicectl list devices 2>/dev/null || true
}

available_device_lines() {
  # "unavailable" 含 "available"，必须先排除，否则会把已断开的真机当成可用。
  raw_device_list | grep -Ei 'available|connected' | grep -Eiv 'unavailable' || true
}

available_device_ids() {
  available_device_lines | grep -Eio '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' || true
}

# devicectl 输出的是弯撇号 ’，手写配置里通常是直撇号 '，比较前统一。
normalize_device_text() {
  printf '%s' "$1" | sed "s/[’‘＇´\`]/'/g"
}

find_devices_by_name() {
  local needle line
  needle="$(normalize_device_text "$1")"
  [[ -z "$needle" ]] && return 0

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if normalize_device_text "$line" | grep -iqF -- "$needle"; then
      printf '%s\n' "$line"
    fi
  done <<< "$(available_device_lines)"
}

print_indented() {
  local text="$1"
  [[ -z "$text" ]] && return 0
  while IFS= read -r line; do
    [[ -n "$line" ]] && echo "    $line"
  done <<< "$text"
}

print_profiles() {
  local name team bundle_id device_id device_name default_marker idx

  echo "📋 当前 profile 配置"
  echo "    - 本地配置文件: $LOCAL_CONFIG"
  echo ""
  for ((idx = 0; idx < ${#PROFILE_NAMES[@]}; idx++)); do
    name="${PROFILE_NAMES[$idx]}"
    team="$(get_profile_field "$name" TEAM)"
    bundle_id="$(get_profile_field "$name" BUNDLE_ID)"
    device_id="$(get_profile_field "$name" DEVICE_ID)"
    device_name="$(get_profile_field "$name" DEVICE_NAME)"
    default_marker=""
    [[ "$name" == "$DEFAULT_PROFILE" ]] && default_marker=" (default)"

    echo "- $name$default_marker"
    echo "    team: ${team:-<未配置>}"
    echo "    bundle: ${bundle_id:-<未配置>}"
    echo "    device id: ${device_id:-<未配置>}"
    echo "    device name: ${device_name:-<未配置>}"
  done
}

if [[ "$LIST_PROFILES" -eq 1 ]]; then
  print_profiles
  exit 0
fi

if [[ "$LIST_DEVICES" -eq 1 ]]; then
  raw_device_list
  exit 0
fi

if ! profile_exists "$PROFILE"; then
  echo "❌ 未找到 profile:$PROFILE"
  echo ""
  print_profiles
  exit 2
fi

TEAM="${TEAM_OVERRIDE:-$(get_profile_field "$PROFILE" TEAM)}"
BUNDLE_ID="${BUNDLE_ID_OVERRIDE:-$(get_profile_field "$PROFILE" BUNDLE_ID)}"

# 命令行显式给了 --device-name 时不能再套用 profile 里存的 Identifier，
# 否则会静默装到另一台手机上。
if [[ -z "$DEVICE_ID" && "$DEVICE_NAME_EXPLICIT" -eq 0 ]]; then
  DEVICE_ID="$(get_profile_field "$PROFILE" DEVICE_ID)"
fi
if [[ -z "$DEVICE_NAME" ]]; then
  DEVICE_NAME="$(get_profile_field "$PROFILE" DEVICE_NAME)"
fi

if [[ -z "$BUNDLE_ID" ]]; then
  echo "❌ 当前 profile 没有可用的 Bundle ID。"
  echo "   请在 $LOCAL_CONFIG 里补齐，或通过 --bundle-id 临时覆盖。"
  exit 2
fi

if [[ "$MODE" != "sim" && -z "$TEAM" ]]; then
  echo "❌ 当前 profile 没有可用的 Development Team。"
  echo "   请在 $LOCAL_CONFIG 里补齐，或通过 --team 临时覆盖。"
  exit 2
fi

print_available_devices() {
  local lines
  lines="$(available_device_lines)"
  if [[ -z "$lines" ]]; then
    echo "   当前没有 available/connected 的真机。请确认手机已解锁并保持亮屏。" >&2
    return 0
  fi
  echo "   当前可用真机：" >&2
  print_indented "$lines" >&2
}

resolve_device_ids() {
  local matches ids count available_ids available_count

  if [[ "$ALL_DEVICES" -eq 1 ]]; then
    available_device_ids
    return 0
  fi

  if [[ -n "$DEVICE_ID" ]]; then
    printf '%s\n' "$DEVICE_ID"
    return 0
  fi

  if [[ -n "$DEVICE_NAME" ]]; then
    matches="$(find_devices_by_name "$DEVICE_NAME")"
    if [[ -z "$matches" ]]; then
      available_ids="$(available_device_ids)"
      available_count="$(printf '%s\n' "$available_ids" | sed '/^$/d' | wc -l | tr -d ' ')"
      if [[ "$available_count" -eq 1 ]]; then
        echo "⚠️  配置的设备名 \"$DEVICE_NAME\" 未匹配到已连接真机，改用当前唯一可用设备。" >&2
        print_available_devices
        echo "   请把 $LOCAL_CONFIG 里的 device name 改成新名字，或改成填写 Identifier。" >&2
        printf '%s\n' "$available_ids"
        return 0
      fi
      echo "❌ 没找到名称匹配 \"$DEVICE_NAME\" 的已连接 iPhone。" >&2
      print_available_devices
      echo "   改 $LOCAL_CONFIG 的 device name，或用 --device-name / Identifier 指定。" >&2
      return 1
    fi

    ids="$(printf '%s\n' "$matches" | grep -Eio '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' || true)"
    count="$(printf '%s\n' "$ids" | sed '/^$/d' | wc -l | tr -d ' ')"
    if [[ "$count" -gt 1 ]]; then
      echo "❌ 设备名 \"$DEVICE_NAME\" 匹配到多台真机，请改用 Identifier：" >&2
      print_indented "$matches" >&2
      return 1
    fi

    printf '%s\n' "$ids"
    return 0
  fi

  available_device_ids
}

print_signing_plan() {
  echo "🪪 当前签名配置:"
  echo "    - profile $PROFILE"
  echo "    - team $TEAM"
  echo "    - bundle $BUNDLE_ID"
  if [[ -n "$DEVICE_ID" ]]; then
    echo "    - default device id $DEVICE_ID"
  elif [[ -n "$DEVICE_NAME" ]]; then
    echo "    - default device name $DEVICE_NAME"
  fi
}

push_to_device() {
  local dev="$1" install_output launch_output
  echo "  📦 安装到真机 $dev …"

  if ! install_output="$(xcrun devicectl device install app --device "$dev" "$DEVICE_APP" 2>&1)"; then
    echo "  ❌ 真机安装失败"
    print_indented "$install_output"
    return 1
  fi

  if launch_output="$(xcrun devicectl device process launch --device "$dev" "$BUNDLE_ID" 2>&1)"; then
    echo "  ✅ $dev 已更新并启动"
  elif grep -qi 'not been explicitly trusted' <<< "$launch_output"; then
    echo "  ⚠️  已安装,但需在这台手机上信任证书:设置 → 通用 → VPN 与设备管理 → 信任你的 Apple ID"
    print_indented "$launch_output"
  elif grep -qi 'developer mode' <<< "$launch_output"; then
    echo "  ⚠️  已安装,但需在这台手机上开启开发者模式:设置 → 隐私与安全性 → 开发者模式"
    print_indented "$launch_output"
  else
    echo "  ❌ 真机启动失败"
    print_indented "$launch_output"
    return 1
  fi
}

# ============================ 模拟器 ============================

# 找到那台叫 $SIM_NAME 的模拟器。名字后面跟 " (" 是为了不误匹配 "iPhone 15 Pro Max"
sim_udid() {
  xcrun simctl list devices available 2>/dev/null \
    | grep -E "^[[:space:]]+${SIM_NAME} \(" \
    | grep -oiE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' \
    | head -1 || true
}

# 有没有可用的 iOS runtime。没装 runtime 时整个模拟器路径都要跳过
newest_ios_runtime() {
  xcrun simctl list runtimes 2>/dev/null \
    | grep -oE 'com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9-]+' \
    | tail -1 || true
}

# 确保模拟器存在且已启动,回显 UDID。失败回显空
ensure_sim() {
  local udid rt
  udid="$(sim_udid)"
  if [[ -z "$udid" ]]; then
    rt="$(newest_ios_runtime)"
    [[ -z "$rt" ]] && return 0
    udid="$(xcrun simctl create "$SIM_NAME" "$SIM_TYPE" "$rt" 2>/dev/null)" || return 0
  fi
  if ! xcrun simctl list devices 2>/dev/null | grep -q "$udid.*Booted"; then
    xcrun simctl boot "$udid" >/dev/null 2>&1 || true
    xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true
  fi
  echo "$udid"
}

push_to_sim() {
  local udid="$1"
  echo "  📦 安装到模拟器 $SIM_NAME …"
  open -a Simulator >/dev/null 2>&1 || true
  xcrun simctl terminate "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl install "$udid" "$SIM_APP"
  xcrun simctl launch "$udid" "$BUNDLE_ID" >/dev/null
  echo "  ✅ 模拟器已更新并启动"
  if [[ "$SHOT" -eq 1 ]]; then
    mkdir -p "$SHOT_DIR"
    local f="$SHOT_DIR/$(date +%H%M%S).png"
    sleep 3
    xcrun simctl io "$udid" screenshot "$f" >/dev/null 2>&1 && echo "  🖼  截图:$f"
  fi
}

# ============================ 编译 ============================

# $1 = iphoneos | iphonesimulator
build_for() {
  local sdk="$1" rc
  local -a extra
  if [[ "$sdk" == "iphoneos" ]]; then
    echo "🔨 编译真机版…"
    extra=(
      -allowProvisioningUpdates
      -allowProvisioningDeviceRegistration
      CODE_SIGN_STYLE=Automatic
      DEVELOPMENT_TEAM="$TEAM"
      PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID"
    )
  else
    echo "🔨 编译模拟器版…"
    extra=(
      CODE_SIGNING_ALLOWED=NO
      PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID"
    )
  fi
  set +e
  xcodebuild -project "$PROJECT" -target "$TARGET" -configuration "$CONFIG" \
    -sdk "$sdk" "${extra[@]}" SYMROOT="$BUILD_DIR" build 2>&1 \
    | grep -Ev "$NOISE" | tail -2
  rc=${PIPESTATUS[0]}
  set -e
  return "$rc"
}

# ============================ 主流程 ============================

deploy_once() {
  local devices="" sim_id="" sim_plan="" did_any=0

  if [[ "$MODE" != "sim" ]]; then
    devices="$(resolve_device_ids)" || return 1
  fi

  if [[ "$MODE" != "device" ]]; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
      sim_plan="$(sim_udid)"
      [[ -z "$sim_plan" ]] && sim_plan="$SIM_NAME"
    else
      sim_id="$(ensure_sim)"
    fi
  fi

  if [[ "$MODE" == "device" && -z "$devices" ]]; then
    echo "❌ 没找到已连接的 iPhone。请用数据线连上手机、解锁并保持亮屏后重试。"
    return 1
  fi

  if [[ "$MODE" == "sim" && -z "$sim_id" && "$DRY_RUN" -eq 0 ]]; then
    echo "❌ 没有可用的模拟器。先装 runtime:xcodebuild -downloadPlatform iOS"
    return 1
  fi

  if [[ "$MODE" == "auto" && -z "$devices" && -z "$sim_id" && "$DRY_RUN" -eq 0 ]]; then
    echo "❌ 既没有可用模拟器,也没有已连接的 iPhone。"
    return 1
  fi

  print_signing_plan
  echo "🎯 本次目标:"
  if [[ -n "$sim_id" ]]; then
    echo "    - 模拟器 $SIM_NAME ($sim_id)"
  elif [[ -n "$sim_plan" ]]; then
    echo "    - 模拟器 $SIM_NAME (${sim_plan})"
  fi
  if [[ -n "$devices" ]]; then
    echo "$devices" | sed 's/^/    - 真机 /'
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "🧪 dry-run: 仅完成配置解析，不执行编译和安装。"
    return 0
  fi

  if [[ -n "$sim_id" ]]; then
    if build_for iphonesimulator && [[ -d "$SIM_APP" ]]; then
      push_to_sim "$sim_id"
      did_any=1
    else
      echo "❌ 模拟器版编译失败。"
    fi
  fi

  if [[ -n "$devices" ]]; then
    if build_for iphoneos && [[ -d "$DEVICE_APP" ]]; then
      while IFS= read -r dev; do
        [[ -n "$dev" ]] && push_to_device "$dev"
      done <<< "$devices"
      did_any=1
    else
      echo "❌ 真机版编译失败。"
    fi
  fi

  [[ "$did_any" -eq 1 ]] || return 1
  echo "🎉 全部完成!"
}

# 源码指纹(所有 swift 文件的修改时间之和),用来检测变化
fingerprint() {
  find "$SRC_DIR" -type f -name '*.swift' -exec stat -f '%m' {} \; 2>/dev/null | paste -sd+ - | bc
}

if [[ "$WATCH" -eq 0 ]]; then
  deploy_once
  exit $?
fi

echo "👀 监听模式已开启,保存 $SRC_DIR/ 里的 .swift 文件即自动重新部署。按 Ctrl+C 退出。"
deploy_once || true
last="$(fingerprint)"
while true; do
  sleep 1
  now="$(fingerprint)"
  if [[ "$now" != "$last" ]]; then
    echo ""
    echo "🔁 检测到代码改动,重新部署…"
    last="$now"
    deploy_once || true
  fi
done
