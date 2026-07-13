"""M4-A 本地离线检索服务。

该服务只返回章节证据，不生成答案，不访问网络，也不接入阅游生产链路。
"""

from __future__ import annotations

import argparse
import json
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

from m4_ai_eval import ChapterIndex, _load_json, load_index


MAX_BODY_BYTES = 4096
MAX_QUERY_LENGTH = 200


def _json_bytes(payload: dict[str, Any]) -> bytes:
    return json.dumps(payload, ensure_ascii=False).encode("utf-8")


def make_handler(index: ChapterIndex) -> type[BaseHTTPRequestHandler]:
    class OfflineAiHandler(BaseHTTPRequestHandler):
        def _send_json(self, status: HTTPStatus, payload: dict[str, Any]) -> None:
            body = _json_bytes(payload)
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self) -> None:  # noqa: N802
            if self.path == "/health":
                self._send_json(HTTPStatus.OK, {"status": "ok", "mode": "offline_retrieval_baseline"})
                return
            self._send_json(HTTPStatus.NOT_FOUND, {"status": "error", "message": "路径不存在"})

        def do_POST(self) -> None:  # noqa: N802
            if self.path != "/v1/ai/retrieve":
                self._send_json(HTTPStatus.NOT_FOUND, {"status": "error", "message": "路径不存在"})
                return
            try:
                length = int(self.headers.get("Content-Length", "0"))
            except ValueError:
                length = 0
            if length <= 0 or length > MAX_BODY_BYTES:
                self._send_json(HTTPStatus.REQUEST_ENTITY_TOO_LARGE, {"status": "error", "message": "请求体超限"})
                return
            try:
                payload = json.loads(self.rfile.read(length))
            except (json.JSONDecodeError, UnicodeDecodeError):
                self._send_json(HTTPStatus.BAD_REQUEST, {"status": "error", "message": "请求格式错误"})
                return
            query = payload.get("query") if isinstance(payload, dict) else None
            if not isinstance(query, str) or not query.strip() or len(query) > MAX_QUERY_LENGTH:
                self._send_json(HTTPStatus.BAD_REQUEST, {"status": "error", "message": "query 无效"})
                return
            result = index.search(query.strip())
            self._send_json(
                HTTPStatus.OK,
                {
                    "status": "success",
                    "mode": "offline_retrieval_baseline",
                    "generated": False,
                    "citations": [
                        {
                            "chapterId": result.citation.chapter_id,
                            "title": result.citation.title,
                            "quote": result.citation.quote,
                            "offset": result.citation.offset,
                        }
                    ],
                },
            )

        def log_message(self, format: str, *args: object) -> None:
            return

    return OfflineAiHandler


def serve(corpus_path: Path, host: str = "127.0.0.1", port: int = 8787) -> None:
    server = ThreadingHTTPServer((host, port), make_handler(load_index(corpus_path)))
    print(f"M4-A offline retrieval service listening on http://{host}:{port}")
    server.serve_forever()


def main() -> int:
    parser = argparse.ArgumentParser(description="启动 M4-A 本地离线检索服务")
    parser.add_argument("--corpus", type=Path, required=True)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8787)
    args = parser.parse_args()
    serve(args.corpus, args.host, args.port)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
