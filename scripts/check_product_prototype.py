"""检查阅游 390x844 HTML 产品原型的结构合同。"""

from __future__ import annotations

import argparse
import json
import sys
from html.parser import HTMLParser
from pathlib import Path
from typing import Any


REQUIRED_SCENARIOS = {"continue", "first", "error", "honor", "paid", "complete"}
REQUIRED_SCREENS = {"listen", "library", "companion"}
REQUIRED_COMPANION_TABS = {"xiaoyo", "marks", "activity"}
REQUIRED_REALM_TABS = {"free", "pro"}
REQUIRED_IDS = {
    "retry-cloud",
    "use-local",
    "open-reader",
    "open-compare",
    "reader-toggle",
    "prototype-purchase",
    "view-honor",
    "choose-next-book",
}
REQUIRED_DELEGATED_BINDINGS = (
    'all(".nav-button")',
    'all(".scenario-button")',
    'all("[data-companion]")',
    'all("[data-realm]")',
    'all("[data-close]")',
    'all(".book-item")',
    'all(".overlay")',
)
REQUIRED_DIRECT_BINDINGS = (
    'byId("main-play").addEventListener(',
    'byId("mini-play").addEventListener(',
    'byId("reader-toggle").addEventListener(',
    'byId("open-reader").addEventListener(',
    'byId("open-compare").addEventListener(',
    'byId("preview-realm").addEventListener(',
    'byId("show-chapters").addEventListener(',
    'byId("cycle-speed").addEventListener(',
    'byId("reader-speed").addEventListener(',
    'byId("previous-line").addEventListener(',
    'byId("next-line").addEventListener(',
    'byId("play-sample").addEventListener(',
    'byId("empty-import").addEventListener(',
    'byId("import-book").addEventListener(',
    'byId("retry-cloud").addEventListener(',
    'byId("use-local").addEventListener(',
    'byId("prototype-purchase").addEventListener(',
    'byId("view-honor").addEventListener(',
    'byId("choose-next-book").addEventListener(',
    'byId("book-search").addEventListener(',
    'byId("sort-books").addEventListener(',
)
FORBIDDEN_SCRIPT_APIS = (
    "fetch(",
    "XMLHttpRequest",
    "WebSocket(",
    "navigator.sendBeacon",
    "PaymentRequest(",
)
DEFAULT_SCREENSHOT_EXPECTATIONS = {
    "桌面": ("screenshots/20260713_阅游产品原型_桌面.png", (1440, 1000)),
    "手机": ("screenshots/20260713_阅游产品原型_手机.png", (390, 844)),
}
FORBIDDEN_REMOTE_PREFIXES = ("http://", "https://", "//")


class _PrototypeParser(HTMLParser):
    """收集原型中影响交互合同的 HTML 节点。"""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.metas: list[dict[str, str]] = []
        self.elements: list[tuple[str, dict[str, str]]] = []
        self.scripts: list[str] = []
        self._script_buffer: list[str] | None = None

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attributes = {key: value or "" for key, value in attrs}
        if tag == "meta":
            self.metas.append(attributes)
        self.elements.append((tag, attributes))
        if tag == "script":
            self._script_buffer = []

    def handle_endtag(self, tag: str) -> None:
        if tag == "script" and self._script_buffer is not None:
            self.scripts.append("".join(self._script_buffer))
            self._script_buffer = None

    def handle_data(self, data: str) -> None:
        if self._script_buffer is not None:
            self._script_buffer.append(data)


def inspect_prototype(
    source: str,
    source_path: Path,
    screenshot_expectations: dict[str, tuple[str, tuple[int, int]]] | None = None,
) -> dict[str, Any]:
    """检查原型结构并返回可序列化报告。"""

    parser = _PrototypeParser()
    parser.feed(source)
    errors: list[str] = []
    warnings: list[str] = []

    viewport = next(
        (
            meta.get("content", "")
            for meta in parser.metas
            if meta.get("name", "").lower() == "viewport"
        ),
        "",
    )
    if "width=device-width" not in viewport or "initial-scale=1" not in viewport:
        errors.append("viewport 必须包含 width=device-width 和 initial-scale=1")
    if "--phone-width: 390px" not in source:
        errors.append("原型必须固定 390px 手机宽度")
    if "--phone-height: 844px" not in source:
        errors.append("原型必须固定 844px 手机高度")

    ids: list[str] = []
    scenarios: set[str] = set()
    screens: set[str] = set()
    companion_tabs: set[str] = set()
    realm_tabs: set[str] = set()
    local_images: list[str] = []
    buttons_without_type: list[str] = []
    remote_resources: list[str] = []
    data_close_ids: set[str] = set()
    for tag, attributes in parser.elements:
        element_id = attributes.get("id", "")
        if element_id:
            ids.append(element_id)
        if tag == "button" and attributes.get("type") != "button":
            buttons_without_type.append(element_id or "<未命名按钮>")
        if attributes.get("data-scenario"):
            scenarios.add(attributes["data-scenario"])
        if attributes.get("data-screen"):
            screens.add(attributes["data-screen"])
        if attributes.get("data-companion"):
            companion_tabs.add(attributes["data-companion"])
        if attributes.get("data-realm"):
            realm_tabs.add(attributes["data-realm"])
        if attributes.get("data-close"):
            data_close_ids.add(attributes["data-close"])
        for key in ("src", "href"):
            resource = attributes.get(key, "")
            if not resource:
                continue
            if resource.startswith(FORBIDDEN_REMOTE_PREFIXES):
                remote_resources.append(resource)
            elif key == "src" and tag == "img":
                local_images.append(resource)

    duplicate_ids = sorted({item for item in ids if ids.count(item) > 1})
    if duplicate_ids:
        errors.append(f"id 不得重复：{', '.join(duplicate_ids)}")
    if missing := sorted(REQUIRED_SCENARIOS - scenarios):
        errors.append(f"缺少场景：{', '.join(missing)}")
    if missing := sorted(REQUIRED_SCREENS - screens):
        errors.append(f"缺少根导航：{', '.join(missing)}")
    if missing := sorted(REQUIRED_COMPANION_TABS - companion_tabs):
        errors.append(f"缺少陪伴分段：{', '.join(missing)}")
    if missing := sorted(REQUIRED_REALM_TABS - realm_tabs):
        errors.append(f"缺少书境分段：{', '.join(missing)}")
    if buttons_without_type:
        errors.append(f"按钮缺少 type=button：{', '.join(buttons_without_type)}")
    if remote_resources:
        errors.append(f"原型不得依赖远程资源：{', '.join(remote_resources)}")
    if missing := sorted(REQUIRED_IDS - set(ids) - data_close_ids):
        errors.append(f"缺少关键交互节点：{', '.join(missing)}")

    for image_path in local_images:
        if not (source_path.parent / image_path).is_file():
            errors.append(f"本地图片不存在：{image_path}")

    for label, (relative_path, expected_size) in (
        screenshot_expectations or DEFAULT_SCREENSHOT_EXPECTATIONS
    ).items():
        screenshot_path = source_path.parent / relative_path
        try:
            with screenshot_path.open("rb") as screenshot:
                header = screenshot.read(24)
            if header[:8] != b"\x89PNG\r\n\x1a\n" or len(header) < 24:
                raise ValueError("不是有效 PNG 文件")
            actual_size = (
                int.from_bytes(header[16:20], byteorder="big"),
                int.from_bytes(header[20:24], byteorder="big"),
            )
            if actual_size != expected_size:
                errors.append(
                    f"{label}截图尺寸必须为 {expected_size[0]}x{expected_size[1]}，"
                    f"实际为 {actual_size[0]}x{actual_size[1]}"
                )
        except (OSError, ValueError) as error:
            errors.append(f"{label}截图不可读：{relative_path}（{error}）")

    script = "\n".join(parser.scripts)
    for binding in (*REQUIRED_DELEGATED_BINDINGS, *REQUIRED_DIRECT_BINDINGS):
        if binding not in script:
            errors.append(f"缺少交互绑定：{binding}")

    forbidden_apis = [api for api in FORBIDDEN_SCRIPT_APIS if api in script]
    if forbidden_apis:
        errors.append(f"原型脚本不得调用网络或支付 API：{', '.join(forbidden_apis)}")
    if "支付均为模拟反馈" not in source or "原型不会发起支付" not in source:
        errors.append("原型必须明确支付仅为模拟反馈且不会发起支付")

    return {
        "ok": not errors,
        "errors": errors,
        "warnings": warnings,
        "counts": {
            "scenarios": len(scenarios),
            "screens": len(screens),
            "companionTabs": len(companion_tabs),
            "realmTabs": len(realm_tabs),
            "images": len(local_images),
        },
    }


def inspect_file(path: Path) -> dict[str, Any]:
    """读取指定原型文件并执行检查。"""

    return inspect_prototype(path.read_text(encoding="utf-8"), path)


def main() -> int:
    """执行命令行检查。"""

    parser = argparse.ArgumentParser(description="检查阅游手机 HTML 原型合同")
    parser.add_argument(
        "path",
        nargs="?",
        type=Path,
        default=Path("docs/product/20260713_阅游产品改进手机原型.html"),
    )
    parser.add_argument("--json", action="store_true", dest="as_json")
    args = parser.parse_args()
    report = inspect_file(args.path)
    if args.as_json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
    else:
        status = "通过" if report["ok"] else "失败"
        print(f"原型合同检查：{status}")
        for error in report["errors"]:
            print(f"ERROR: {error}")
        for warning in report["warnings"]:
            print(f"WARN: {warning}")
        print(json.dumps(report["counts"], ensure_ascii=False, sort_keys=True))
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
