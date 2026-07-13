import json
import sys
import subprocess
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from m4_ai_eval import evaluate, load_index


ROOT = Path(__file__).resolve().parents[1]
CORPUS = ROOT / "docs" / "ai" / "m4_g2_eval_corpus.json"
CASES = ROOT / "docs" / "ai" / "m4_g2_eval_cases.json"


class M4AiEvaluationTest(unittest.TestCase):
    def test_curated_corpus_passes_g2a_technical_gate(self) -> None:
        report = evaluate(load_index(CORPUS), json.loads(CASES.read_text(encoding="utf-8")))

        self.assertEqual(report["cases"], 8)
        self.assertGreaterEqual(report["accuracy"], 0.85)
        self.assertGreaterEqual(report["citation_rate"], 0.90)
        self.assertLess(report["p95_ms"], 5000)
        self.assertTrue(report["gate_passed"])

    def test_wrong_expected_chapter_cannot_pass(self) -> None:
        cases = json.loads(CASES.read_text(encoding="utf-8"))
        cases[0]["expected_chapter_id"] = 100

        report = evaluate(load_index(CORPUS), cases)

        self.assertLess(report["citation_rate"], 0.90)
        self.assertFalse(report["gate_passed"])

    def test_cli_returns_json_report(self) -> None:
        completed = subprocess.run(
            [
                sys.executable,
                str(ROOT / "scripts" / "m4_ai_eval.py"),
                "--corpus",
                str(CORPUS),
                "--cases",
                str(CASES),
            ],
            check=True,
            capture_output=True,
            text=True,
        )

        report = json.loads(completed.stdout)
        self.assertTrue(report["gate_passed"])
        self.assertEqual(report["estimated_cost"], 0.0)


if __name__ == "__main__":
    unittest.main()
