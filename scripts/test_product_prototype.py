"""原型合同检查器的标准库测试。"""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from check_product_prototype import inspect_file, inspect_prototype  # noqa: E402


ROOT = Path(__file__).resolve().parents[1]
PROTOTYPE = ROOT / "docs/product/20260713_阅游产品改进手机原型.html"


class ProductPrototypeContractTest(unittest.TestCase):
    """验证当前原型具备总详设要求的交互节点。"""

    def test_current_prototype_passes(self) -> None:
        report = inspect_file(PROTOTYPE)
        self.assertTrue(report["ok"], report["errors"])
        self.assertEqual(report["counts"]["scenarios"], 6)
        self.assertEqual(report["counts"]["screens"], 3)

    def test_missing_scene_is_rejected(self) -> None:
        report = inspect_prototype(
            '<meta name="viewport" content="width=device-width, initial-scale=1">'
            '<style>:root{--phone-width: 390px; --phone-height: 844px;}</style>',
            PROTOTYPE,
        )
        self.assertFalse(report["ok"])
        self.assertTrue(any("缺少场景" in error for error in report["errors"]))


if __name__ == "__main__":
    unittest.main()
