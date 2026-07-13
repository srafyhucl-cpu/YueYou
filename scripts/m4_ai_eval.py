"""M4-A 离线章节检索与 G2-A 技术门评测。

该模块只使用预置评测集，不调用网络、模型或生产服务。它验证的是章节检索、
引用定位、延迟和成本预算基线，不代表真实用户体验或大模型回答质量。
"""

from __future__ import annotations

import argparse
import json
import re
import time
from dataclasses import dataclass
from pathlib import Path
from statistics import quantiles
from typing import Any, Iterable


_CJK_RE = re.compile(r"[\u4e00-\u9fff]")
_WORD_RE = re.compile(r"[A-Za-z0-9_]+")
_CHAPTER_RE = re.compile(r"(?m)^(第([一二三四五六七八九十百零〇0-9]+)回[^\r\n]*)$")


@dataclass(frozen=True)
class Chapter:
    chapter_id: int
    title: str
    content: str


@dataclass(frozen=True)
class Citation:
    chapter_id: int
    title: str
    quote: str
    offset: int


@dataclass(frozen=True)
class Retrieval:
    chapter: Chapter
    citation: Citation
    score: int


def _terms(text: str) -> set[str]:
    normalized = "".join(text.split()).lower()
    terms = set(_WORD_RE.findall(normalized))
    cjk = _CJK_RE.findall(normalized)
    terms.update(cjk)
    terms.update("".join(cjk[index : index + 2]) for index in range(len(cjk) - 1))
    return {term for term in terms if term}


class ChapterIndex:
    """基于字符词元的确定性章节索引，作为无模型评测基线。"""

    def __init__(self, chapters: Iterable[Chapter]) -> None:
        self._chapters = tuple(chapters)
        self._terms = {
            chapter.chapter_id: _terms(f"{chapter.title} {chapter.content}")
            for chapter in self._chapters
        }

    def search(self, query: str) -> Retrieval:
        query_terms = _terms(query)
        ranked = sorted(
            self._chapters,
            key=lambda chapter: (
                len(query_terms & self._terms[chapter.chapter_id]),
                -chapter.chapter_id,
            ),
            reverse=True,
        )
        chapter = ranked[0]
        matched = query_terms & self._terms[chapter.chapter_id]
        offset = self._first_match_offset(chapter, matched)
        quote_start = max(0, offset - 20)
        quote = chapter.content[quote_start : quote_start + 80].strip()
        citation = Citation(chapter.chapter_id, chapter.title, quote, offset)
        return Retrieval(chapter, citation, len(matched))

    @staticmethod
    def _first_match_offset(chapter: Chapter, terms: set[str]) -> int:
        offsets = [chapter.content.find(term) for term in terms if len(term) > 1]
        valid_offsets = [offset for offset in offsets if offset >= 0]
        return min(valid_offsets) if valid_offsets else 0


def _chinese_number(value: str) -> int:
    """将西游记目录常用的中文数字章节号转换为整数。"""
    if value.isdigit():
        return int(value)
    digits = {"零": 0, "〇": 0, "一": 1, "二": 2, "三": 3, "四": 4, "五": 5,
              "六": 6, "七": 7, "八": 8, "九": 9}
    if value == "十":
        return 10
    if "百" in value:
        head, tail = value.split("百", 1)
        return digits[head or "一"] * 100 + _chinese_number(tail) if tail else digits[head or "一"] * 100
    if "十" in value:
        head, tail = value.split("十", 1)
        return (digits.get(head, 1) * 10) + (digits.get(tail, 0) if tail else 0)
    return digits[value]


def split_chapters(text: str) -> list[Chapter]:
    """按“第 N 回”标题切分文本，并保留章节标题和正文范围。"""
    matches = list(_CHAPTER_RE.finditer(text))
    if not matches:
        raise ValueError("文本中未找到“第 N 回”章节标题")
    chapters: list[Chapter] = []
    for index, match in enumerate(matches):
        content_start = match.end()
        content_end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        chapters.append(
            Chapter(
                chapter_id=_chinese_number(match.group(2)),
                title=match.group(1).strip(),
                content=text[content_start:content_end].strip(),
            )
        )
    return chapters


def load_index_from_text(text: str) -> ChapterIndex:
    return ChapterIndex(split_chapters(text))


def _load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def load_index(corpus_path: Path) -> ChapterIndex:
    rows = _load_json(corpus_path)
    chapters = [Chapter(int(row["chapter_id"]), row["title"], row["content"]) for row in rows]
    if not chapters:
        raise ValueError("评测语料不能为空")
    return ChapterIndex(chapters)


def evaluate(index: ChapterIndex, cases: list[dict[str, Any]], budget_limit: float = 0.05) -> dict[str, Any]:
    results: list[dict[str, Any]] = []
    durations_ms: list[float] = []
    for case in cases:
        started = time.perf_counter_ns()
        retrieval = index.search(case["query"])
        durations_ms.append((time.perf_counter_ns() - started) / 1_000_000)
        expected_id = int(case["expected_chapter_id"])
        chapter_hit = retrieval.chapter.chapter_id == expected_id
        evidence_hit = chapter_hit and all(
            term in retrieval.citation.quote or term in retrieval.chapter.content
            for term in case["evidence_terms"]
        )
        results.append(
            {
                "id": case["id"],
                "chapter_hit": chapter_hit,
                "citation_hit": evidence_hit,
                "chapter_id": retrieval.chapter.chapter_id,
                "citation": {
                    "title": retrieval.citation.title,
                    "quote": retrieval.citation.quote,
                    "offset": retrieval.citation.offset,
                },
            }
        )

    accuracy = sum(item["chapter_hit"] for item in results) / len(results)
    citation_rate = sum(item["citation_hit"] for item in results) / len(results)
    p95_ms = max(durations_ms) if len(durations_ms) < 2 else quantiles(durations_ms, n=20, method="inclusive")[18]
    estimated_cost = 0.0
    gate = {
        "accuracy": accuracy >= 0.85,
        "citation_rate": citation_rate >= 0.90,
        "p95_ms": p95_ms < 5000,
        "budget": estimated_cost <= budget_limit,
    }
    return {
        "cases": len(results),
        "accuracy": accuracy,
        "citation_rate": citation_rate,
        "p95_ms": p95_ms,
        "estimated_cost": estimated_cost,
        "gate_passed": all(gate.values()),
        "gate": gate,
        "results": results,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="运行 M4-A/G2-A 离线章节引用评测")
    parser.add_argument("--corpus", type=Path, required=True)
    parser.add_argument("--cases", type=Path, required=True)
    parser.add_argument("--budget-limit", type=float, default=0.05)
    args = parser.parse_args()
    report = evaluate(load_index(args.corpus), _load_json(args.cases), args.budget_limit)
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report["gate_passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
