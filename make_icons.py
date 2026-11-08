#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
叩音 · Stillwave — App Store 图标生成器（只用 Python 标准库，无第三方依赖）

  python3 make_icons.py

产出（都写在脚本同目录）：
  app-icon.svg               矢量源，可继续在 Figma / Sketch 里改
  app-icon-1024.png          App Store 主图：1024×1024、sRGB、RGB 无 alpha、无圆角
  app-icon-paper-1024.png    宣纸浅色变体（深色模式对照 / 宣传物料备选）
  app-icon-watch-1024.png    watchOS target 图标（系统自动裁圆，故主体加粗收紧）

设计：一枚「叩点」落向一整片连续水线，水线被叩出一列高斯包络调制的行波，
向两侧自然衰减 —— 与 App 里的连续高度场同源。**刻意不画同心圆涟漪**。
深色版是加光（墨池里的月影），浅色版是减光（宣纸上的淡墨）。
"""
import math
import os
import struct
import zlib

W = H = 1024
OUT = os.path.dirname(os.path.abspath(__file__))

# 高斯查表：t = |d| / sigma，t 取 0..8
GAUSS = [math.exp(-(k / 64.0) ** 2) for k in range(513)]          # exp(-t²)
DOTQ = [math.exp(-1.40 * (k / 40.0)) for k in range(801)]         # exp(-1.4q)
HALOQ = [math.exp(-0.35 * (k / 40.0)) for k in range(801)]        # exp(-0.35q)


def gauss(t):
    k = int(t * 64.0)
    return GAUSS[k] if k < 512 else 0.0


def dot_lut(q, table):
    k = int(q * 40.0)
    return table[k] if k < 800 else 0.0


CFG = {
    "dark": dict(
        base=(5, 7, 9), moon=(92, 133, 120), line=(150, 196, 178), dot=(208, 224, 212),
        sign=1.0, moon_gain=0.34, line_core=0.90, line_halo=0.11, line2=0.22,
        dot_gain=1.00, beam=0.0, amp=0.052, core=0.0026, halo=0.013,
        dot_rx=0.055, dot_ry=0.050, second=True,
    ),
    "paper": dict(
        base=(220, 216, 204), moon=(30, 36, 30), line=(120, 132, 116), dot=(150, 160, 146),
        sign=-1.0, moon_gain=0.80, line_core=0.92, line_halo=0.12, line2=0.20,
        dot_gain=1.00, beam=0.0, amp=0.052, core=0.0026, halo=0.013,
        dot_rx=0.055, dot_ry=0.050, second=True,
    ),
    "watch": dict(
        base=(5, 7, 9), moon=(100, 144, 128), line=(166, 214, 194), dot=(238, 246, 236),
        sign=1.0, moon_gain=0.42, line_core=1.18, line_halo=0.16, line2=0.0,
        dot_gain=1.12, beam=0.0, amp=0.076, core=0.0052, halo=0.020,
        dot_rx=0.072, dot_ry=0.082, second=False,
    ),
}


def build_rows(cfg):
    """可分离的高斯 + 查表，逐像素算出 RGB；返回 bytes。"""
    buf = bytearray((W * 3 + 1) * H)
    c = cfg
    base, moon_c, line_c, dot_c = c["base"], c["moon"], c["line"], c["dot"]
    sign = c["sign"]

    # 只依赖 u 的列预计算
    env = [0.0] * W
    y1 = [0.0] * W
    y2 = [0.0] * W
    fade = [0.0] * W
    moon_u = [0.0] * W
    dot_u = [0.0] * W
    beam_u = [0.0] * W
    vig_u = [0.0] * W
    for i in range(W):
        u = (i + 0.5) / W
        du = u - 0.5
        e = math.exp(-((du / 0.30) ** 2))
        wv = math.cos(2.0 * math.pi * du / 0.19)
        env[i] = e
        y1[i] = 0.615 - c["amp"] * e * wv
        y2[i] = 0.660 + 0.60 * c["amp"] * e * math.cos(2.0 * math.pi * du / 0.19 + 1.15)
        fade[i] = 0.10 + 0.90 * e
        moon_u[i] = math.exp(-(du * du) / (2.0 * 0.34 ** 2))
        dot_u[i] = (du / c["dot_rx"]) ** 2
        beam_u[i] = math.exp(-((du / 0.020) ** 2))
        vig_u[i] = du * du

    core_s, halo_s = c["core"], c["halo"]
    for j in range(H):
        off = j * (W * 3 + 1)
        buf[off] = 0  # PNG filter: None
        v = (j + 0.5) / H
        dv = v - 0.5
        moon_v = math.exp(-((v - 0.42) ** 2) / (2.0 * 0.34 ** 2))
        dot_v = ((v - 0.335) / c["dot_ry"]) ** 2
        glow_v = math.exp(-((v - 0.47) ** 2) / (2.0 * 0.09 ** 2))
        vig_v = dv * dv
        for i in range(W):
            q = dot_u[i] + dot_v
            dot_amt = dot_lut(q, DOTQ) * c["dot_gain"] + dot_lut(q, HALOQ) * 0.10
            d1 = abs(v - y1[i])
            light = gauss(d1 / core_s) * c["line_core"] + gauss(d1 / halo_s) * c["line_halo"]
            if c["second"]:
                d2 = abs(v - y2[i])
                light += gauss(d2 / core_s) * c["line2"]
            light *= fade[i]
            moon_amt = moon_u[i] * moon_v * c["moon_gain"]
            beam_amt = beam_u[i] * glow_v * c["beam"] if c["beam"] else 0.0
            vig = 1.0 - 0.84 * (vig_u[i] + vig_v)
            if vig < 0.45:
                vig = 0.45
            a = moon_amt
            b = light + beam_amt
            d = dot_amt
            for ch in range(3):
                col = base[ch] + sign * (moon_c[ch] * a + line_c[ch] * b + dot_c[ch] * d)
                col *= vig
                if col < 0:
                    col = 0
                elif col > 255:
                    col = 255
                buf[off + 1 + i * 3 + ch] = int(col + 0.5)
    return bytes(buf)


def png_chunk(tag, data):
    return (struct.pack(">I", len(data)) + tag + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))


def write_png(path, rows):
    png = b"\x89PNG\r\n\x1a\n"
    png += png_chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0))  # 2 = RGB, 无 alpha
    png += png_chunk(b"sRGB", b"\x00")                                          # perceptual sRGB
    png += png_chunk(b"IDAT", zlib.compress(rows, 9))
    png += png_chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)
    return len(png)


def svg_path(cfg, which="main", n=260):
    pts = []
    for i in range(n):
        u = i / (n - 1)
        du = u - 0.5
        e = math.exp(-((du / 0.30) ** 2))
        wv = math.cos(2.0 * math.pi * du / 0.19)
        if which == "main":
            y = 0.615 - cfg["amp"] * e * wv
        else:
            y = 0.660 + 0.60 * cfg["amp"] * e * math.cos(2.0 * math.pi * du / 0.19 + 1.15)
        pts.append("%.2f,%.2f" % (u * 1024, y * 1024))
    return "M " + " L ".join(pts)


def svg_markup(cfg, uid):
    """同一套几何的矢量版；uid 让多份 SVG 内联到同一页面时渐变 id 不冲突。"""
    dark = cfg["sign"] > 0
    bold = cfg is CFG["watch"]
    bg0 = "#050709" if dark else "#dcd8cc"
    bg1 = "#0b1212" if dark else "#cfcbbf"
    line = "#a8d3c2" if dark else "#4a5c4e"
    dot = "#eef4ec" if dark else "#2c3a30"
    if bold:
        line = "#b6e0cc"
    b, k, w = uid + "bg", uid + "knock", uid + "wave"
    wide = 14 if bold else 7
    halo_w = 64 if bold else 46
    second = "" if not cfg["second"] else (
        '  <path d="%s" fill="none" stroke="url(#%s)" stroke-width="9" opacity=".22" stroke-linecap="round"/>\n'
        % (svg_path(cfg, "second"), w))
    rx = 148 if bold else 112
    ry = 132 if bold else 100
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <!-- 叩音 · Stillwave — 一枚叩点，落向一整片连续水线；无同心圆、无圆角、无透明 -->
  <defs>
    <radialGradient id="{b}" cx="50%" cy="42%" r="72%">
      <stop offset="0%" stop-color="{bg1}"/><stop offset="100%" stop-color="{bg0}"/>
    </radialGradient>
    <radialGradient id="{k}" cx="50%" cy="50%" r="50%">
      <stop offset="0%" stop-color="{dot}"/><stop offset="55%" stop-color="{dot}" stop-opacity=".72"/>
      <stop offset="100%" stop-color="{dot}" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="{w}" x1="0" x2="1">
      <stop offset="0%" stop-color="{line}" stop-opacity="0"/>
      <stop offset="22%" stop-color="{line}" stop-opacity=".55"/>
      <stop offset="50%" stop-color="{line}" stop-opacity="1"/>
      <stop offset="78%" stop-color="{line}" stop-opacity=".55"/>
      <stop offset="100%" stop-color="{line}" stop-opacity="0"/>
    </linearGradient>
  </defs>
  <rect width="1024" height="1024" fill="{bg0}"/>
  <rect width="1024" height="1024" fill="url(#{b})"/>
  <ellipse cx="512" cy="343" rx="{rx}" ry="{ry}" fill="url(#{k})"/>
{second}  <path d="{svg_path(cfg, 'main')}" fill="none" stroke="{line}" stroke-width="{halo_w}" opacity=".10" stroke-linecap="round"/>
  <path d="{svg_path(cfg, 'main')}" fill="none" stroke="url(#{w})" stroke-width="{wide}" stroke-linecap="round"/>
</svg>
'''


PREVIEW = '''<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>一叩 · 图标与命名</title>
<style>
  :root { --fg:#d5e0d8; --dim:#8c9c93; --line:rgba(180,210,196,.14); }
  * { box-sizing:border-box; }
  body { margin:0; background:#070a0b; color:var(--fg); font-family:"Songti SC","STSong","Noto Serif CJK SC",serif;
         -webkit-font-smoothing:antialiased; }
  .wrap { max-width:1080px; margin:0 auto; padding:56px 32px 80px; }
  .eyebrow { font:10px/1 -apple-system,sans-serif; letter-spacing:4px; color:var(--dim); opacity:.7; }
  h1 { font-size:34px; letter-spacing:14px; font-weight:400; margin:18px 0 14px; }
  h1 span { font:12px/1 -apple-system,sans-serif; letter-spacing:3px; color:var(--dim); margin-left:14px; }
  .lede { font-size:13px; line-height:2.1; letter-spacing:1px; color:var(--dim); margin:0 0 44px; }
  h2 { font-size:13px; letter-spacing:6px; font-weight:400; opacity:.55; margin:0 0 20px; }
  section { border-top:1px solid var(--line); padding-top:30px; margin-top:44px; }
  .hero { display:grid; grid-template-columns:340px 1fr; gap:40px; align-items:start; }
  .big svg { width:100%; height:auto; display:block; border-radius:20px; }
  .big figcaption { font:10px/1.6 -apple-system,sans-serif; color:var(--dim); opacity:.6; margin-top:12px; letter-spacing:1px; }
  .store-card { display:flex; align-items:center; gap:18px; padding:18px; border:1px solid var(--line);
                border-radius:14px; background:rgba(255,255,255,.02); }
  .store-icon { width:76px; height:76px; flex:none; border-radius:17px; overflow:hidden; }
  .store-icon svg { width:100%; height:100%; display:block; }
  .store-name { font-size:17px; letter-spacing:2px; }
  .store-name em { font:italic 12px -apple-system,sans-serif; opacity:.5; margin-left:8px; letter-spacing:0; }
  .store-sub { font-size:11px; color:var(--dim); margin-top:6px; letter-spacing:1px; }
  .store-cat { font:9px/1.6 -apple-system,sans-serif; color:var(--dim); opacity:.6; margin-top:8px; }
  .get { margin-left:auto; flex:none; font:11px -apple-system,sans-serif; color:#9fd8c2;
         border:1px solid rgba(159,216,194,.35); border-radius:20px; padding:6px 16px; }
  .sizes { display:grid; grid-template-columns:repeat(4,1fr); gap:16px; margin-top:26px; }
  .size { text-align:center; }
  .ph { width:100%; aspect-ratio:1; overflow:hidden; border-radius:20px; margin:0 auto 10px;
        border:1px solid var(--line); }
  .ph svg { width:100%; height:100%; display:block; }
  .ph.round { border-radius:50%; width:76%; }
  .ph.tiny { width:30%; border-radius:50%; }
  .size span { font:9px/1.5 -apple-system,sans-serif; color:var(--dim); opacity:.7; letter-spacing:.5px; }
  table { width:100%; border-collapse:collapse; font-size:12px; }
  td { padding:12px 10px; border-bottom:1px solid var(--line); vertical-align:top; line-height:1.8; }
  td:first-child { width:130px; color:var(--dim); letter-spacing:2px; white-space:nowrap; }
  td b { font-weight:400; font-size:15px; letter-spacing:2px; }
  td small { display:block; font:10px/1.7 -apple-system,sans-serif; color:var(--dim); opacity:.75; margin-top:3px; }
  .warn { margin-top:24px; padding:16px 18px; border-left:2px solid rgba(214,178,118,.6);
          background:rgba(214,178,118,.05); font-size:12px; line-height:2; letter-spacing:.5px; }
  .warn strong { color:#e2c391; font-weight:400; }
  .cols { display:grid; grid-template-columns:1fr 1fr; gap:36px; }
  ul { margin:0; padding-left:18px; font-size:11px; line-height:2.1; color:var(--dim); }
  ul li::marker { color:#7fae9c; }
  .files { font:10px/2 ui-monospace,Menlo,monospace; color:var(--dim); margin-top:22px; opacity:.75; }
  @media (max-width:820px) { .hero,.cols { grid-template-columns:1fr; } .sizes { grid-template-columns:repeat(2,1fr); } }
</style></head><body><div class="wrap">
  <div class="eyebrow">ICON CONCEPT · 图标概念</div>
  <h1>一 叩 <span>ONE KNOCK</span></h1>
  <p class="lede">一枚指腹的墨痕将落未落，一整片水线在它下方被叩出一列行波，向两侧散尽。<br>
     没有同心圆、没有边框、没有文字 —— 缩到 24px，也只剩「一个点、一道波」。<br>
     视觉与 App 里的连续高度场同源：波是一整片水，不是一圈圈描出来的涟漪。</p>

  <div class="hero">
    <figure class="big">__MAIN__<figcaption>app-icon-1024.png · 墨池主版 · 1024×1024 RGB 无 alpha</figcaption></figure>
    <div>
      <div class="store-card">
        <div class="store-icon">__STORE__</div>
        <div>
          <div class="store-name">叩音 <em>Stillwave</em></div>
          <div class="store-sub">一叩一应 · 腕上的片刻安静</div>
          <div class="store-cat">健康与健身 · 4+ · 一次购买，iPhone 与 Apple Watch 通用</div>
        </div>
        <div class="get">获取</div>
      </div>
      <div class="sizes">
        <div class="size"><div class="ph">__IPHONE__</div><span>iPhone 主屏 · 60px</span></div>
        <div class="size"><div class="ph round">__WATCH1__</div><span>Watch 表盘 · 系统裁圆</span></div>
        <div class="size"><div class="ph tiny">__WATCH2__</div><span>复杂功能 · 24px</span></div>
        <div class="size"><div class="ph">__PAPER__</div><span>宣纸变体 · 浅色对照</span></div>
      </div>
    </div>
  </div>

  <section><h2>命 名</h2>
    <table>
      <tr><td>图标概念名</td><td><b>一叩 / One Knock</b><small>只用于设计说明与宣传物料，不作为商店名</small></td></tr>
      <tr><td>中文名（现行）</td><td><b>叩音</b><small>2 字，出自《文赋》「叩寂寞而求音」；命名说明见下方</small></td></tr>
      <tr><td>英文名</td><td><b>Stillwave</b><small>still 静 + wave 波；造词可读、可注册，避开 Knock Water 的直译与 knock on wood 联想</small></td></tr>
      <tr><td>中文副标题</td><td><b>一叩一应 · 腕上的片刻安静</b><small>14 字，限额 30 字</small></td></tr>
      <tr><td>英文副标题</td><td><b>A knock, a wave, stillness</b><small>26 字符，限额 30 字符</small></td></tr>
      <tr><td>描述首句</td><td><b>一池静水，等你轻轻叩一下。</b><small>前三行决定转化；不写疗效、不写「治疗焦虑 / 改善睡眠 / 调理五脏」</small></td></tr>
      <tr><td>关键词（中）</td><td>冥想,正念,呼吸,放松,专注,减压,静心,五音,白噪音<small>100 字节上限，逗号分隔；不与名称重复</small></td></tr>
      <tr><td>关键词（英）</td><td>meditation,mindfulness,calm,breathing,haptic,unwind,focus<small>本地化元数据单独填写</small></td></tr>
    </table>
    <div class="warn"><strong>命名已定 · 叩音</strong><br>
      中文名 <strong>叩音</strong>（kòu yīn）取自陆机《文赋》「课虚无以责有，叩寂寞而求音」末二字：
      静里一叩，才有音；既点出五音与触觉乐谱，也避开了旧名的谐音风险。
      英文名 <strong>Stillwave</strong> 不变：中文说「音」，英文说「静与波」。两端产品名都已是单行常量，改一个词即可全站生效。
      另外「叩音」与 Stillwave 都必须在 App Store Connect 正式查重，并检查商标与同名 App。</div>
  </section>

  <section><h2>交 付 资 产 与 上 架 要 点</h2>
    <div class="cols">
      <ul>
        <li>图标 1024×1024 PNG：正方形、无透明通道、无圆角，系统自动加遮罩</li>
        <li><b>Watch target 需要独立的 AppIcon 资源</b>，缺了上传直接被拒</li>
        <li>iPhone 6.9″ 截图必填；Apple Watch 截图在 App Store Connect 的 Watch 标签页单独上传</li>
        <li>截图必须是真实界面，不能是营销合成图</li>
        <li>名称 30 字 / 副标题 30 字 / 关键词 100 字节 / 宣传文本 170 字</li>
      </ul>
      <ul>
        <li>PrivacyInfo.xcprivacy 隐私清单必填；隐私政策 URL、支持 URL 必填</li>
        <li>第一版建议<b>不接 HealthKit</b>：不读心率就不用 purpose string、不用健康数据披露，审核最轻</li>
        <li>工程用「iOS App with Watch App」，勾选 Supports Running Without iOS App Installation，Universal Purchase 一次购买两端</li>
        <li>Watch bundle ID 必须以 iOS bundle ID 为前缀</li>
        <li>审核备注里说明 mindfulness 场景与 WKExtendedRuntimeSession 的用途，避免被判滥用后台模式</li>
      </ul>
    </div>
    <div class="files">app-icon.svg（矢量源） · app-icon-1024.png · app-icon-paper-1024.png · app-icon-watch-1024.png · make_icons.py（可复现生成）</div>
  </section>
</div></body></html>
'''


def write_svg(path, cfg):
    with open(path, "w", encoding="utf-8") as f:
        f.write(svg_markup(cfg, "s"))


def write_preview():
    def mk(name, uid):
        return svg_markup(CFG[name], uid)
    html = (PREVIEW
            .replace("__MAIN__", mk("dark", "a"))
            .replace("__STORE__", mk("dark", "b"))
            .replace("__IPHONE__", mk("dark", "c"))
            .replace("__WATCH1__", mk("watch", "d"))
            .replace("__WATCH2__", mk("watch", "e"))
            .replace("__PAPER__", mk("paper", "f")))
    with open(os.path.join(OUT, "icon-preview.html"), "w", encoding="utf-8") as f:
        f.write(html)


def main():
    for name, cfg in CFG.items():
        rows = build_rows(cfg)
        suffix = {"dark": "", "paper": "-paper", "watch": "-watch"}[name]
        path = os.path.join(OUT, "app-icon%s-1024.png" % suffix)
        size = write_png(path, rows)
        print("%-28s %6.1f KB" % (os.path.basename(path), size / 1024))
    write_svg(os.path.join(OUT, "app-icon.svg"), CFG["dark"])
    write_preview()
    print("app-icon.svg / icon-preview.html  矢量源与预览")
    print("\n规范检查：1024×1024 / color type 2 (RGB，无 alpha) / 无圆角 / sRGB chunk 已写入")


if __name__ == "__main__":
    main()
