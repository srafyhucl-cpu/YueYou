from __future__ import annotations

from datetime import date
from pathlib import Path
import re

from fpdf import FPDF

ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "docs" / "copyright"
DOC_FILE = OUT_DIR / "阅游V1.1.0.md"
OUT_FILE = OUT_DIR / "阅游V1.1.0.pdf"
SOFTWARE_NAME = "阅游V1.1.0"
APPLICANT = "胡传龙"
LINES_PER_PAGE = 30
FONT_SIZE = 10
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


class DocumentPdf(FPDF):
    def header(self) -> None:
        self.set_font("MicrosoftYaHei", "", 9)
        self.cell(0, 6, f"{SOFTWARE_NAME} 文档鉴别材料  第 {self.page_no()} 页", align="C")
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


def _markdown_to_lines(text: str) -> list[str]:
    lines: list[str] = []
    for raw in text.splitlines():
        line = raw.strip()
        if not line:
            lines.append("")
            continue
        if line.startswith("#"):
            lines.append(line.replace("#", "").strip())
        elif line.startswith("|"):
            lines.append(line.replace("|", "  ").strip())
        elif line.startswith("-"):
            lines.append(line)
        elif line.startswith("```"):
            continue
        else:
            lines.append(line)
    return lines


def _paginate(lines: list[str]) -> list[list[str]]:
    pages: list[list[str]] = []
    current: list[str] = []
    for line in lines:
        current.append(line)
        if len(current) == LINES_PER_PAGE:
            pages.append(current)
            current = []
    if current:
        while len(current) < LINES_PER_PAGE:
            current.append("")
        pages.append(current)
    return pages


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    content = DOC_FILE.read_text(encoding="utf-8")
    lines = _markdown_to_lines(content)
    pages = _paginate(lines)

    pdf = DocumentPdf(format="A4")
    pdf.add_font("MicrosoftYaHei", "", str(_font_path()))
    pdf.set_auto_page_break(auto=False)
    pdf.set_margins(left=16, top=14, right=16)

    for page in pages:
        pdf.add_page()
        pdf.set_font("MicrosoftYaHei", "", FONT_SIZE)
        for line in page:
            pdf.cell(0, 8.0, _sanitize_for_pdf(line[:76]), new_x="LMARGIN", new_y="NEXT")

    pdf.output(str(OUT_FILE))
    print(f"已生成：{OUT_FILE}")
    print(f"页数：{len(pages)}")


if __name__ == "__main__":
    main()
