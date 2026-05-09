# -*- coding: utf-8 -*-
"""阅游聚焦覆盖率验证脚本

目标：解决全量 `flutter test --coverage` 慢（30s+）+ 全量门禁阻塞的问题。
- 只跑指定 test 目录（默认全量但提供过滤入口）
- 解析 coverage/lcov.info，**仅打印目标 lib 文件**的覆盖率
- 与历史快照对比（可选 --baseline），快速看出本次改动的覆盖率涨跌

用法：
    # 只关注 reader_provider 与 tts_audio_notifier
    python scripts/coverage_focus.py \\
        --test test/features/reader/ test/features/audio/ \\
        --files lib/features/reader/providers/reader_provider.dart \\
                lib/features/audio/providers/tts_audio_notifier.dart

    # 仅解析现有 lcov.info（不重新跑测试）
    python scripts/coverage_focus.py \\
        --files lib/features/audio/providers/tts_audio_notifier.dart \\
        --no-run

    # 与历史快照对比
    python scripts/coverage_focus.py --baseline coverage/baseline.json
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

LCOV = Path('coverage/lcov.info')
DEFAULT_FILES = [
    'lib/features/audio/providers/tts_audio_notifier.dart',
    'lib/features/audio/services/tts_engine_service.dart',
    'lib/features/reader/providers/reader_provider.dart',
    'lib/features/library/services/file_import_service.dart',
    'lib/features/library/providers/bookshelf_provider.dart',
    'lib/features/game_2048/providers/game_provider.dart',
    'lib/core/database/storage_service.dart',
]


def _normalize(p: str) -> str:
    return p.replace('\\', '/').lower()


def _parse_lcov(target_files: list[str]) -> dict[str, dict[str, int]]:
    """解析 lcov.info，仅返回 target_files 涉及的文件覆盖率统计。"""
    if not LCOV.exists():
        raise SystemExit(f'未找到 {LCOV}，请先以 --coverage 跑测试。')
    targets = {_normalize(t) for t in target_files}
    out: dict[str, dict[str, int]] = {}
    in_block: str | None = None
    hit, total = 0, 0
    with LCOV.open('r', encoding='utf-8') as f:
        for raw in f:
            line = raw.strip()
            if line.startswith('SF:'):
                cur = _normalize(line[3:])
                in_block = cur if cur in targets else None
                hit, total = 0, 0
            elif in_block and line.startswith('DA:'):
                _, hits = line[3:].split(',', 1)
                total += 1
                if int(hits) > 0:
                    hit += 1
            elif line == 'end_of_record' and in_block:
                out[in_block] = {'hit': hit, 'total': total}
                in_block = None
    return out


def _run_tests(test_paths: list[str], concurrency: int) -> int:
    cmd = [
        'flutter', 'test',
        *test_paths,
        '--coverage',
        f'--concurrency={concurrency}',
        '--reporter', 'compact',
    ]
    print(f'[focus] 命令: {" ".join(cmd)}', flush=True)
    t0 = time.time()
    proc = subprocess.run(cmd, shell=True)
    print(f'[focus] 测试耗时: {time.time() - t0:.2f}s  exit={proc.returncode}', flush=True)
    return proc.returncode


def _print_coverage(data: dict[str, dict[str, int]], baseline: dict | None) -> None:
    print('\n## 聚焦覆盖率')
    print(f'{"文件":<70} {"覆盖率":>10} {"行数":>10} {"对比":>10}')
    print('-' * 102)
    for path in sorted(data.keys()):
        v = data[path]
        rate = (v['hit'] / v['total'] * 100) if v['total'] else 0.0
        delta = ''
        if baseline and path in baseline:
            old_rate = baseline[path]['hit'] / baseline[path]['total'] * 100 \
                if baseline[path]['total'] else 0.0
            d = rate - old_rate
            if abs(d) >= 0.01:
                delta = f'{d:+.2f}pp'
        print(f'{path:<70} {rate:>9.2f}% {v["hit"]:>4}/{v["total"]:<5} {delta:>10}')


def _save_baseline(data: dict[str, dict[str, int]], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(data, ensure_ascii=False, indent=2),
        encoding='utf-8',
    )
    print(f'[focus] 已写入快照: {path}')


def main() -> int:
    parser = argparse.ArgumentParser(description='阅游聚焦覆盖率验证')
    parser.add_argument(
        '--test', nargs='*', default=['test/'],
        help='测试路径（目录/文件），默认 test/',
    )
    parser.add_argument(
        '--files', nargs='*', default=DEFAULT_FILES,
        help='只关心这些 lib 文件的覆盖率（多个）',
    )
    parser.add_argument(
        '--concurrency', type=int, default=8,
        help='flutter test 并发度（默认 8）',
    )
    parser.add_argument(
        '--no-run', action='store_true',
        help='跳过测试执行，只解析现有 lcov.info',
    )
    parser.add_argument(
        '--baseline', type=str, default=None,
        help='与指定基线 JSON 文件对比（可选）',
    )
    parser.add_argument(
        '--save-baseline', type=str, default=None,
        help='将本次结果保存为基线 JSON（如 coverage/baseline.json）',
    )
    args = parser.parse_args()

    if not args.no_run:
        rc = _run_tests(args.test, args.concurrency)
        if rc != 0:
            print('[focus] 测试失败，仍尝试解析覆盖率以便定位…', file=sys.stderr)

    data = _parse_lcov(args.files)
    if not data:
        print('[focus] 未在 lcov.info 中找到任何指定文件，请检查路径。', file=sys.stderr)
        return 2

    baseline = None
    if args.baseline:
        bp = Path(args.baseline)
        if bp.exists():
            baseline = json.loads(bp.read_text(encoding='utf-8'))
        else:
            print(f'[focus] 基线文件不存在: {bp}（跳过对比）', file=sys.stderr)

    _print_coverage(data, baseline)

    if args.save_baseline:
        _save_baseline(data, Path(args.save_baseline))

    return 0


if __name__ == '__main__':
    raise SystemExit(main())
