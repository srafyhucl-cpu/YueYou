#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
将 xiyouji.json 转换为 OSS 章节 txt 文件 + catalog JSON
输出结构：
  output/chapters/xiyouji/001.txt ~ 100.txt   ← 上传到 OSS
  output/catalog/xiyouji_catalog.json          ← 供 GET /catalog 接口使用

OSS 目标路径约定：
  oss://bucket/books/chapters/xiyouji/001.txt
  oss://bucket/books/catalog/xiyouji_catalog.json

CDN 访问 URL：
  https://cdn.hclstudio.cn/books/chapters/xiyouji/001.txt
"""

import json
import os
import pathlib

# ── 配置 ──────────────────────────────────────────────────────────────────
INPUT_JSON = pathlib.Path(__file__).parent / "xiyouji.json"
OUTPUT_DIR = pathlib.Path(__file__).parent / "output"
CDN_BASE   = "https://cdn.hclstudio.cn/books"   # 修改为你的 CDN 域名
# ─────────────────────────────────────────────────────────────────────────


def main():
    with open(INPUT_JSON, encoding="utf-8") as f:
        book = json.load(f)

    chapters = book["Chapters"]

    chapter_dir = OUTPUT_DIR / "chapters" / "xiyouji"
    catalog_dir = OUTPUT_DIR / "catalog"
    chapter_dir.mkdir(parents=True, exist_ok=True)
    catalog_dir.mkdir(parents=True, exist_ok=True)

    catalog_items = []

    for idx, ch in enumerate(chapters):
        seq     = ch["Sequence"]          # 1-based
        title   = ch["Title"]
        content = ch["Content"]           # 字符串形式的 JSON 数组

        # Content 是 JSON 数组序列化后的字符串，每元素为一段落
        paragraphs = json.loads(content)
        text = "\n".join(p.strip() for p in paragraphs if p.strip())

        # 文件名：三位补零，1-indexed
        filename = f"{seq:03d}.txt"
        out_path = chapter_dir / filename
        out_path.write_text(text, encoding="utf-8")
        print(f"[{idx+1:3d}/100] {filename}  ({len(text)} chars)  {title[:20]}...")

        catalog_items.append({
            "title":      title,
            "lineIndex":  0,
            "cdnUrl":     f"{CDN_BASE}/chapters/xiyouji/{filename}"
        })

    # 生成 catalog JSON（供 GET /catalog 接口使用）
    catalog_payload = {
        "status":   "success",
        "chapters": [{"title": c["title"], "lineIndex": 0} for c in catalog_items]
    }
    catalog_path = catalog_dir / "xiyouji_catalog.json"
    catalog_path.write_text(
        json.dumps(catalog_payload, ensure_ascii=False, indent=2),
        encoding="utf-8"
    )
    print(f"\n✅ 转换完成！")
    print(f"   章节 txt : {chapter_dir}  ({len(chapters)} 个文件)")
    print(f"   目录 JSON: {catalog_path}")
    print(f"\n上传命令示例（阿里云 OSS CLI）：")
    print(f"  ossutil cp -r {chapter_dir} oss://your-bucket/books/chapters/xiyouji/ --acl public-read")
    print(f"  ossutil cp {catalog_path} oss://your-bucket/books/catalog/ --acl public-read")


if __name__ == "__main__":
    main()
