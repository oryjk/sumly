#!/usr/bin/env python3
"""
Generate Sumly (记金) v1.0.6 App Store screenshot suite (iPhone 6.7" & iPad Pro 12.9")
using Google Chrome headless rendering for pixel-accurate editorial dark-gold visuals.

Outputs:
  - iPhone 6.7" (1290 x 2796): <out_dir>/iphone/01.png ~ 06.png
  - iPad Pro 12.9" (2048 x 2732): <out_dir>/ipad/01.png ~ 06.png
  - Optional preview collages (iPhone App Store Search 3-up + 6-card strip, iPad 6-card strip)
"""

from __future__ import annotations

import argparse
import concurrent.futures
import html
import os
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

CHROME_BIN = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

DEFAULT_RAW_DIR = Path(
    "/Users/carlwang/.gemini/antigravity/brain/77e4602c-38ee-4d0a-9163-02d8952f541c/scratch/raw_screens"
)
DEFAULT_WIDGET_PATH = Path(
    "/Users/carlwang/.gemini/antigravity/brain/77e4602c-38ee-4d0a-9163-02d8952f541c/scratch/widget_medium.png"
)
DEFAULT_OUT_DIR = Path(
    "/Users/carlwang/projects/sumly/sumly_ios/build/app-store-screenshots-v106"
)
DEFAULT_PREVIEW_DIR = Path(
    "/Users/carlwang/.gemini/antigravity/brain/77e4602c-38ee-4d0a-9163-02d8952f541c/scratch"
)
DEFAULT_APP_ICON = Path(
    "/Users/carlwang/projects/sumly/sumly_ios/Sumly/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon1024.png"
)

# Exact logical viewport dimensions (rendered at --force-device-scale-factor=2)
DEVICE_SPECS: dict[str, dict[str, Any]] = {
    "iphone": {
        "css_w": 645,
        "css_h": 1398,
        "px_w": 1290,
        "px_h": 2796,
        "scale": 2,
    },
    "ipad": {
        "css_w": 1024,
        "css_h": 1366,
        "px_w": 2048,
        "px_h": 2732,
        "scale": 2,
    },
}


SLIDES: list[dict[str, Any]] = [
    {
        "out_name": "01.png",
        "raw_name": "03.png",
        "label": "01 · 持有与攒金盒",
        "theme": "vault-gold",
        "badge": "攒金专属账本",
        "title_line1": "买了黄金",
        "title_line2": "算清真实到手",
        "subtitle": "金条 · 金豆 · 金饰 · 积存金，每一克都心中有数",
        "card_type": "slide01",
    },
    {
        "out_name": "02.png",
        "raw_name": "01.png",
        "label": "02 · 行情与买入点位",
        "theme": "market-crimson",
        "badge": "买入点叠加走势",
        "title_line1": "每一笔买入",
        "title_line2": "直接画在走势上",
        "subtitle": "国内 Au99.99 / 伦敦金走势 · 保本线一眼看清",
        "card_type": "slide02",
    },
    {
        "out_name": "03.png",
        "raw_name": "06.png",
        "label": "03 · 黄金温度与美债压力",
        "theme": "aurora-macro",
        "badge": "黄金温度 × 美债压力",
        "title_line1": "独创温度计",
        "title_line2": "看清黄金大周期",
        "subtitle": "五维热度 × 美债财政压力，客观历史分位呈现",
        "card_type": "slide03",
    },
    {
        "out_name": "04.png",
        "raw_name": "04.png",
        "label": "04 · 透明拆解算法",
        "theme": "blueprint-amber",
        "badge": "透明拆解算法",
        "title_line1": "工费回收损耗",
        "title_line2": "一图拆解明白",
        "subtitle": "裸金成本、工费、纯度与回收折价透明可查",
        "card_type": "slide04",
    },
    {
        "out_name": "05.png",
        "raw_name": "05.png",
        "label": "05 · 攒金陪伴日历",
        "theme": "calendar-warmth",
        "badge": "攒金陪伴日历",
        "title_line1": "攒金陪伴日历",
        "title_line2": "见证长期积累",
        "subtitle": "每日盈亏热力 · 里程碑记录 · 脱敏海报分享",
        "card_type": "slide05",
    },
    {
        "out_name": "06.png",
        "raw_name": "02.png",
        "label": "06 · 极简记账与桌面组件",
        "theme": "spotlight-widget",
        "badge": "极简记账 × 桌面组件",
        "title_line1": "3 秒极简入库",
        "title_line2": "桌面随时看金价",
        "subtitle": "4 大形态一键选 · 支持桌面与锁屏实时小组件",
        "card_type": "slide06",
    },
]


def file_uri(path: Path) -> str:
    return path.resolve().as_uri()


def build_background_svg(theme: str, w: int, h: int) -> str:
    """Subtle editorial vector geometry unique to each slide's narrative."""
    if theme == "vault-gold":
        # Concentric golden vault rings + fine radial ticks
        cx, cy = int(w * 0.50), int(h * 0.56)
        r1, r2, r3 = int(w * 0.44), int(w * 0.62), int(w * 0.80)
        return f"""
        <svg class="bg-geo" viewBox="0 0 {w} {h}" fill="none" xmlns="http://www.w3.org/2000/svg">
          <defs>
            <linearGradient id="g1" x1="0" y1="0" x2="{w}" y2="{h}" gradientUnits="userSpaceOnUse">
              <stop offset="0%" stop-color="#FFE89E" stop-opacity="0.28"/>
              <stop offset="50%" stop-color="#D49B32" stop-opacity="0.08"/>
              <stop offset="100%" stop-color="#FFE89E" stop-opacity="0.22"/>
            </linearGradient>
          </defs>
          <circle cx="{cx}" cy="{cy}" r="{r1}" stroke="url(#g1)" stroke-width="1.2"/>
          <circle cx="{cx}" cy="{cy}" r="{r2}" stroke="url(#g1)" stroke-width="1" stroke-dasharray="6 10"/>
          <circle cx="{cx}" cy="{cy}" r="{r3}" stroke="url(#g1)" stroke-width="0.9" opacity="0.7"/>
          <line x1="0" y1="{int(h*0.26)}" x2="{w}" y2="{int(h*0.18)}" stroke="#FFE89E" stroke-opacity="0.09" stroke-width="1"/>
          <line x1="0" y1="{int(h*0.86)}" x2="{w}" y2="{int(h*0.74)}" stroke="#FFE89E" stroke-opacity="0.08" stroke-width="1"/>
        </svg>
        """
    if theme == "market-crimson":
        # Sweeping editorial market spline + faint grid + glowing crimson buy-point accents
        y_base = int(h * 0.58)
        return f"""
        <svg class="bg-geo" viewBox="0 0 {w} {h}" fill="none" xmlns="http://www.w3.org/2000/svg">
          <defs>
            <linearGradient id="lineG" x1="0" y1="0" x2="{w}" y2="0" gradientUnits="userSpaceOnUse">
              <stop offset="0%" stop-color="#E5B442" stop-opacity="0.03"/>
              <stop offset="35%" stop-color="#FFE48F" stop-opacity="0.28"/>
              <stop offset="75%" stop-color="#F27268" stop-opacity="0.24"/>
              <stop offset="100%" stop-color="#E5B442" stop-opacity="0.04"/>
            </linearGradient>
          </defs>
          <g stroke="#F5D78C" stroke-opacity="0.055" stroke-width="1">
            <line x1="0" y1="{int(h*0.32)}" x2="{w}" y2="{int(h*0.32)}"/>
            <line x1="0" y1="{int(h*0.44)}" x2="{w}" y2="{int(h*0.44)}"/>
            <line x1="0" y1="{int(h*0.56)}" x2="{w}" y2="{int(h*0.56)}"/>
            <line x1="0" y1="{int(h*0.68)}" x2="{w}" y2="{int(h*0.68)}"/>
            <line x1="0" y1="{int(h*0.80)}" x2="{w}" y2="{int(h*0.80)}"/>
          </g>
          <path d="M -20 {y_base + 110} C {int(w*0.22)} {y_base + 60}, {int(w*0.40)} {y_base - 90}, {int(w*0.64)} {y_base - 140} S {int(w*0.90)} {y_base - 230}, {w + 20} {y_base - 270}"
                stroke="url(#lineG)" stroke-width="2.2" fill="none"/>
          <path d="M -20 {y_base + 170} C {int(w*0.28)} {y_base + 140}, {int(w*0.52)} {y_base + 20}, {int(w*0.76)} {y_base - 40} S {int(w*0.95)} {y_base - 110}, {w + 20} {y_base - 140}"
                stroke="#E5B442" stroke-opacity="0.10" stroke-width="1.4" stroke-dasharray="5 7" fill="none"/>
          <circle cx="{int(w*0.10)}" cy="{y_base + 92}" r="4.5" fill="#F06A64" fill-opacity="0.55"/>
          <circle cx="{int(w*0.92)}" cy="{y_base - 238}" r="5.5" fill="#F06A64" fill-opacity="0.65"/>
          <circle cx="{int(w*0.92)}" cy="{y_base - 238}" r="14" stroke="#F06A64" stroke-opacity="0.25" stroke-width="1.2"/>
        </svg>
        """
    if theme == "aurora-macro":
        # Calibrated orbital telemetry rings echoing the thermometer & debt gauges
        cx, cy = int(w * 0.50), int(h * 0.52)
        r1, r2 = int(w * 0.46), int(w * 0.64)
        return f"""
        <svg class="bg-geo" viewBox="0 0 {w} {h}" fill="none" xmlns="http://www.w3.org/2000/svg">
          <defs>
            <linearGradient id="auroraArc" x1="0" y1="{cy}" x2="{w}" y2="{cy}" gradientUnits="userSpaceOnUse">
              <stop offset="0%" stop-color="#58C9F2" stop-opacity="0.34"/>
              <stop offset="38%" stop-color="#5FD99D" stop-opacity="0.26"/>
              <stop offset="70%" stop-color="#F6CE64" stop-opacity="0.34"/>
              <stop offset="100%" stop-color="#F2855C" stop-opacity="0.30"/>
            </linearGradient>
          </defs>
          <circle cx="{cx}" cy="{cy}" r="{r1}" stroke="url(#auroraArc)" stroke-width="1.6" stroke-dasharray="3 9"/>
          <circle cx="{cx}" cy="{cy}" r="{r2}" stroke="url(#auroraArc)" stroke-width="1.1" opacity="0.65"/>
          <path d="M {int(w*0.06)} {int(h*0.30)} A {int(w*0.58)} {int(w*0.58)} 0 0 1 {int(w*0.94)} {int(h*0.30)}"
                stroke="url(#auroraArc)" stroke-width="2" stroke-linecap="round" opacity="0.45"/>
        </svg>
        """
    if theme == "blueprint-amber":
        # Precision architectural blueprint grid + subtle ruler ticks along flanks
        step = 54 if w < 800 else 68
        vlines = "".join(
            f'<line x1="{x}" y1="0" x2="{x}" y2="{h}"/>'
            for x in range(step, w, step)
        )
        hlines = "".join(
            f'<line x1="0" y1="{y}" x2="{w}" y2="{y}"/>'
            for y in range(step, h, step)
        )
        ticks_l = "".join(
            f'<line x1="14" y1="{y}" x2="{26 if i % 4 == 0 else 20}" y2="{y}"/>'
            for i, y in enumerate(range(int(h * 0.28), int(h * 0.90), 22))
        )
        ticks_r = "".join(
            f'<line x1="{w - (26 if i % 4 == 0 else 20)}" y1="{y}" x2="{w - 14}" y2="{y}"/>'
            for i, y in enumerate(range(int(h * 0.28), int(h * 0.90), 22))
        )
        return f"""
        <svg class="bg-geo" viewBox="0 0 {w} {h}" fill="none" xmlns="http://www.w3.org/2000/svg">
          <g stroke="#F0C76B" stroke-opacity="0.042" stroke-width="1">
            {vlines}
            {hlines}
          </g>
          <g stroke="#F5D37E" stroke-opacity="0.22" stroke-width="1.2" stroke-linecap="round">
            {ticks_l}
            {ticks_r}
          </g>
        </svg>
        """
    if theme == "calendar-warmth":
        # Soft editorial calendar dot matrix on outer flanks
        dots = []
        cols = [28, 52, w - 52, w - 28] if w < 800 else [42, 74, 106, w - 106, w - 74, w - 42]
        for ci, x in enumerate(cols):
            for ri, y in enumerate(range(int(h * 0.30), int(h * 0.90), 34)):
                color = "#E87166" if (ci + ri) % 5 == 0 else ("#58C48A" if (ci + ri) % 7 == 0 else "#F4CF74")
                op = "0.26" if (ci + ri) % 5 == 0 else "0.14"
                dots.append(f'<circle cx="{x}" cy="{y}" r="2.2" fill="{color}" fill-opacity="{op}"/>')
        return f"""
        <svg class="bg-geo" viewBox="0 0 {w} {h}" fill="none" xmlns="http://www.w3.org/2000/svg">
          {''.join(dots)}
          <line x1="0" y1="{int(h*0.27)}" x2="{w}" y2="{int(h*0.27)}" stroke="#F5CE72" stroke-opacity="0.08" stroke-width="1"/>
        </svg>
        """
    # spotlight-widget
    cx, cy = int(w * 0.72), int(h * 0.78)
    return f"""
    <svg class="bg-geo" viewBox="0 0 {w} {h}" fill="none" xmlns="http://www.w3.org/2000/svg">
      <defs>
        <linearGradient id="spotG" x1="0" y1="0" x2="{w}" y2="{h}" gradientUnits="userSpaceOnUse">
          <stop offset="0%" stop-color="#FFE89E" stop-opacity="0.24"/>
          <stop offset="100%" stop-color="#D99C2B" stop-opacity="0.06"/>
        </linearGradient>
      </defs>
      <circle cx="{cx}" cy="{cy}" r="{int(w*0.36)}" stroke="url(#spotG)" stroke-width="1.3"/>
      <circle cx="{cx}" cy="{cy}" r="{int(w*0.52)}" stroke="url(#spotG)" stroke-width="1" stroke-dasharray="4 8"/>
      <line x1="{int(w*0.08)}" y1="{int(h*0.24)}" x2="{int(w*0.92)}" y2="{int(h*0.24)}" stroke="#FFE89E" stroke-opacity="0.07" stroke-width="1"/>
    </svg>
    """


def build_floating_elements(slide: dict[str, Any], device: str, widget_uri: str) -> str:
    """Build non-occluding frosted glass callout cards or the real widget overlay."""
    ctype = slide["card_type"]

    if ctype == "slide01":
        return """
        <div class="glass-card card-tr card-s01">
          <div class="gc-eyebrow">现在卖预计到手</div>
          <div class="gc-value gold-num">¥54,279</div>
          <div class="gc-pill-row">
            <span class="gc-profit-badge">真实盈亏 +4.76%</span>
          </div>
        </div>
        <div class="glass-pill pill-bl pill-s01">
          <span class="pill-dot gold-dot"></span>
          <span class="pill-text">超保本线</span>
          <span class="pill-num">+¥35.72/g</span>
        </div>
        """

    if ctype == "slide02":
        return """
        <div class="glass-card card-tr card-s02">
          <div class="gc-eyebrow">持仓保本线</div>
          <div class="gc-value gold-num">¥752.88<span class="gc-unit">/g</span></div>
          <div class="gc-legend">
            <span class="buy-dot"></span>
            <span>历史买入点位</span>
          </div>
        </div>
        """

    if ctype == "slide03":
        return """
        <div class="glass-card card-tr card-s03">
          <div class="s03-row">
            <span class="s03-dot dot-temp"></span>
            <span class="s03-label">黄金温度</span>
            <span class="s03-val val-temp">58.4°</span>
          </div>
          <div class="s03-divider"></div>
          <div class="s03-row">
            <span class="s03-dot dot-debt"></span>
            <span class="s03-label">美债压力</span>
            <span class="s03-val val-debt">73.5</span>
          </div>
        </div>
        """

    if ctype == "slide04":
        # iPhone raw 04 shows single-item breakeven ¥757.75/g; keep exact prescribed figure
        # (also consistent with the brief's unified callout copy).
        price = "¥757.75" if device == "iphone" else "¥746.63"
        return f"""
        <div class="glass-card card-tr card-s04">
          <div class="gc-eyebrow">每克保本价</div>
          <div class="gc-value gold-num">{price}<span class="gc-unit">/g</span></div>
          <div class="gc-sub">含工费与回收损耗</div>
        </div>
        """

    if ctype == "slide05":
        return """
        <div class="glass-card card-tr card-s05">
          <div class="gc-eyebrow-row">
            <span class="sparkle">✦</span>
            <span>陪伴第 129 天</span>
          </div>
          <div class="gc-sub-metric">
            <span class="gc-sub-k">本月预估</span>
            <span class="gc-sub-v profit-red">+¥561</span>
          </div>
        </div>
        """

    if ctype == "slide06":
        return f"""
        <div class="widget-float-wrap">
          <div class="widget-tag">
            <span class="widget-tag-dot"></span>
            <span>桌面实时小组件</span>
          </div>
          <div class="widget-shell">
            <img class="widget-img" src="{html.escape(widget_uri)}" alt="Sumly Widget"/>
          </div>
        </div>
        """

    return ""


def render_slide_html(
    slide: dict[str, Any],
    device: str,
    raw_path: Path,
    widget_path: Path,
) -> str:
    spec = DEVICE_SPECS[device]
    w, h = spec["css_w"], spec["css_h"]
    theme = slide["theme"]
    raw_uri = file_uri(raw_path)
    widget_uri = file_uri(widget_path)
    bg_svg = build_background_svg(theme, w, h)
    floating_html = build_floating_elements(slide, device, widget_uri)

    # Device shift for visual rhythm & overlay space
    shift_class = ""
    if slide["card_type"] in ("slide02", "slide04"):
        shift_class = "device-shift-slight"
    elif slide["card_type"] == "slide06":
        shift_class = "device-shift-widget"

    is_iphone = device == "iphone"
    device_markup = (
        f"""
        <div class="device-stage {shift_class}">
          <div class="iphone-chassis">
            <div class="hw-btn btn-action"></div>
            <div class="hw-btn btn-vol-up"></div>
            <div class="hw-btn btn-vol-dn"></div>
            <div class="hw-btn btn-power"></div>
            <div class="iphone-bezel">
              <div class="iphone-screen">
                <img src="{html.escape(raw_uri)}" alt="screen"/>
              </div>
              <div class="screen-glare"></div>
            </div>
          </div>
        </div>
        """
        if is_iphone
        else f"""
        <div class="device-stage {shift_class}">
          <div class="ipad-chassis">
            <div class="ipad-bezel">
              <div class="ipad-camera"></div>
              <div class="ipad-screen">
                <img src="{html.escape(raw_uri)}" alt="screen"/>
              </div>
              <div class="screen-glare"></div>
            </div>
          </div>
        </div>
        """
    )

    return f"""<!DOCTYPE html>
<html lang="zh-Hans">
<head>
<meta charset="utf-8"/>
<style>
  * {{
    box-sizing: border-box;
    margin: 0;
    padding: 0;
    -webkit-font-smoothing: antialiased;
    text-rendering: optimizeLegibility;
  }}

  html, body {{
    width: {w}px;
    height: {h}px;
    overflow: hidden;
    background: #0A0908;
    font-family: "PingFang SC", "-apple-system", "SF Pro Display", "Hiragino Sans GB", "Noto Sans SC", sans-serif;
    color: #FFFDF8;
  }}

  .canvas {{
    position: relative;
    width: {w}px;
    height: {h}px;
    overflow: hidden;
    background: #0A0908;
  }}

  /* =========================================================
     PER-SLIDE DISTINCT LUMINOUS EDITORIAL BACKDROPS
     ========================================================= */
  .bg-aura {{
    position: absolute;
    inset: 0;
    pointer-events: none;
  }}

  /* 01: Imperial Warm Champagne Gold Vault */
  .theme-vault-gold .bg-aura {{
    background:
      radial-gradient(ellipse 92% 48% at 50% 6%, rgba(252, 208, 102, 0.36) 0%, rgba(204, 142, 38, 0.13) 48%, rgba(10, 9, 8, 0) 80%),
      radial-gradient(ellipse 96% 58% at 50% 60%, rgba(242, 188, 72, 0.30) 0%, rgba(168, 112, 28, 0.12) 54%, rgba(10, 9, 8, 0) 82%),
      radial-gradient(ellipse 80% 34% at 20% 96%, rgba(252, 206, 98, 0.28) 0%, rgba(10, 9, 8, 0) 74%),
      linear-gradient(180deg, #1B150B 0%, #0F0C08 42%, #181209 100%);
  }}

  /* 02: Crimson-Gold Market Pulse */
  .theme-market-crimson .bg-aura {{
    background:
      radial-gradient(ellipse 84% 44% at 52% 8%, rgba(246, 192, 82, 0.30) 0%, rgba(10, 9, 8, 0) 74%),
      radial-gradient(ellipse 82% 54% at 88% 54%, rgba(242, 96, 88, 0.36) 0%, rgba(176, 56, 52, 0.14) 52%, rgba(10, 9, 8, 0) 80%),
      radial-gradient(ellipse 76% 50% at 12% 72%, rgba(236, 176, 64, 0.28) 0%, rgba(10, 9, 8, 0) 76%),
      radial-gradient(ellipse 84% 30% at 50% 98%, rgba(224, 138, 74, 0.24) 0%, rgba(10, 9, 8, 0) 74%),
      linear-gradient(180deg, #1A100D 0%, #100B0A 45%, #1B0F0C 100%);
  }}

  /* 03: Aurora Macro Spectrum x Warm Gold */
  .theme-aurora-macro .bg-aura {{
    background:
      radial-gradient(ellipse 78% 50% at 12% 40%, rgba(76, 204, 246, 0.34) 0%, rgba(44, 138, 178, 0.12) 52%, rgba(10, 9, 8, 0) 80%),
      radial-gradient(ellipse 72% 44% at 44% 24%, rgba(90, 222, 160, 0.24) 0%, rgba(10, 9, 8, 0) 74%),
      radial-gradient(ellipse 82% 54% at 88% 52%, rgba(250, 202, 88, 0.36) 0%, rgba(236, 128, 70, 0.15) 54%, rgba(10, 9, 8, 0) 82%),
      radial-gradient(ellipse 88% 34% at 50% 94%, rgba(242, 176, 78, 0.26) 0%, rgba(76, 188, 222, 0.12) 56%, rgba(10, 9, 8, 0) 84%),
      linear-gradient(180deg, #0E171C 0%, #0D1214 42%, #18120B 100%);
  }}

  /* 04: Champagne & Copper Precision Blueprint */
  .theme-blueprint-amber .bg-aura {{
    background:
      radial-gradient(ellipse 88% 46% at 48% 8%, rgba(252, 214, 126, 0.32) 0%, rgba(10, 9, 8, 0) 76%),
      radial-gradient(ellipse 86% 56% at 84% 48%, rgba(232, 148, 62, 0.34) 0%, rgba(154, 90, 32, 0.13) 54%, rgba(10, 9, 8, 0) 80%),
      radial-gradient(ellipse 78% 46% at 16% 82%, rgba(248, 202, 96, 0.30) 0%, rgba(10, 9, 8, 0) 76%),
      linear-gradient(180deg, #1B140C 0%, #120E09 48%, #1E150A 100%);
  }}

  /* 05: Warm Sunset Amber x Rose-Emerald Calendar Glow */
  .theme-calendar-warmth .bg-aura {{
    background:
      radial-gradient(ellipse 86% 44% at 50% 6%, rgba(250, 202, 94, 0.32) 0%, rgba(10, 9, 8, 0) 74%),
      radial-gradient(ellipse 76% 52% at 12% 56%, rgba(80, 208, 144, 0.28) 0%, rgba(40, 128, 84, 0.11) 52%, rgba(10, 9, 8, 0) 78%),
      radial-gradient(ellipse 80% 52% at 88% 62%, rgba(242, 108, 98, 0.32) 0%, rgba(174, 66, 58, 0.12) 54%, rgba(10, 9, 8, 0) 80%),
      radial-gradient(ellipse 86% 30% at 50% 98%, rgba(246, 192, 86, 0.28) 0%, rgba(10, 9, 8, 0) 76%),
      linear-gradient(180deg, #1A130C 0%, #110E0B 46%, #1B120D 100%);
  }}

  /* 06: Liquid Gold Dual Spotlight */
  .theme-spotlight-widget .bg-aura {{
    background:
      radial-gradient(ellipse 92% 44% at 48% 7%, rgba(255, 218, 122, 0.36) 0%, rgba(10, 9, 8, 0) 76%),
      radial-gradient(ellipse 80% 54% at 30% 58%, rgba(232, 174, 62, 0.28) 0%, rgba(10, 9, 8, 0) 78%),
      radial-gradient(ellipse 78% 48% at 80% 80%, rgba(255, 212, 96, 0.42) 0%, rgba(218, 148, 36, 0.18) 52%, rgba(10, 9, 8, 0) 80%),
      linear-gradient(180deg, #1E170B 0%, #110D09 46%, #201609 100%);
  }}

  .bg-geo {{
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    pointer-events: none;
  }}

  /* Ultra-subtle film grain to eliminate gradient banding */
  .bg-grain {{
    position: absolute;
    inset: 0;
    pointer-events: none;
    opacity: 0.035;
    background-image: url("data:image/svg+xml,%3Csvg viewBox='0 0 200 200' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.85' numOctaves='2' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E");
  }}

  /* =========================================================
     HEADER COPY BLOCK
     ========================================================= */
  .header {{
    position: relative;
    z-index: 10;
    display: flex;
    flex-direction: column;
    align-items: center;
    text-align: center;
    padding: { '40px 28px 0' if is_iphone else '38px 48px 0' };
  }}

  .badge-pill {{
    display: inline-flex;
    align-items: center;
    gap: 8px;
    padding: { '7px 18px' if is_iphone else '8px 22px' };
    border-radius: 999px;
    background: linear-gradient(180deg, rgba(252, 214, 118, 0.16) 0%, rgba(214, 158, 48, 0.08) 100%);
    border: 1px solid rgba(255, 224, 138, 0.36);
    box-shadow: inset 0 1px 0 rgba(255, 245, 214, 0.25), 0 8px 22px rgba(0, 0, 0, 0.35);
    font-size: { '19px' if is_iphone else '21px' };
    font-weight: 600;
    letter-spacing: 0.08em;
    color: #FBE096;
    margin-bottom: { '16px' if is_iphone else '14px' };
  }}

  .badge-diamond {{
    width: 7px;
    height: 7px;
    transform: rotate(45deg);
    background: linear-gradient(135deg, #FFF5CF 0%, #E5B442 100%);
    box-shadow: 0 0 10px rgba(255, 224, 132, 0.85);
    flex-shrink: 0;
  }}

  .hero-title {{
    display: flex;
    flex-direction: column;
    align-items: center;
    font-size: { '68px' if is_iphone else '74px' };
    font-weight: 800;
    line-height: 1.15;
    letter-spacing: -0.02em;
    white-space: nowrap;
  }}

  .title-l1 {{
    color: #FFFDF8;
    text-shadow: 0 6px 26px rgba(0, 0, 0, 0.5);
  }}

  .title-l2 {{
    background: linear-gradient(180deg, #FFF5CC 0%, #FFE89E 34%, #E5B442 82%, #D19926 100%);
    -webkit-background-clip: text;
    background-clip: text;
    color: transparent;
    filter: drop-shadow(0 6px 22px rgba(229, 180, 66, 0.30));
  }}

  .hero-sub {{
    margin-top: { '14px' if is_iphone else '12px' };
    font-size: { '21.5px' if is_iphone else '25.5px' };
    font-weight: 500;
    letter-spacing: 0.015em;
    color: rgba(250, 242, 226, 0.80);
    white-space: nowrap;
    text-shadow: 0 2px 12px rgba(0, 0, 0, 0.45);
  }}

  /* =========================================================
     DEVICE STAGE & METALLIC HARDWARE MOCKUPS
     ========================================================= */
  .device-stage {{
    position: absolute;
    left: 0;
    right: 0;
    top: { '332px' if is_iphone else '338px' };
    display: flex;
    justify-content: center;
    z-index: 15;
  }}

  .device-shift-slight {{
    transform: translateX({ '-14px' if is_iphone else '-18px' });
  }}

  .device-shift-widget {{
    transform: translateX({ '-34px' if is_iphone else '-56px' });
  }}

  /* iPhone 16 Pro Max Titanium Frame (Screen 474 x 1030 -> exact 1320:2868 ratio) */
  .iphone-chassis {{
    position: relative;
    padding: 3px;
    border-radius: 54px;
    background: linear-gradient(
      145deg,
      #786850 0%,
      #342D24 18%,
      #594D3B 42%,
      #1E1A15 68%,
      #4A4032 88%,
      #2A241D 100%
    );
    box-shadow:
      0 34px 92px rgba(0, 0, 0, 0.86),
      0 12px 32px rgba(0, 0, 0, 0.65),
      0 0 88px rgba(235, 182, 68, 0.16),
      inset 0 1px 1px rgba(255, 240, 200, 0.32);
  }}

  .theme-aurora-macro .iphone-chassis,
  .theme-aurora-macro .ipad-chassis {{
    box-shadow:
      0 34px 92px rgba(0, 0, 0, 0.86),
      0 12px 32px rgba(0, 0, 0, 0.65),
      -26px 0 82px rgba(72, 198, 240, 0.18),
      26px 0 82px rgba(246, 196, 84, 0.20),
      inset 0 1px 1px rgba(255, 245, 220, 0.30);
  }}

  .theme-market-crimson .iphone-chassis,
  .theme-market-crimson .ipad-chassis {{
    box-shadow:
      0 34px 92px rgba(0, 0, 0, 0.86),
      0 12px 32px rgba(0, 0, 0, 0.65),
      22px 10px 84px rgba(232, 92, 86, 0.18),
      -18px 0 72px rgba(235, 182, 68, 0.14),
      inset 0 1px 1px rgba(255, 238, 200, 0.30);
  }}

  .iphone-bezel {{
    position: relative;
    padding: 8px;
    border-radius: 51px;
    background: #080808;
    box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.06);
  }}

  .iphone-screen {{
    width: 472px;
    height: 1026px;
    border-radius: 44px;
    overflow: hidden;
    background: #121110;
    position: relative;
  }}

  .iphone-screen img {{
    display: block;
    width: 100%;
    height: 100%;
    object-fit: cover;
  }}

  /* Side Titanium Hardware Buttons */
  .hw-btn {{
    position: absolute;
    width: 3px;
    border-radius: 2px;
    background: linear-gradient(180deg, #6E604A 0%, #2D271F 50%, #5B4F3D 100%);
  }}
  .btn-action {{ left: -3px; top: 158px; height: 28px; }}
  .btn-vol-up {{ left: -3px; top: 214px; height: 54px; }}
  .btn-vol-dn {{ left: -3px; top: 282px; height: 54px; }}
  .btn-power  {{ right: -3px; top: 236px; height: 82px; }}

  /* iPad Pro 12.9" Titanium Frame (Screen 732 x 976 -> exact 3:4 ratio) */
  .ipad-chassis {{
    position: relative;
    padding: 3.5px;
    border-radius: 34px;
    background: linear-gradient(
      145deg,
      #786850 0%,
      #342D24 18%,
      #594D3B 44%,
      #1E1A15 70%,
      #4A4032 90%,
      #2A241D 100%
    );
    box-shadow:
      0 34px 96px rgba(0, 0, 0, 0.86),
      0 12px 34px rgba(0, 0, 0, 0.68),
      0 0 96px rgba(235, 182, 68, 0.16),
      inset 0 1px 1px rgba(255, 240, 200, 0.30);
  }}

  .ipad-bezel {{
    position: relative;
    padding: 13px;
    border-radius: 31px;
    background: #080808;
    box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.06);
  }}

  .ipad-camera {{
    position: absolute;
    top: 4.5px;
    left: 50%;
    transform: translateX(-50%);
    width: 5px;
    height: 5px;
    border-radius: 50%;
    background: #1C2026;
    box-shadow: inset 0 0 1px rgba(120, 170, 255, 0.35);
  }}

  .ipad-screen {{
    width: 732px;
    height: 976px;
    border-radius: 20px;
    overflow: hidden;
    background: #121110;
    position: relative;
  }}

  .ipad-screen img {{
    display: block;
    width: 100%;
    height: 100%;
    object-fit: cover;
  }}

  .screen-glare {{
    position: absolute;
    inset: 8px;
    border-radius: { '44px' if is_iphone else '20px' };
    pointer-events: none;
    background: linear-gradient(
      132deg,
      rgba(255, 244, 216, 0.065) 0%,
      rgba(255, 244, 216, 0.015) 22%,
      rgba(255, 255, 255, 0) 42%
    );
    box-shadow: inset 0 0 0 1px rgba(255, 238, 198, 0.07);
  }}

  /* =========================================================
     FLOATING FROSTED-GLASS CALLOUT CARDS (3D MAGAZINE DEPTH)
     ========================================================= */
  .glass-card {{
    position: absolute;
    z-index: 30;
    border-radius: { '20px' if is_iphone else '22px' };
    padding: { '14px 18px 15px' if is_iphone else '16px 22px 17px' };
    background: linear-gradient(
      148deg,
      rgba(40, 34, 26, 0.88) 0%,
      rgba(20, 17, 13, 0.94) 100%
    );
    backdrop-filter: blur(22px) saturate(145%);
    -webkit-backdrop-filter: blur(22px) saturate(145%);
    border: 1px solid rgba(255, 224, 146, 0.36);
    box-shadow:
      inset 0 1px 0 rgba(255, 248, 222, 0.30),
      0 22px 48px rgba(0, 0, 0, 0.72),
      0 0 34px rgba(235, 184, 68, 0.16);
    font-variant-numeric: tabular-nums;
  }}

  .card-tr {{
    right: { '14px' if is_iphone else '28px' };
    top: { '350px' if is_iphone else '364px' };
  }}

  /* Slide 01 specific: clean shoulder alignment, zero battery sliver, zero figure overlap */
  .card-s01 {{
    top: { '348px' if is_iphone else '360px' };
    min-width: { '198px' if is_iphone else '228px' };
  }}

  .gc-eyebrow {{
    font-size: { '13px' if is_iphone else '15px' };
    font-weight: 500;
    color: rgba(246, 236, 216, 0.76);
    letter-spacing: 0.02em;
    margin-bottom: 4px;
  }}

  .gc-value {{
    font-family: "SF Pro Display", "PingFang SC", -apple-system, sans-serif;
    font-size: { '30px' if is_iphone else '35px' };
    font-weight: 800;
    line-height: 1.1;
    letter-spacing: -0.02em;
  }}

  .gold-num {{
    background: linear-gradient(180deg, #FFF4C8 0%, #F7CE66 65%, #DFAA34 100%);
    -webkit-background-clip: text;
    background-clip: text;
    color: transparent;
  }}

  .gc-unit {{
    font-size: { '17px' if is_iphone else '20px' };
    font-weight: 600;
    margin-left: 2px;
  }}

  .gc-pill-row {{
    margin-top: 8px;
    display: flex;
  }}

  .gc-profit-badge {{
    display: inline-flex;
    align-items: center;
    padding: { '4px 10px' if is_iphone else '5px 12px' };
    border-radius: 999px;
    background: rgba(236, 94, 88, 0.18);
    border: 1px solid rgba(242, 114, 108, 0.42);
    color: #FF8882;
    font-size: { '13px' if is_iphone else '15px' };
    font-weight: 700;
    letter-spacing: 0.01em;
  }}

  /* Slide 01 bottom-left lightweight capsule (straddling lower-left bezel without blocking box items) */
  .glass-pill {{
    position: absolute;
    z-index: 30;
    display: inline-flex;
    align-items: center;
    gap: 7px;
    padding: { '10px 16px' if is_iphone else '12px 20px' };
    border-radius: 999px;
    background: linear-gradient(145deg, rgba(38, 32, 24, 0.90) 0%, rgba(19, 16, 12, 0.95) 100%);
    backdrop-filter: blur(18px);
    -webkit-backdrop-filter: blur(18px);
    border: 1px solid rgba(255, 224, 146, 0.36);
    box-shadow:
      inset 0 1px 0 rgba(255, 246, 218, 0.28),
      0 16px 36px rgba(0, 0, 0, 0.70),
      0 0 24px rgba(235, 184, 68, 0.16);
    font-variant-numeric: tabular-nums;
  }}

  .pill-bl {{
    left: { '16px' if is_iphone else '32px' };
    bottom: { '40px' if is_iphone else '64px' };
  }}

  .pill-dot {{
    width: 8px;
    height: 8px;
    border-radius: 50%;
    flex-shrink: 0;
  }}

  .gold-dot {{
    background: #F6CE64;
    box-shadow: 0 0 10px rgba(246, 206, 100, 0.9);
  }}

  .pill-text {{
    font-size: { '14px' if is_iphone else '16px' };
    font-weight: 500;
    color: rgba(248, 240, 224, 0.82);
  }}

  .pill-num {{
    font-family: "SF Pro Display", "PingFang SC", sans-serif;
    font-size: { '15.5px' if is_iphone else '18px' };
    font-weight: 700;
    color: #FBE090;
  }}

  /* Slide 02 floating card: cleanly below status bar in open dark canvas space */
  .card-s02 {{
    top: { '412px' if is_iphone else '396px' };
    min-width: { '194px' if is_iphone else '228px' };
  }}

  .gc-legend {{
    margin-top: 8px;
    display: inline-flex;
    align-items: center;
    gap: 7px;
    font-size: { '13.5px' if is_iphone else '15.5px' };
    font-weight: 600;
    color: rgba(255, 236, 232, 0.90);
  }}

  .buy-dot {{
    width: 9px;
    height: 9px;
    border-radius: 50%;
    background: #F26B64;
    box-shadow: 0 0 0 3px rgba(242, 107, 100, 0.25), 0 0 10px rgba(242, 107, 100, 0.85);
    flex-shrink: 0;
  }}

  /* Slide 03 lightweight dual-metric floating card */
  .card-s03 {{
    top: { '354px' if is_iphone else '362px' };
    padding: { '12px 16px' if is_iphone else '14px 20px' };
    border-color: rgba(154, 222, 238, 0.34);
    box-shadow:
      inset 0 1px 0 rgba(255, 255, 255, 0.24),
      0 18px 42px rgba(0, 0, 0, 0.72),
      -10px 0 28px rgba(72, 198, 240, 0.16),
      10px 0 28px rgba(246, 196, 84, 0.16);
    min-width: { '184px' if is_iphone else '216px' };
  }}

  .s03-row {{
    display: flex;
    align-items: center;
    gap: 8px;
  }}

  .s03-divider {{
    height: 1px;
    margin: 8px 0;
    background: linear-gradient(90deg, rgba(255,255,255,0.04), rgba(255,230,170,0.22), rgba(255,255,255,0.04));
  }}

  .s03-dot {{
    width: 8px;
    height: 8px;
    border-radius: 50%;
    flex-shrink: 0;
  }}

  .dot-temp {{
    background: linear-gradient(135deg, #5ED89E, #F6CE64);
    box-shadow: 0 0 10px rgba(94, 216, 158, 0.85);
  }}

  .dot-debt {{
    background: linear-gradient(135deg, #F6CE64, #F08252);
    box-shadow: 0 0 10px rgba(240, 130, 82, 0.85);
  }}

  .s03-label {{
    font-size: { '13.5px' if is_iphone else '15.5px' };
    font-weight: 500;
    color: rgba(246, 242, 232, 0.82);
  }}

  .s03-val {{
    margin-left: auto;
    font-family: "SF Pro Display", "PingFang SC", sans-serif;
    font-size: { '19px' if is_iphone else '22px' };
    font-weight: 800;
  }}

  .val-temp {{ color: #9CF0C2; }}
  .val-debt {{ color: #FFD076; }}

  /* Slide 04 floating card */
  .card-s04 {{
    top: { '348px' if is_iphone else '378px' };
    min-width: { '204px' if is_iphone else '232px' };
  }}

  .gc-sub {{
    margin-top: 7px;
    font-size: { '13px' if is_iphone else '15px' };
    font-weight: 500;
    color: rgba(248, 224, 168, 0.86);
    padding-top: 6px;
    border-top: 1px solid rgba(255, 224, 146, 0.16);
  }}

  /* Slide 05 floating card */
  .card-s05 {{
    top: { '348px' if is_iphone else '362px' };
    min-width: { '198px' if is_iphone else '224px' };
    padding: { '13px 17px 14px' if is_iphone else '15px 21px 16px' };
  }}

  .gc-eyebrow-row {{
    display: flex;
    align-items: center;
    gap: 6px;
    font-size: { '14.5px' if is_iphone else '16.5px' };
    font-weight: 700;
    color: #FBE096;
    margin-bottom: 8px;
  }}

  .sparkle {{
    color: #FFD76A;
    text-shadow: 0 0 10px rgba(255, 215, 106, 0.85);
  }}

  .gc-sub-metric {{
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    gap: 10px;
    padding-top: 7px;
    border-top: 1px solid rgba(255, 224, 146, 0.16);
  }}

  .gc-sub-k {{
    font-size: { '13px' if is_iphone else '15px' };
    color: rgba(246, 236, 216, 0.76);
  }}

  .profit-red {{
    font-family: "SF Pro Display", "PingFang SC", sans-serif;
    font-size: { '22px' if is_iphone else '26px' };
    font-weight: 800;
    color: #FF7B74;
  }}

  /* =========================================================
     SLIDE 06 REAL WIDGET LAYERED OVERLAY
     ========================================================= */
  .widget-float-wrap {{
    position: absolute;
    right: { '16px' if is_iphone else '30px' };
    bottom: { '136px' if is_iphone else '112px' };
    z-index: 35;
    display: flex;
    flex-direction: column;
    align-items: flex-end;
  }}

  .widget-tag {{
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: { '6px 14px' if is_iphone else '7px 16px' };
    margin-bottom: 10px;
    border-radius: 999px;
    background: linear-gradient(145deg, rgba(44, 36, 24, 0.92), rgba(22, 18, 12, 0.96));
    border: 1px solid rgba(255, 224, 146, 0.42);
    box-shadow: 0 10px 26px rgba(0, 0, 0, 0.65), 0 0 18px rgba(242, 192, 72, 0.22);
    font-size: { '13.5px' if is_iphone else '15.5px' };
    font-weight: 600;
    letter-spacing: 0.04em;
    color: #FCE29B;
  }}

  .widget-tag-dot {{
    width: 7px;
    height: 7px;
    border-radius: 50%;
    background: #F6CE64;
    box-shadow: 0 0 8px rgba(246, 206, 100, 0.95);
  }}

  .widget-shell {{
    width: { '348px' if is_iphone else '446px' };
    aspect-ratio: 1005 / 472;
    border-radius: { '28px' if is_iphone else '34px' };
    overflow: hidden;
    background: #1B1815;
    border: 1.5px solid rgba(255, 224, 142, 0.48);
    box-shadow:
      0 28px 66px rgba(0, 0, 0, 0.86),
      0 10px 26px rgba(0, 0, 0, 0.72),
      0 0 48px rgba(242, 192, 72, 0.28),
      inset 0 1px 0 rgba(255, 248, 220, 0.34);
    position: relative;
  }}

  .widget-img {{
    display: block;
    width: 100%;
    height: 100%;
    object-fit: cover;
    transform: scale(1.018);
  }}
</style>
</head>
<body>
  <div class="canvas theme-{theme}">
    <div class="bg-aura"></div>
    {bg_svg}
    <div class="bg-grain"></div>

    <header class="header">
      <div class="badge-pill">
        <span class="badge-diamond"></span>
        <span>{html.escape(slide["badge"])}</span>
      </div>
      <h1 class="hero-title">
        <span class="title-l1">{html.escape(slide["title_line1"])}</span>
        <span class="title-l2">{html.escape(slide["title_line2"])}</span>
      </h1>
      <p class="hero-sub">{html.escape(slide["subtitle"])}</p>
    </header>

    {device_markup}
    {floating_html}
  </div>
</body>
</html>
"""


def render_html_to_png(html_content: str, out_path: Path, css_w: int, css_h: int, scale: int = 2) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmpdir:
        html_file = Path(tmpdir) / "page.html"
        html_file.write_text(html_content, encoding="utf-8")
        cmd = [
            CHROME_BIN,
            "--headless=new",
            "--disable-gpu",
            "--hide-scrollbars",
            "--no-first-run",
            "--no-default-browser-check",
            "--disable-extensions",
            "--run-all-compositor-stages-before-draw",
            "--virtual-time-budget=1200",
            f"--window-size={css_w},{css_h}",
            f"--force-device-scale-factor={scale}",
            f"--screenshot={out_path}",
            html_file.resolve().as_uri(),
        ]
        subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def check_dimensions(path: Path) -> tuple[int, int]:
    out = subprocess.check_output(
        ["sips", "-g", "pixelWidth", "-g", "pixelHeight", str(path)],
        text=True,
    )
    w = h = 0
    for line in out.splitlines():
        line = line.strip()
        if line.startswith("pixelWidth:"):
            w = int(line.split(":")[1].strip())
        elif line.startswith("pixelHeight:"):
            h = int(line.split(":")[1].strip())
    return w, h


def build_iphone_preview(iphone_dir: Path, app_icon: Path, out_path: Path) -> None:
    """Create a combined preview: top App Store Search 3-up simulation + bottom 6-card full strip."""
    cards_html = []
    for s in SLIDES:
        img_uri = file_uri(iphone_dir / s["out_name"])
        cards_html.append(
            f"""
            <div class="strip-card">
              <div class="strip-frame">
                <img src="{html.escape(img_uri)}" alt="{html.escape(s['out_name'])}"/>
              </div>
              <div class="strip-caption">{html.escape(s['label'])}</div>
            </div>
            """
        )

    search_imgs = [file_uri(iphone_dir / SLIDES[i]["out_name"]) for i in range(3)]
    icon_uri = file_uri(app_icon) if app_icon.exists() else ""

    html_doc = f"""<!DOCTYPE html>
<html lang="zh-Hans">
<head>
<meta charset="utf-8"/>
<style>
  * {{ box-sizing: border-box; margin: 0; padding: 0; -webkit-font-smoothing: antialiased; }}
  html, body {{
    width: 1920px;
    height: 1220px;
    overflow: hidden;
    background: #0D0D0F;
    font-family: "PingFang SC", "-apple-system", "SF Pro Display", sans-serif;
    color: #F5F2EA;
  }}
  .wrap {{
    width: 1920px;
    height: 1220px;
    padding: 34px 44px;
    display: flex;
    flex-direction: column;
    gap: 28px;
    background: radial-gradient(ellipse 80% 45% at 50% 0%, rgba(235, 184, 68, 0.10), transparent 70%), #0D0D0F;
  }}
  .top-row {{
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 36px;
  }}
  .meta-block {{
    flex: 1;
  }}
  .meta-kicker {{
    font-size: 13px;
    font-weight: 700;
    letter-spacing: 0.14em;
    color: #E5B442;
    text-transform: uppercase;
    margin-bottom: 8px;
  }}
  .meta-title {{
    font-size: 30px;
    font-weight: 800;
    color: #FFFDF8;
    margin-bottom: 8px;
  }}
  .meta-sub {{
    font-size: 15px;
    color: rgba(245, 240, 228, 0.68);
    line-height: 1.5;
  }}

  /* Authentic iOS App Store Search Result Card (Dark Mode + Light Mode side by side) */
  .search-previews {{
    display: flex;
    gap: 24px;
  }}
  .store-card {{
    width: 456px;
    border-radius: 24px;
    padding: 18px 18px 16px;
    box-shadow: 0 18px 44px rgba(0,0,0,0.45);
  }}
  .store-dark {{
    background: #1C1C1E;
    border: 1px solid rgba(255,255,255,0.09);
    color: #FFFFFF;
  }}
  .store-light {{
    background: #FFFFFF;
    border: 1px solid rgba(0,0,0,0.08);
    color: #111113;
  }}
  .store-head {{
    display: flex;
    align-items: center;
    gap: 12px;
    margin-bottom: 14px;
  }}
  .store-icon {{
    width: 54px;
    height: 54px;
    border-radius: 13px;
    overflow: hidden;
    flex-shrink: 0;
    border: 1px solid rgba(255,224,146,0.22);
    background: #141210;
  }}
  .store-icon img {{ width: 100%; height: 100%; object-fit: cover; display: block; }}
  .store-info {{ flex: 1; min-width: 0; }}
  .store-name {{ font-size: 16px; font-weight: 700; line-height: 1.25; }}
  .store-desc {{ font-size: 12.5px; opacity: 0.65; margin-top: 2px; }}
  .store-stars {{ font-size: 11px; color: #F5B82E; margin-top: 3px; letter-spacing: 1px; }}
  .store-btn {{
    padding: 6px 18px;
    border-radius: 999px;
    font-size: 14px;
    font-weight: 700;
  }}
  .store-dark .store-btn {{ background: #2C2C2E; color: #0A84FF; }}
  .store-light .store-btn {{ background: #F2F2F7; color: #007AFF; }}
  .store-thumbs {{
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 9px;
  }}
  .store-thumb {{
    border-radius: 13px;
    overflow: hidden;
    aspect-ratio: 1290 / 2796;
    border: 1px solid rgba(128,128,128,0.22);
  }}
  .store-thumb img {{ width: 100%; height: 100%; object-fit: cover; display: block; }}
  .store-mode-tag {{
    text-align: center;
    font-size: 11.5px;
    margin-top: 10px;
    opacity: 0.55;
  }}

  /* 6-card full panorama strip */
  .strip-label {{
    font-size: 14px;
    font-weight: 600;
    color: rgba(245, 240, 228, 0.65);
    margin-bottom: -14px;
    letter-spacing: 0.04em;
  }}
  .strip-grid {{
    display: grid;
    grid-template-columns: repeat(6, 1fr);
    gap: 20px;
    flex: 1;
    align-items: start;
  }}
  .strip-card {{
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 10px;
  }}
  .strip-frame {{
    width: 100%;
    aspect-ratio: 1290 / 2796;
    border-radius: 18px;
    overflow: hidden;
    border: 1px solid rgba(255, 224, 146, 0.22);
    box-shadow: 0 18px 42px rgba(0, 0, 0, 0.55);
  }}
  .strip-frame img {{ width: 100%; height: 100%; object-fit: cover; display: block; }}
  .strip-caption {{
    font-size: 14px;
    font-weight: 600;
    color: rgba(250, 242, 226, 0.85);
  }}
</style>
</head>
<body>
  <div class="wrap">
    <div class="top-row">
      <div class="meta-block">
        <div class="meta-kicker">Sumly · 记金 · v1.0.6 App Store Visual Suite</div>
        <div class="meta-title">iPhone 6.7" 商店截图总览与搜索页 3 联缩略预览</div>
        <div class="meta-sub">
          精确输出规格：1290 × 2796 px（6 张全套）<br/>
          右侧模拟 App Store 深/浅双模式搜索卡片缩略比例，检验主标题 1 秒可读性与首三张视觉节奏。
        </div>
      </div>

      <div class="search-previews">
        <div class="store-card store-light">
          <div class="store-head">
            <div class="store-icon">{f'<img src="{html.escape(icon_uri)}"/>' if icon_uri else ''}</div>
            <div class="store-info">
              <div class="store-name">记金 Sumly - 黄金记账与实时金价</div>
              <div class="store-desc">攒金账本 · 真实保本价 · 黄金温度计</div>
              <div class="store-stars">★★★★★ <span style="opacity:.5;color:#555">5.0</span></div>
            </div>
            <div class="store-btn">获取</div>
          </div>
          <div class="store-thumbs">
            <div class="store-thumb"><img src="{html.escape(search_imgs[0])}"/></div>
            <div class="store-thumb"><img src="{html.escape(search_imgs[1])}"/></div>
            <div class="store-thumb"><img src="{html.escape(search_imgs[2])}"/></div>
          </div>
          <div class="store-mode-tag">App Store 搜索页 · 浅色模式预览</div>
        </div>

        <div class="store-card store-dark">
          <div class="store-head">
            <div class="store-icon">{f'<img src="{html.escape(icon_uri)}"/>' if icon_uri else ''}</div>
            <div class="store-info">
              <div class="store-name">记金 Sumly - 黄金记账与实时金价</div>
              <div class="store-desc">攒金账本 · 真实保本价 · 黄金温度计</div>
              <div class="store-stars">★★★★★ <span style="opacity:.55;color:#bbb">5.0</span></div>
            </div>
            <div class="store-btn">获取</div>
          </div>
          <div class="store-thumbs">
            <div class="store-thumb"><img src="{html.escape(search_imgs[0])}"/></div>
            <div class="store-thumb"><img src="{html.escape(search_imgs[1])}"/></div>
            <div class="store-thumb"><img src="{html.escape(search_imgs[2])}"/></div>
          </div>
          <div class="store-mode-tag">App Store 搜索页 · 深色模式预览</div>
        </div>
      </div>
    </div>

    <div class="strip-label">全套 6 张横排总览（01 ~ 06 · 1290 × 2796）</div>
    <div class="strip-grid">
      {''.join(cards_html)}
    </div>
  </div>
</body>
</html>
"""
    render_html_to_png(html_doc, out_path, css_w=1920, css_h=1220, scale=1)


def build_ipad_preview(ipad_dir: Path, out_path: Path) -> None:
    """Create a 6-card horizontal panorama strip for iPad Pro 12.9" screenshots."""
    cards_html = []
    for s in SLIDES:
        img_uri = file_uri(ipad_dir / s["out_name"])
        cards_html.append(
            f"""
            <div class="strip-card">
              <div class="strip-frame">
                <img src="{html.escape(img_uri)}" alt="{html.escape(s['out_name'])}"/>
              </div>
              <div class="strip-caption">{html.escape(s['label'])}</div>
            </div>
            """
        )

    html_doc = f"""<!DOCTYPE html>
<html lang="zh-Hans">
<head>
<meta charset="utf-8"/>
<style>
  * {{ box-sizing: border-box; margin: 0; padding: 0; -webkit-font-smoothing: antialiased; }}
  html, body {{
    width: 2160px;
    height: 620px;
    overflow: hidden;
    background: #0D0D0F;
    font-family: "PingFang SC", "-apple-system", "SF Pro Display", sans-serif;
    color: #F5F2EA;
  }}
  .wrap {{
    width: 2160px;
    height: 620px;
    padding: 32px 42px;
    display: flex;
    flex-direction: column;
    gap: 22px;
    background: radial-gradient(ellipse 80% 55% at 50% 0%, rgba(235, 184, 68, 0.10), transparent 72%), #0D0D0F;
  }}
  .head {{
    display: flex;
    align-items: baseline;
    justify-content: space-between;
  }}
  .head-title {{
    font-size: 26px;
    font-weight: 800;
    color: #FFFDF8;
  }}
  .head-spec {{
    font-size: 14px;
    font-weight: 600;
    color: #E5B442;
    letter-spacing: 0.06em;
  }}
  .strip-grid {{
    display: grid;
    grid-template-columns: repeat(6, 1fr);
    gap: 22px;
    flex: 1;
  }}
  .strip-card {{
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 10px;
  }}
  .strip-frame {{
    width: 100%;
    aspect-ratio: 2048 / 2732;
    border-radius: 16px;
    overflow: hidden;
    border: 1px solid rgba(255, 224, 146, 0.22);
    box-shadow: 0 18px 42px rgba(0, 0, 0, 0.55);
  }}
  .strip-frame img {{ width: 100%; height: 100%; object-fit: cover; display: block; }}
  .strip-caption {{
    font-size: 14.5px;
    font-weight: 600;
    color: rgba(250, 242, 226, 0.85);
  }}
</style>
</head>
<body>
  <div class="wrap">
    <div class="head">
      <div class="head-title">Sumly · 记金 v1.0.6 — iPad Pro 12.9" 商店截图全套总览（01 ~ 06）</div>
      <div class="head-spec">2048 × 2732 px · 6 SLIDES</div>
    </div>
    <div class="strip-grid">
      {''.join(cards_html)}
    </div>
  </div>
</body>
</html>
"""
    render_html_to_png(html_doc, out_path, css_w=2160, css_h=620, scale=1)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate Sumly App Store screenshots via Chrome headless.")
    parser.add_argument("--device", choices=["iphone", "ipad", "all"], default="all")
    parser.add_argument("--raw-dir", type=Path, default=DEFAULT_RAW_DIR)
    parser.add_argument("--widget", type=Path, default=DEFAULT_WIDGET_PATH)
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR)
    parser.add_argument("--preview-dir", type=Path, default=DEFAULT_PREVIEW_DIR)
    parser.add_argument("--app-icon", type=Path, default=DEFAULT_APP_ICON)
    parser.add_argument("--no-previews", action="store_true")
    parser.add_argument("--workers", type=int, default=4)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not Path(CHROME_BIN).exists():
        print(f"ERROR: Chrome not found at {CHROME_BIN}", file=sys.stderr)
        return 1

    devices = ["iphone", "ipad"] if args.device == "all" else [args.device]
    jobs: list[tuple[str, dict[str, Any], Path, Path]] = []

    for dev in devices:
        for slide in SLIDES:
            raw_path = args.raw_dir / dev / slide["raw_name"]
            if not raw_path.exists():
                print(f"ERROR: Missing raw screenshot: {raw_path}", file=sys.stderr)
                return 1
            out_path = args.out_dir / dev / slide["out_name"]
            jobs.append((dev, slide, raw_path, out_path))

    if not args.widget.exists():
        print(f"ERROR: Missing widget asset: {args.widget}", file=sys.stderr)
        return 1

    def _run_job(job: tuple[str, dict[str, Any], Path, Path]) -> tuple[str, Path, int, int]:
        dev, slide, raw_path, out_path = job
        spec = DEVICE_SPECS[dev]
        content = render_slide_html(slide, dev, raw_path, args.widget)
        render_html_to_png(content, out_path, spec["css_w"], spec["css_h"], spec["scale"])
        pw, ph = check_dimensions(out_path)
        return dev, out_path, pw, ph

    print(f"Rendering {len(jobs)} App Store screenshots using {args.workers} workers...")
    failed = False
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = [pool.submit(_run_job, j) for j in jobs]
        for fut in concurrent.futures.as_completed(futures):
            dev, out_path, pw, ph = fut.result()
            exp_w, exp_h = DEVICE_SPECS[dev]["px_w"], DEVICE_SPECS[dev]["px_h"]
            ok = (pw == exp_w and ph == exp_h)
            status = "OK" if ok else f"MISMATCH (expected {exp_w}x{exp_h})"
            print(f"  [{dev:6s}] {out_path.name}: {pw}x{ph}  {status}")
            if not ok:
                failed = True

    if failed:
        print("ERROR: One or more screenshots failed pixel dimension verification.", file=sys.stderr)
        return 2

    if not args.no_previews:
        if "iphone" in devices:
            p_iphone = args.preview_dir / "store_v106_iphone_preview.png"
            build_iphone_preview(args.out_dir / "iphone", args.app_icon, p_iphone)
            pw, ph = check_dimensions(p_iphone)
            print(f"  [preview] {p_iphone}: {pw}x{ph}")
        if "ipad" in devices:
            p_ipad = args.preview_dir / "store_v106_ipad_preview.png"
            build_ipad_preview(args.out_dir / "ipad", p_ipad)
            pw, ph = check_dimensions(p_ipad)
            print(f"  [preview] {p_ipad}: {pw}x{ph}")

    print("All done!")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
