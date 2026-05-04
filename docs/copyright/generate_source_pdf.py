from __future__ import annotations

from datetime import date
from pathlib import Path
from typing import Iterable
import re

from fpdf import FPDF

ROOT = Path(__file__).resolve().parents[2]
LIB_DIR = ROOT / "lib"
OUT_DIR = ROOT / "docs" / "copyright"
OUT_FILE = OUT_DIR / "源代码.pdf"
SOFTWARE_NAME = "阅游 V1.1"
APPLICANT = "【申请人姓名】"
LINES_PER_PAGE = 50
TOTAL_PAGES = 60
FONT_SIZE = 8
FONT_CANDIDATES = [
    Path("C:/Windows/Fonts/simhei.ttf"),
    Path("C:/Windows/Fonts/msyh.ttc"),
    Path("C:/Windows/Fonts/simsun.ttc"),
]
EMOJI_PATTERN = re.compile(
    "["
    "\\U0001F300-\\U0001FAFF"
    "\\U00002700-\\U000027BF"
    "\\U00002600-\\U000026FF"
    "\\uFE0F"
    "]+"
)


def _ordered_files() -> list[Path]:
    files = sorted(LIB_DIR.rglob("*.dart"), key=lambda p: p.as_posix())
    main_file = LIB_DIR / "main.dart"
    if main_file in files:
        files.remove(main_file)
        files.insert(0, main_file)
    return files


def _collect_lines(files: Iterable[Path]) -> list[str]:
    lines: list[str] = []
    for file in files:
        relative = file.relative_to(ROOT).as_posix()
        lines.append(f"// ===== 文件：{relative} =====")
        content = file.read_text(encoding="utf-8", errors="replace").splitlines()
        for index, line in enumerate(content, start=1):
            stripped = line.rstrip()
            if stripped:
                lines.append(f"{index:04d}  {stripped}")
        lines.append("")
    return lines


def _slice_pages(lines: list[str]) -> list[list[str]]:
    page_capacity = LINES_PER_PAGE
    needed = TOTAL_PAGES * page_capacity
    half = needed // 2
    head = lines[:half]
    tail = lines[-half:] if len(lines) >= half else lines
    material = (head + tail)[:needed]
    pages: list[list[str]] = []
    for index in range(0, needed, page_capacity):
        page = material[index:index + page_capacity]
        while len(page) < page_capacity:
            page.append("")
        pages.append(page)
    return pages[:TOTAL_PAGES]


class SourcePdf(FPDF):
    def header(self) -> None:
        self.set_font("MicrosoftYaHei", "", 9)
        self.cell(0, 6, f"{SOFTWARE_NAME} 源代码鉴别材料  第 {self.page_no()} 页", align="C")
        self.ln(8)

    def footer(self) -> None:
        self.set_y(-12)
        self.set_font("MicrosoftYaHei", "", 8)
        self.cell(0, 6, f"申请人：{APPLICANT}    生成日期：{date.today().isoformat()}", align="C")


def _font_path() -> Path:
    for font in FONT_CANDIDATES:
        if font.exists():
            return font
    raise FileNotFoundError("未找到中文字体，请安装微软雅黑或宋体。")


def _sanitize_for_pdf(text: str) -> str:
    return EMOJI_PATTERN.sub("", text).replace("•", "-")


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    files = _ordered_files()
    lines = _collect_lines(files)
    pages = _slice_pages(lines)

    pdf = SourcePdf(format="A4")
    font_path = _font_path()
    pdf.add_font("MicrosoftYaHei", "", str(font_path))
    pdf.set_auto_page_break(auto=False)
    pdf.set_margins(left=12, top=12, right=12)

    for page in pages:
        pdf.add_page()
        pdf.set_font("MicrosoftYaHei", "", FONT_SIZE)
        for line in page:
            pdf.cell(0, 4.9, _sanitize_for_pdf(line[:100]), new_x="LMARGIN", new_y="NEXT")

    pdf.output(str(OUT_FILE))
    print(f"已生成：{OUT_FILE}")
    print(f"页数：{len(pages)}")


if __name__ == "__main__":
    main()
