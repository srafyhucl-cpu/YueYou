# -*- coding: utf-8 -*-
"""列出指定 lib 文件的未覆盖行号，帮助定位补测试重点。

用法：
    python scripts/uncovered_lines.py <相对 lib 路径，可多个>
示例：
    python scripts/uncovered_lines.py lib/features/audio/providers/tts_audio_notifier.dart
"""
from __future__ import annotations

import sys
from pathlib import Path

LCOV = Path('coverage/lcov.info')


def _normalize(p: str) -> str:
    return p.replace('\\', '/').lower()


def _collect_uncovered(target: str) -> list[int]:
    if not LCOV.exists():
        raise SystemExit(f'未找到 {LCOV}, 请先运行 flutter test --coverage')
    target = _normalize(target)
    lines: list[int] = []
    in_block = False
    with LCOV.open('r', encoding='utf-8') as f:
        for raw in f:
            line = raw.strip()
            if line.startswith('SF:'):
                in_block = _normalize(line[3:]) == target
            elif in_block and line.startswith('DA:'):
                ln, hits = line[3:].split(',', 1)
                if int(hits) == 0:
                    lines.append(int(ln))
            elif line == 'end_of_record':
                in_block = False
    return lines


def _ranges(nums: list[int]) -> list[str]:
    if not nums:
        return []
    out, start, prev = [], nums[0], nums[0]
    for n in nums[1:]:
        if n == prev + 1:
            prev = n
            continue
        out.append(f'{start}' if start == prev else f'{start}-{prev}')
        start = prev = n
    out.append(f'{start}' if start == prev else f'{start}-{prev}')
    return out


def main() -> int:
    if len(sys.argv) < 2:
        print('用法: python scripts/uncovered_lines.py <lib路径...>')
        return 1
    for target in sys.argv[1:]:
        nums = _collect_uncovered(target)
        print(f'\n## {target}  未覆盖 {len(nums)} 行')
        rngs = _ranges(nums)
        # 按 6 个/行排版
        for i in range(0, len(rngs), 6):
            print('  ' + ', '.join(rngs[i:i + 6]))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
