"""P2-3 一次性脚本：把 lib/ 内所有 `import '../...';` 形式的相对导入
改写为 `import 'package:yueyou/...';` 形式。

用法：
    python scripts/fix_relative_imports.py

执行后请手动 `flutter analyze` 并 `flutter test` 验证；脚本会跳过已是 package URI 的导入。
本脚本只在仓库内 lib/ 路径下生效，不修改 test/ 等目录。
"""
from __future__ import annotations

import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LIB = ROOT / "lib"
PACKAGE = "yueyou"

IMPORT_RE = re.compile(r"""^(\s*import\s+['"])(\.{1,2}/[^'"]+)(['"];)""", re.M)


def to_package_uri(file_path: Path, rel: str) -> str | None:
    """把 `../../core/x.dart` 转换为 `package:yueyou/core/x.dart`。"""
    base = file_path.parent
    target = (base / rel).resolve()
    try:
        rel_to_lib = target.relative_to(LIB)
    except ValueError:
        # 目标不在 lib/ 下，保留原相对导入
        return None
    return f"package:{PACKAGE}/{rel_to_lib.as_posix()}"


def fix_file(file_path: Path) -> int:
    text = file_path.read_text(encoding="utf-8")
    changes = 0

    def _replace(m: re.Match[str]) -> str:
        nonlocal changes
        prefix, rel, suffix = m.group(1), m.group(2), m.group(3)
        new_uri = to_package_uri(file_path, rel)
        if new_uri is None:
            return m.group(0)
        changes += 1
        return f"{prefix}{new_uri}{suffix}"

    new_text = IMPORT_RE.sub(_replace, text)
    if changes:
        file_path.write_text(new_text, encoding="utf-8")
    return changes


def main() -> int:
    if not LIB.is_dir():
        print(f"❌ 找不到 lib/ 目录: {LIB}", file=sys.stderr)
        return 1
    total_files = 0
    total_changes = 0
    for dirpath, _dirs, files in os.walk(LIB):
        for name in files:
            if not name.endswith(".dart"):
                continue
            path = Path(dirpath) / name
            n = fix_file(path)
            if n > 0:
                total_files += 1
                total_changes += n
                print(f"  ✓ {path.relative_to(ROOT).as_posix()}: {n} 处改写")
    print(f"\n✅ 完成：{total_files} 个文件 / {total_changes} 处导入改写。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
