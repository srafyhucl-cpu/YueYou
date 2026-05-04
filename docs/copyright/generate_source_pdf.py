from __future__ import annotations

from datetime import date
from pathlib import Path
import re

from fpdf import FPDF

ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "docs" / "copyright"
OUT_FILE = OUT_DIR / "源代码.pdf"
SOFTWARE_NAME = "阅游 V1.1.0"
APPLICANT = "胡传龙"
LINES_PER_PAGE = 50
TOTAL_PAGES = 60
FONT_SIZE = 8
SECTION_LINES = LINES_PER_PAGE * (TOTAL_PAGES // 2)
SOURCE_PATTERNS = [
    "lib/main.dart",
    "lib/core/config/*.dart",
    "lib/core/constants/*.dart",
    "lib/core/theme/*.dart",
    "lib/core/database/*.dart",
    "lib/core/utils/*.dart",
    "lib/features/reader/domain/*.dart",
    "lib/features/reader/providers/*.dart",
    "lib/features/reader/presentation/**/*.dart",
    "lib/features/audio/**/*.dart",
    "lib/features/library/**/*.dart",
    "lib/features/game/**/*.dart",
    "lib/features/settings/**/*.dart",
    "lib/shared/**/*.dart",
    "server/main.go",
    "server/config.go",
    "server/handler_tts.go",
    "server/handler_book.go",
    "server/handler_privacy.go",
]
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
    files: list[Path] = []
    seen: set[Path] = set()
    for pattern in SOURCE_PATTERNS:
        matches = sorted(ROOT.glob(pattern), key=lambda p: p.as_posix())
        for file in matches:
            if file.is_file() and file not in seen:
                files.append(file)
                seen.add(file)
    return files


def _read_source_lines(file: Path) -> list[str]:
    relative = file.relative_to(ROOT).as_posix()
    lines: list[str] = []
    lines.append(f"// ===== 文件：{relative} =====")
    content = file.read_text(encoding="utf-8", errors="replace").splitlines()
    for index, line in enumerate(content, start=1):
        stripped = line.rstrip()
        if stripped:
            lines.append(f"{index:04d}  {stripped}")
    lines.append(f"// ===== 文件结束：{relative} =====")
    lines.append("")
    return lines


def _collect_sections(files: list[Path]) -> list[str]:
    head: list[str] = []
    tail: list[str] = []
    for file in files:
        block = _read_source_lines(file)
        if len(head) + len(block) <= SECTION_LINES:
            head.extend(block)
        else:
            break
    for file in reversed(files):
        block = _read_source_lines(file)
        if len(tail) + len(block) <= SECTION_LINES:
            tail[0:0] = block
        else:
            break
    return _fit_section(head, "前 30 页连续源码") + _fit_section(tail, "后 30 页连续源码")


def _fit_section(lines: list[str], title: str) -> list[str]:
    fitted = [f"// ===== {title} ====="]
    fitted.extend(lines[: SECTION_LINES - 1])
    while len(fitted) < SECTION_LINES:
        fitted.append("//")
    return fitted[:SECTION_LINES]


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
    return EMOJI_PATTERN.sub("", text).replace("•", "-").replace("\t", "    ")


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    files = _ordered_files()
    lines = _collect_sections(files)
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
