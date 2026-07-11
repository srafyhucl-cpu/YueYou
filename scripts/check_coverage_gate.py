"""CI 覆盖率强制门禁脚本（互联网大厂正式版本契约）。

用法：
    python scripts/check_coverage_gate.py --overall 80 --core 90

退出码：
    0 - 通过所有门槛
    1 - 任意门槛不达标（CI 应阻断 PR）

校验项：
    1. 全仓行覆盖率 >= --overall 阈值
    2. 核心文件清单中每个文件 >= --core 阈值
    3. 输出明细供 PR 评审

豁免（不计入分母）：
    - lib/**/*painter*.dart  纯绘制
    - lib/**/animation*.dart  纯动画
    - lib/core/constants/*.dart  常量
    - lib/core/config/*.dart  配置常量
    - lib/features/*/constants/*.dart  模块常量
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LCOV = ROOT / "coverage" / "lcov.info"

# 大厂正式标准核心文件清单（每个 >= --core 阈值）
CORE_FILES = [
    "lib/features/audio/providers/tts_audio_notifier.dart",
    "lib/features/audio/services/tts_engine_service.dart",
    "lib/features/audio/domain/tts_audio_buffer.dart",
    "lib/features/reader/providers/reader_provider.dart",
    "lib/features/reader/domain/text_parser.dart",
    "lib/features/game_2048/providers/game_provider.dart",
    "lib/core/database/storage_service.dart",
    "lib/features/library/services/file_import_service.dart",
    "lib/features/library/providers/bookshelf_provider.dart",
]

# 豁免文件 glob 模式
EXEMPT_PATTERNS = [
    "painter",
    "/animation",
    "/constants/",
    "/config/",
    "settings_texts",
]


def is_exempt(path: str) -> bool:
    return any(p in path for p in EXEMPT_PATTERNS)


def parse_lcov() -> list[dict]:
    if not LCOV.exists():
        print(f"[GATE] FATAL: 未找到 {LCOV}，请先 flutter test --coverage", file=sys.stderr)
        sys.exit(1)
    records: list[dict] = []
    cur: dict | None = None
    for raw in LCOV.read_text(encoding="utf-8").splitlines():
        if raw.startswith("SF:"):
            cur = {"file": raw[3:].strip(), "hit": set(), "all": set()}
        elif raw.startswith("DA:") and cur is not None:
            ln_str, _, count_str = raw[3:].partition(",")
            ln = int(ln_str)
            cur["all"].add(ln)
            if int(count_str) > 0:
                cur["hit"].add(ln)
        elif raw == "end_of_record" and cur is not None:
            records.append({
                "file": _normalize(cur["file"]),
                "lines_total": len(cur["all"]),
                "lines_hit": len(cur["hit"]),
            })
            cur = None
    return records


def _normalize(file_path: str) -> str:
    p = Path(file_path)
    try:
        return p.relative_to(ROOT).as_posix()
    except ValueError:
        return file_path.replace("\\", "/")


def percent(hit: int, total: int) -> float:
    return 0.0 if total == 0 else hit * 100.0 / total


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--overall", type=float, default=80.0,
                        help="整体行覆盖率门槛（默认 80%）")
    parser.add_argument("--core", type=float, default=90.0,
                        help="核心文件行覆盖率门槛（默认 90%）")
    parser.add_argument("--strict", action="store_true",
                        help="严格模式：豁免文件也参与统计")
    args = parser.parse_args()

    records = parse_lcov()
    # 仅保留 lib/ 路径 + 排除豁免
    filtered = [r for r in records
                if r["file"].startswith("lib/")
                and (args.strict or not is_exempt(r["file"]))]

    # 1. 全仓
    total_total = sum(r["lines_total"] for r in filtered)
    total_hit = sum(r["lines_hit"] for r in filtered)
    overall_pct = percent(total_hit, total_total)

    print("=" * 80)
    print(f"[GATE] 整体行覆盖率: {total_hit}/{total_total} = {overall_pct:.2f}% "
          f"(门槛 {args.overall}%)")

    failures: list[str] = []
    if overall_pct < args.overall:
        failures.append(f"  - 整体覆盖率 {overall_pct:.2f}% < {args.overall}%")

    # 2. 核心文件逐个校验
    print(f"\n[GATE] 核心文件覆盖率检查（门槛 {args.core}%）：")
    by_file = {r["file"]: r for r in records}
    for core in CORE_FILES:
        r = by_file.get(core)
        if r is None:
            print(f"  [SKIP] {core}: 未在 lcov 中出现（可能尚未被任何测试加载）")
            failures.append(f"  - {core} 未被任何测试覆盖")
            continue
        pct = percent(r["lines_hit"], r["lines_total"])
        marker = "[OK] " if pct >= args.core else "[FAIL]"
        print(f"  {marker} {core}: {r['lines_hit']}/{r['lines_total']} = {pct:.2f}%")
        if pct < args.core:
            failures.append(f"  - {core} {pct:.2f}% < {args.core}%")

    # 3. 输出最终结论
    print("=" * 80)
    if failures:
        print(f"[GATE] FAILED：{len(failures)} 个门槛不达标，CI 应阻断本次合并")
        for f in failures:
            print(f)
        return 1
    print("[GATE] PASSED：所有覆盖率门槛达标")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
