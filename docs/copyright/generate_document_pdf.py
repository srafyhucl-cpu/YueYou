from __future__ import annotations

from dataclasses import dataclass
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
TOTAL_PAGES = 60
FONT_SIZE = 10
CODE_FONT_SIZE = 9
BODY_LINE_HEIGHT = 6.2
PARAGRAPH_GAP = 1.4
IMAGE_MAX_WIDTH = 118.0
IMAGE_MAX_HEIGHT = 82.0
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
    "\uFE0F"
    "]+"
)
IMAGE_PATTERN = re.compile(r"!\[(.*?)\]\((.*?)\)")


@dataclass(frozen=True)
class MarkdownElement:
    kind: str
    text: str = ""
    level: int = 0
    path: Path | None = None
    lines: tuple[str, ...] = ()


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
    sanitized = EMOJI_PATTERN.sub("", text).replace("•", "-").replace("\t", "    ")
    sanitized = sanitized.replace("`", "").replace("**", "").replace("__", "")
    return sanitized


def _markdown_to_elements(text: str) -> list[MarkdownElement]:
    elements: list[MarkdownElement] = []
    in_code_block = False
    code_lines: list[str] = []

    for raw in text.splitlines():
        line = raw.rstrip()
        stripped = line.strip()

        if stripped.startswith("```"):
            if in_code_block and code_lines:
                elements.append(MarkdownElement(kind="code", lines=tuple(code_lines)))
                code_lines = []
            in_code_block = not in_code_block
            continue

        if in_code_block:
            code_lines.append(line)
            continue

        if not stripped:
            elements.append(MarkdownElement(kind="blank"))
            continue

        image_match = IMAGE_PATTERN.fullmatch(stripped)
        if image_match:
            alt_text, relative_path = image_match.groups()
            elements.append(
                MarkdownElement(
                    kind="image",
                    text=_sanitize_for_pdf(alt_text.strip()),
                    path=(OUT_DIR / relative_path).resolve(),
                )
            )
            continue

        if stripped.startswith("#"):
            level = len(stripped) - len(stripped.lstrip("#"))
            heading = stripped[level:].strip()
            elements.append(
                MarkdownElement(
                    kind="heading",
                    text=_sanitize_for_pdf(heading),
                    level=max(1, min(level, 3)),
                )
            )
            continue

        if stripped.startswith("|"):
            cells = [cell.strip() for cell in stripped.strip("|").split("|")]
            if all(set(cell) <= {"-", ":", " "} for cell in cells):
                continue
            elements.append(
                MarkdownElement(
                    kind="table_row",
                    text=_sanitize_for_pdf("  |  ".join(cells)),
                )
            )
            continue

        if re.match(r"^[-*]\s+", stripped):
            elements.append(
                MarkdownElement(
                    kind="bullet",
                    text=_sanitize_for_pdf(re.sub(r"^[-*]\s+", "", stripped)),
                )
            )
            continue

        if re.match(r"^\d+\.\s+", stripped):
            elements.append(MarkdownElement(kind="numbered", text=_sanitize_for_pdf(stripped)))
            continue

        elements.append(MarkdownElement(kind="paragraph", text=_sanitize_for_pdf(stripped)))

    if code_lines:
        elements.append(MarkdownElement(kind="code", lines=tuple(code_lines)))

    return elements


def _wrap_text(pdf: FPDF, text: str, width: float) -> list[str]:
    if not text:
        return [""]

    wrapped: list[str] = []
    current = ""

    for char in text:
        if char == "\n":
            wrapped.append(current.rstrip())
            current = ""
            continue

        next_value = f"{current}{char}"
        if current and pdf.get_string_width(next_value) > width:
            wrapped.append(current.rstrip())
            current = char
        else:
            current = next_value

    if current or not wrapped:
        wrapped.append(current.rstrip())

    return wrapped


def _ensure_space(pdf: FPDF, required_height: float) -> None:
    if pdf.get_y() + required_height > pdf.page_break_trigger:
        pdf.add_page()


def _jpeg_size(path: Path) -> tuple[int, int]:
    with path.open("rb") as file:
        data = file.read()

    if len(data) < 4 or data[:2] != b"\xff\xd8":
        raise ValueError(f"不支持的 JPEG 图片：{path}")

    index = 2
    while index < len(data):
        while index < len(data) and data[index] == 0xFF:
            index += 1
        if index >= len(data):
            break

        marker = data[index]
        index += 1

        if marker in {0xD8, 0xD9}:
            continue

        if index + 2 > len(data):
            break
        segment_length = int.from_bytes(data[index:index + 2], "big")
        if segment_length < 2 or index + segment_length > len(data):
            break

        if marker in {0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF}:
            if index + 7 > len(data):
                break
            height = int.from_bytes(data[index + 3:index + 5], "big")
            width = int.from_bytes(data[index + 5:index + 7], "big")
            return width, height

        index += segment_length

    raise ValueError(f"无法解析 JPEG 图片尺寸：{path}")


def _image_info(path: Path) -> tuple[str, int, int]:
    with path.open("rb") as file:
        header = file.read(24)

    if len(header) >= 24 and header[:8] == b"\x89PNG\r\n\x1a\n":
        width = int.from_bytes(header[16:20], "big")
        height = int.from_bytes(header[20:24], "big")
        return "PNG", width, height

    if len(header) >= 2 and header[:2] == b"\xff\xd8":
        width, height = _jpeg_size(path)
        return "JPG", width, height

    raise ValueError(f"不支持的图片格式：{path}")


def _render_text_block(pdf: FPDF, text: str, *, indent: float = 0.0, gap_after: float = PARAGRAPH_GAP) -> None:
    width = pdf.w - pdf.l_margin - pdf.r_margin - indent
    lines = _wrap_text(pdf, text, width)
    _ensure_space(pdf, len(lines) * BODY_LINE_HEIGHT + gap_after)
    for line in lines:
        pdf.set_x(pdf.l_margin + indent)
        pdf.cell(width, BODY_LINE_HEIGHT, line, new_x="LMARGIN", new_y="NEXT")
    if gap_after > 0:
        pdf.ln(gap_after)


def _render_image(pdf: FPDF, element: MarkdownElement) -> None:
    if element.path is None or not element.path.exists():
        _render_text_block(pdf, f"[缺失图片] {element.text}", indent=0)
        return

    image_type, pixel_width, pixel_height = _image_info(element.path)
    image_width = IMAGE_MAX_WIDTH
    image_height = image_width * pixel_height / pixel_width
    if image_height > IMAGE_MAX_HEIGHT:
        image_height = IMAGE_MAX_HEIGHT
        image_width = image_height * pixel_width / pixel_height

    caption_height = BODY_LINE_HEIGHT + PARAGRAPH_GAP
    _ensure_space(pdf, image_height + caption_height + 2)
    x = (pdf.w - image_width) / 2
    y = pdf.get_y()
    pdf.image(str(element.path), x=x, y=y, w=image_width, h=image_height)
    pdf.set_y(y + image_height + 2)
    pdf.set_font("MicrosoftYaHei", "", 9)
    _render_text_block(pdf, element.text, gap_after=PARAGRAPH_GAP)
    pdf.set_font("MicrosoftYaHei", "", FONT_SIZE)


def _render_elements(pdf: FPDF, elements: list[MarkdownElement]) -> None:
    heading_sizes = {1: 15, 2: 13, 3: 11}

    for element in elements:
        if element.kind == "blank":
            if pdf.get_y() < pdf.page_break_trigger - 6:
                pdf.ln(2)
            continue

        if element.kind == "heading":
            size = heading_sizes.get(element.level, 11)
            _ensure_space(pdf, BODY_LINE_HEIGHT + 6)
            pdf.set_font("MicrosoftYaHei", "", size)
            _render_text_block(pdf, element.text, gap_after=2.2)
            pdf.set_font("MicrosoftYaHei", "", FONT_SIZE)
            continue

        if element.kind == "paragraph":
            pdf.set_font("MicrosoftYaHei", "", FONT_SIZE)
            _render_text_block(pdf, element.text)
            continue

        if element.kind == "bullet":
            pdf.set_font("MicrosoftYaHei", "", FONT_SIZE)
            _render_text_block(pdf, f"- {element.text}", indent=4)
            continue

        if element.kind == "numbered":
            pdf.set_font("MicrosoftYaHei", "", FONT_SIZE)
            _render_text_block(pdf, element.text, indent=2)
            continue

        if element.kind == "table_row":
            pdf.set_font("MicrosoftYaHei", "", 9)
            _render_text_block(pdf, element.text, gap_after=0.8)
            pdf.set_font("MicrosoftYaHei", "", FONT_SIZE)
            continue

        if element.kind == "code":
            pdf.set_font("MicrosoftYaHei", "", CODE_FONT_SIZE)
            for code_line in element.lines:
                _render_text_block(pdf, _sanitize_for_pdf(code_line), indent=4, gap_after=0)
            pdf.ln(1.2)
            pdf.set_font("MicrosoftYaHei", "", FONT_SIZE)
            continue

        if element.kind == "image":
            pdf.set_font("MicrosoftYaHei", "", FONT_SIZE)
            _render_image(pdf, element)
            continue


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    content = DOC_FILE.read_text(encoding="utf-8-sig")
    elements = _markdown_to_elements(content)

    pdf = DocumentPdf(format="A4")
    pdf.add_font("MicrosoftYaHei", "", str(_font_path()))
    pdf.set_auto_page_break(auto=True, margin=16)
    pdf.set_margins(left=16, top=14, right=16)

    pdf.add_page()
    pdf.set_font("MicrosoftYaHei", "", FONT_SIZE)
    _render_elements(pdf, elements)

    pdf.output(str(OUT_FILE))
    print(f"已生成：{OUT_FILE}")
    print(f"页数：{pdf.page_no()}")
    if pdf.page_no() > TOTAL_PAGES:
        print(f"提示：当前文档页数超过 {TOTAL_PAGES} 页，请改为提交连续前30页和后30页。")


if __name__ == "__main__":
    main()
