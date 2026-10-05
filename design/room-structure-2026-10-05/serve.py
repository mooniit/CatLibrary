"""Local-only preview server; explicit module MIME avoids Windows registry overrides."""
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from functools import partial
import argparse

parser = argparse.ArgumentParser()
parser.add_argument("--port", type=int, default=4181)
args = parser.parse_args()

class Handler(SimpleHTTPRequestHandler):
    extensions_map = {**SimpleHTTPRequestHandler.extensions_map, ".mjs": "text/javascript"}

root = Path(__file__).resolve().parents[2]
print(f"http://127.0.0.1:{args.port}/design/room-structure-2026-10-05/", flush=True)
ThreadingHTTPServer(("127.0.0.1", args.port), partial(Handler, directory=str(root))).serve_forever()
