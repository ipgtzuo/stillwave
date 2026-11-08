#!/bin/bash
# 叩音 · Stillwave — 真机一键：编译 → 安装 → 启动
#
# 一次性前提（必须本人做，脚本无法代办）：
#   1. Xcode → Settings → Accounts 登录 Apple ID（免费 Personal Team 即可）
#   2. iPhone 用 USB 连到 Mac，解锁并点「信任此电脑」
#   3. iPhone → 设置 → 隐私与安全性 → 开发者模式 → 打开（会要求重启）
#
# 用法：
#   ./scripts/install-device.sh [TEAM_ID] [DEVICE_UDID] [BUNDLE_PREFIX]
# 例：
#   ./scripts/install-device.sh A1B2C3D4E5 00008130-000059DC1151001C com.zuog.kouyin
# 在 Xcode 登录过账号后可直接零参数运行，Team ID 会从证书 / 描述文件自动推断。
#
# Team ID：Xcode → Settings → Accounts → 选中 Team 可见（10 位）。
# 不传 UDID 时自动取第一台已配对的物理 iPhone。
# 环境变量覆盖：DEVELOPMENT_TEAM / DEVICE_UDID / IOS_BUNDLE_ID / DERIVED_DATA。

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJ="$ROOT/KouShui.xcodeproj"
DD="${DERIVED_DATA:-/tmp/koushui-device-dd}"
TEAM="${1:-${DEVELOPMENT_TEAM:-}}"
UDID="${2:-${DEVICE_UDID:-}}"
PREFIX="${3:-${IOS_BUNDLE_ID:-com.example.koushui}}"

# Team ID 自动推断：① 参数/环境变量 → ② Xcode 偏好记录的 teamID → ③ 证书 Subject 的 OU
# → ④ 已有描述文件的 TeamIdentifier。
# ⚠ 不能从 codesigning 身份名抓括号：Apple Development 证书名里的 "(XXXXXXXXXX)" 是
#   Personal Team 的 member ID（本机 YT278M5BQ5），真正的 Team ID 在 OU（9RH9WL3PQ3）。
#   02:59 实测踩过这个坑，用 member ID 会报 "No account for team …"。
# 全部推断不到也不传 DEVELOPMENT_TEAM：工程里已固化本机 Team，xcodebuild 会自动继承。
if [[ -z "$TEAM" ]]; then
  TEAM="$(defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier 2>/dev/null \
    | python3 -c 'import sys,re; m=re.search(r"teamID\s*=\s*([A-Z0-9]{10})",sys.stdin.read()); print(m.group(1) if m else "")' 2>/dev/null || true)"
fi
if [[ -z "$TEAM" ]]; then
  TEAM="$(security find-certificate -a -c 'Apple Development' -p "$HOME/Library/Keychains/login.keychain-db" 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null \
    | python3 -c 'import sys,re; m=re.search(r"OU=([A-Z0-9]{10})",sys.stdin.read()); print(m.group(1) if m else "")' 2>/dev/null || true)"
fi
if [[ -z "$TEAM" ]]; then
  PROFILE_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"
  if [[ -d "$PROFILE_DIR" ]]; then
    for P in "$PROFILE_DIR"/*.mobileprovision; do
      [[ -f "$P" ]] || continue
      TEAM="$(security cms -D -i "$P" 2>/dev/null | python3 -c 'import plistlib,sys; d=plistlib.loads(sys.stdin.buffer.read()); t=d.get("TeamIdentifier") or []; print(t[0] if t else "")' 2>/dev/null || true)"
      [[ -n "$TEAM" ]] && break
    done
  fi
fi
if [[ -n "$TEAM" ]]; then
  echo "→ Team ID: ${TEAM}（自动推断）"
else
  echo "→ 未推断出 Team ID，使用工程内已固化的 DEVELOPMENT_TEAM。"
fi

if [[ "$PREFIX" == com.example.* ]]; then
  echo "⚠  ${PREFIX} 是占位 ID，可能与其他团队冲突，建议换成自己的反向域名。"
  echo "   Watch 端会用 ${PREFIX}.watch，Watch plist 的 companion 同步指向 ${PREFIX}。"
fi

# --- 1. 找设备 ---
DEV_JSON="$(mktemp /tmp/koushui-devices.XXXXXX)"
trap 'rm -f "$DEV_JSON"' EXIT
xcrun devicectl list devices --json-output "$DEV_JSON" >/dev/null 2>&1 || true

if [[ -z "$UDID" ]]; then
  UDID="$(python3 -c '
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
for x in d.get("result", {}).get("devices", []):
    h = x.get("hardwareProperties") or {}
    if h.get("reality") == "physical" and h.get("platform") == "iOS":
        print(h.get("udid", ""))
        break
' "$DEV_JSON" 2>/dev/null || true)"
fi

if [[ -z "$UDID" ]]; then
  echo "✗ 没找到已配对的物理 iPhone。请用 USB 连上、解锁并信任此电脑。" >&2
  exit 1
fi

STATE="$(python3 -c '
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
for x in d.get("result", {}).get("devices", []):
    h = x.get("hardwareProperties") or {}
    if h.get("udid") == sys.argv[2]:
        print((x.get("connectionProperties") or {}).get("tunnelState", "unknown"))
        break
' "$DEV_JSON" "$UDID" 2>/dev/null || true)"

echo "→ 设备 UDID: $UDID  连接: ${STATE:-unknown}"
if [[ "$STATE" == "disconnected" ]]; then
  echo "⚠  设备当前离线。仍会先编译；安装前请插上 USB、解锁手机。"
fi

# --- 2. arm64 真机编译 + 自动签名 ---
echo "→ 开始 arm64 真机编译（自动签名 / 自动注册设备）…"
# macOS 自带 bash 3.2：set -u 下空数组展开会报 unbound variable，数组里始终留一个参数。
SIGN_ARGS=(CODE_SIGN_STYLE=Automatic)
if [[ -n "$TEAM" ]]; then
  SIGN_ARGS+=(DEVELOPMENT_TEAM="$TEAM")
fi
if ! xcodebuild -project "$PROJ" -scheme Stillwave \
  -destination 'generic/platform=iOS' -configuration Debug \
  -allowProvisioningUpdates \
  -derivedDataPath "$DD" \
  "${SIGN_ARGS[@]}" \
  IOS_BUNDLE_ID="$PREFIX" \
  WATCH_BUNDLE_ID="$PREFIX.watch" \
  build > /tmp/koushui-device-build.log 2>&1; then
  echo "✗ 编译 / 签名失败，关键报错：" >&2
  /usr/bin/grep -iE 'error:|requires a development team|no account|no profiles|cannot be registered|invalid credentials' \
    /tmp/koushui-device-build.log | head -12 >&2
  echo "  完整日志: /tmp/koushui-device-build.log" >&2
  if /usr/bin/grep -qiE 'missing Xcode-Username|Invalid credentials|No Accounts|requires a development team' \
      /tmp/koushui-device-build.log; then
    echo "  ↳ 这是 Apple ID 会话问题，不是代码问题：命令行进程读不到 Xcode 存的账号凭据" >&2
    echo "    （Data Protection 钥匙串只对 Xcode 授权）。两条路：" >&2
    echo "    ① 直接在 Xcode 里 ▶ Run 一次（GUI 会话有效时可直接签成功）；" >&2
    echo "    ② Xcode → Settings → Accounts 重新登录 Apple ID，再在非沙箱终端重跑本脚本。" >&2
  fi
  exit 1
fi
tail -3 /tmp/koushui-device-build.log

APP="$(find "$DD/Build/Products/Debug-iphoneos" -maxdepth 1 -name 'Stillwave.app' -type d | head -1)"
if [[ -z "$APP" ]]; then
  echo "✗ 没找到 Stillwave.app（$DD/Build/Products/Debug-iphoneos）" >&2
  exit 1
fi
echo "→ 产物: $APP"
if [[ -d "$APP/Watch/KouShuiWatch.app" ]]; then
  echo "→ 已内嵌 Watch App: $APP/Watch/KouShuiWatch.app"
else
  echo "⚠  产物里没有内嵌 Watch App，请检查 scheme 依赖。"
fi
echo "→ 签名信息："
codesign -dv --verbose=2 "$APP" 2>&1 | /usr/bin/grep -E 'Identifier|TeamIdentifier|Signature' | head -5 || true

# --- 3. 安装并启动 ---
echo "→ 安装到 $UDID …"
if ! xcrun devicectl device install app --device "$UDID" "$APP"; then
  echo "✗ 安装失败。检查：手机是否解锁 / 是否信任此电脑 / 开发者模式是否打开 / 设备是否已注册到 Team。" >&2
  echo "  也可以先在 Xcode 里 ▶ Run 一次，让 Xcode 生成证书与描述文件后再跑本脚本。" >&2
  exit 1
fi

echo "→ 启动 $PREFIX …"
if ! xcrun devicectl device process launch --device "$UDID" "$PREFIX"; then
  echo "⚠  未能自动启动，请在手机主屏手动点开「叩音」。"
fi

echo "✓ 完成。"
echo "  若提示「不受信任的开发者」：iPhone → 设置 → 通用 → VPN 与设备管理 → 信任你的 Apple ID。"
echo "  Watch 端：iPhone 的 Watch App → 我的手表 → 叩音 → 安装；或 Xcode 切 KouShuiWatch scheme 运行到手表。"
echo "  免费 Personal Team 签名 7 天有效，过期后重跑一次本脚本即可。"
