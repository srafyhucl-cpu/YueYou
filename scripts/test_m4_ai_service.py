import json
import sys
import threading
import unittest
from http.client import HTTPConnection
from pathlib import Path
from http.server import ThreadingHTTPServer

sys.path.insert(0, str(Path(__file__).resolve().parent))
from m4_ai_eval import load_index_from_text  # noqa: E402
from m4_ai_service import make_handler  # noqa: E402


class M4AiServiceTest(unittest.TestCase):
    def setUp(self) -> None:
        corpus = "第一回 灵根育孕源流出\n石猴出生于仙石。\n第二回 悟彻菩提真妙理\n孙悟空拜师学艺。"
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), make_handler(load_index_from_text(corpus)))
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self) -> None:
        self.server.shutdown()
        self.thread.join(timeout=2)
        self.server.server_close()

    def request(self, method: str, path: str, body: bytes | None = None):
        connection = HTTPConnection(*self.server.server_address, timeout=2)
        headers = {"Content-Type": "application/json"} if body is not None else {}
        connection.request(method, path, body=body, headers=headers)
        response = connection.getresponse()
        payload = json.loads(response.read().decode("utf-8"))
        connection.close()
        return response.status, payload

    def test_health_and_retrieve_return_citation_without_generation(self) -> None:
        self.assertEqual(self.request("GET", "/health"), (200, {"status": "ok", "mode": "offline_retrieval_baseline"}))
        status, payload = self.request(
            "POST",
            "/v1/ai/retrieve",
            json.dumps({"query": "石猴出生于哪里"}, ensure_ascii=False).encode("utf-8"),
        )
        self.assertEqual(status, 200)
        self.assertFalse(payload["generated"])
        self.assertEqual(payload["citations"][0]["chapterId"], 1)

    def test_invalid_and_oversized_requests_are_rejected(self) -> None:
        status, _ = self.request("POST", "/v1/ai/retrieve", b'{"query":""}')
        self.assertEqual(status, 400)
        status, _ = self.request("POST", "/v1/ai/retrieve", b'{"query":"x"}' * 1000)
        self.assertEqual(status, 413)


if __name__ == "__main__":
    unittest.main()
