"""解析 coverage/lcov.info，按文件输出行覆盖率统计。

用法：
    python scripts/parse_lcov.py [--threshold 60]

输出三段：
    1. 全仓总覆盖率
    2. 按模块（lib/ 一级子目录）汇总覆盖率
    3. 单文件覆盖率（按覆盖率升序，便于发现短板）
"""
from __future__ import annotations

import argparse
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LCOV = ROOT / "coverage" / "lcov.info"


def parse_lcov(path: Path) -> list[dict]:
    """返回 [{file, lines_total, lines_hit}] 列表。"""
    records: list[dict] = []
    cur: dict | None = None
    for raw in path.read_text(encoding="utf-8").splitlines():
        if raw.startswith("SF:"):
            cur = {"file": raw[3:].strip(), "hit_lines": set(), "all_lines": set()}
        elif raw.startswith("DA:") and cur is not None:
            # DA:<line>,<count>
            line_str, _, count_str = raw[3:].partition(",")
            ln = int(line_str)
            count = int(count_str)
            cur["all_lines"].add(ln)
            if count > 0:
                cur["hit_lines"].add(ln)
        elif raw == "end_of_record" and cur is not None:
            cur["lines_total"] = len(cur["all_lines"])
            cur["lines_hit"] = len(cur["hit_lines"])
            del cur["all_lines"]
            del cur["hit_lines"]
            records.append(cur)
            cur = None
    return records


def normalize_path(file_path: str) -> str:
    """统一为相对仓库根的 posix 路径。"""
    p = Path(file_path)
    try:
        return p.relative_to(ROOT).as_posix()
    except ValueError:
        # lcov 里可能是绝对路径，也可能是相对的
        if file_path.startswith("lib/"):
            return file_path.replace("\\", "/")
        # 兜底：直接返回
        return file_path.replace("\\", "/")


def percent(hit: int, total: int) -> float:
    return 0.0 if total == 0 else hit * 100.0 / total


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--threshold", type=float, default=60.0,
                        help="低于该百分比视为'覆盖率不足'，默认 60")
    parser.add_argument("--top-low", type=int, default=30,
                        help="最低覆盖率前 N 个文件，默认 30")
    args = parser.parse_args()

    if not LCOV.exists():
        print(f"❌ 未找到 {LCOV}，请先执行 flutter test --coverage")
        return 1

    records = parse_lcov(LCOV)
    for r in records:
        r["file"] = normalize_path(r["file"])
        r["pct"] = percent(r["lines_hit"], r["lines_total"])

    # 仅保留 lib/ 的文件
    records = [r for r in records if r["file"].startswith("lib/")]

    total_total = sum(r["lines_total"] for r in records)
    total_hit = sum(r["lines_hit"] for r in records)

    print("=" * 80)
    print(f"全仓总覆盖率: {total_hit}/{total_total} = {percent(total_hit, total_total):.2f}%")
    print(f"覆盖文件数: {len(records)}")
    print("=" * 80)

    # 按 lib/ 一级子目录汇总
    by_module: dict[str, list[int]] = defaultdict(lambda: [0, 0])
    for r in records:
        parts = r["file"].split("/")
        if len(parts) >= 3:
            # lib/<feature>/<sub>/...
            mod = "/".join(parts[:3])  # lib/features/audio
        else:
            mod = "/".join(parts[:2])  # lib/main.dart 等
        by_module[mod][0] += r["lines_total"]
        by_module[mod][1] += r["lines_hit"]

    print("\n## 按模块汇总（按覆盖率升序）\n")
    print(f"{'模块':<60} {'命中/总':>16} {'覆盖率':>10}")
    print("-" * 90)
    for mod, (total, hit) in sorted(by_module.items(), key=lambda x: percent(x[1][1], x[1][0])):
        pct = percent(hit, total)
        marker = "⚠️ " if pct < args.threshold else "  "
        print(f"{marker}{mod:<58} {hit:>7}/{total:<7} {pct:>9.2f}%")

    # 最低覆盖率前 N 个文件
    print(f"\n## 覆盖率最低的 {args.top_low} 个文件\n")
    sorted_files = sorted(records, key=lambda r: (r["pct"], -r["lines_total"]))
    print(f"{'文件':<70} {'命中/总':>14} {'覆盖率':>10}")
    print("-" * 100)
    for r in sorted_files[:args.top_low]:
        marker = "⚠️ " if r["pct"] < args.threshold else "  "
        print(f"{marker}{r['file']:<68} {r['lines_hit']:>5}/{r['lines_total']:<6} {r['pct']:>9.2f}%")

    # 0 覆盖率文件
    zero = [r for r in records if r["lines_hit"] == 0 and r["lines_total"] > 0]
    if zero:
        print(f"\n## 完全未覆盖的文件（{len(zero)} 个）\n")
        for r in sorted(zero, key=lambda r: -r["lines_total"]):
            print(f"  - {r['file']} ({r['lines_total']} 行)")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
