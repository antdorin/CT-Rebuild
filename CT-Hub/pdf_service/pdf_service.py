"""
CT-Hub PDF word extraction sidecar.
Listens on 127.0.0.1:5053 (localhost only — not reachable by iOS directly).

Endpoints
---------
GET  /health                  -> {"ok": true}
GET  /words?path=<full_path>  -> word-layout JSON (see schema below)
DELETE /cache?path=<full_path>-> invalidate cache entry + delete .words.json sidecar

JSON schema (matches previous PdfPig output, consumed by iOS HubClient):
{
  "pages": [
    {
      "page": 1,
      "width": 612.0,
      "height": 792.0,
      "words": [
        {"text": "hello", "x0": 72.0, "y0": 700.0, "x1": 110.0, "y1": 714.0}
      ]
    }
  ]
}

Coordinates: PDF-space (bottom-left origin, Y increases upward).
pdfplumber uses top-of-page origin so we convert:
    y0 = page.height - word["bottom"]
    y1 = page.height - word["top"]
"""

import io
import json
import os
import sys
import threading

import fitz  # PyMuPDF
import pdfplumber
from flask import Flask, jsonify, request, send_file

app = Flask(__name__)

# In-memory cache: absolute path -> bytes (UTF-8 encoded JSON)
_cache: dict[str, bytes] = {}
_cache_lock = threading.Lock()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _sidecar_path(pdf_path: str) -> str:
    return pdf_path + ".words.json"


def _extract(pdf_path: str) -> bytes:
    """Extract word layout from pdf_path using pdfplumber. Returns JSON bytes."""
    pages_out = []
    try:
        with pdfplumber.open(pdf_path) as pdf:
            for page in pdf.pages:
                page_h = page.height
                page_w = page.width
                words_out = []

                words = page.extract_words(
                    x_tolerance=3,
                    y_tolerance=3,
                    keep_blank_chars=False,
                    use_text_flow=False,
                    expand_ligatures=True,
                )

                for w in words:
                    text = (w.get("text") or "").strip()
                    if not text:
                        continue
                    # pdfplumber: x0/x1 are already left/right from page left.
                    # top/bottom are from page top — convert to PDF-space (bottom-left origin).
                    x0 = round(float(w["x0"]), 4)
                    x1 = round(float(w["x1"]), 4)
                    y0 = round(page_h - float(w["bottom"]), 4)  # PDF bottom of word
                    y1 = round(page_h - float(w["top"]),    4)  # PDF top of word

                    if x1 <= x0 or y1 <= y0:
                        continue

                    words_out.append({
                        "text": text,
                        "x0": x0,
                        "y0": y0,
                        "x1": x1,
                        "y1": y1,
                    })

                pages_out.append({
                    "page":   page.page_number,
                    "width":  round(float(page_w), 4),
                    "height": round(float(page_h), 4),
                    "words":  words_out,
                })
    except Exception:
        # Return empty layout — iOS falls back to on-device PDFKit extraction.
        pass

    return json.dumps({"pages": pages_out}, separators=(",", ":")).encode("utf-8")


def _get_cached(pdf_path: str) -> bytes:
    """Return cached JSON bytes, populating cache from sidecar or fresh extraction."""
    with _cache_lock:
        if pdf_path in _cache:
            return _cache[pdf_path]

    # Try disk sidecar first (survives Hub restarts)
    sidecar = _sidecar_path(pdf_path)
    if os.path.isfile(sidecar):
        try:
            if os.path.getmtime(sidecar) >= os.path.getmtime(pdf_path):
                with open(sidecar, "rb") as f:
                    data = f.read()
                with _cache_lock:
                    _cache[pdf_path] = data
                return data
        except OSError:
            pass

    data = _extract(pdf_path)

    with _cache_lock:
        _cache[pdf_path] = data

    # Write sidecar asynchronously
    def _write():
        try:
            with open(sidecar, "wb") as f:
                f.write(data)
        except OSError:
            pass

    threading.Thread(target=_write, daemon=False).start()
    return data


def _invalidate(pdf_path: str) -> None:
    with _cache_lock:
        _cache.pop(pdf_path, None)
    sidecar = _sidecar_path(pdf_path)
    try:
        if os.path.isfile(sidecar):
            os.remove(sidecar)
    except OSError:
        pass


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@app.get("/health")
def health():
    return jsonify({"ok": True})


@app.get("/words")
def words():
    pdf_path = request.args.get("path", "")
    if not pdf_path:
        return jsonify({"error": "missing path"}), 400
    if not os.path.isfile(pdf_path):
        return jsonify({"error": "not found"}), 404

    data = _get_cached(pdf_path)
    return app.response_class(response=data, status=200, mimetype="application/json")


@app.delete("/cache")
def invalidate_cache():
    pdf_path = request.args.get("path", "")
    if not pdf_path:
        return jsonify({"error": "missing path"}), 400
    _invalidate(pdf_path)
    return "", 204


@app.get("/page-count")
def page_count():
    pdf_path = request.args.get("path", "")
    if not pdf_path:
        return jsonify({"error": "missing path"}), 400
    if not os.path.isfile(pdf_path):
        return jsonify({"error": "not found"}), 404
    try:
        doc = fitz.open(pdf_path)
        count = doc.page_count
        doc.close()
        return jsonify({"pageCount": count})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.get("/render")
def render_page():
    pdf_path = request.args.get("path", "")
    page_num = request.args.get("page", "1")
    scale = request.args.get("scale", "2.0")
    if not pdf_path:
        return jsonify({"error": "missing path"}), 400
    if not os.path.isfile(pdf_path):
        return jsonify({"error": "not found"}), 404
    try:
        page_idx = int(page_num)  # 0-based, same as fitz
        zoom = float(scale)
    except ValueError:
        return jsonify({"error": "invalid page or scale"}), 400

    try:
        doc = fitz.open(pdf_path)
        if page_idx < 0 or page_idx >= doc.page_count:
            doc.close()
            return jsonify({"error": "page out of range"}), 400
        page = doc[page_idx]
        mat = fitz.Matrix(zoom, zoom)
        pix = page.get_pixmap(matrix=mat, alpha=False)
        img_bytes = pix.tobytes("jpeg")
        doc.close()
        buf = io.BytesIO(img_bytes)
        buf.seek(0)
        return send_file(buf, mimetype="image/jpeg")
    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    port = int(os.environ.get("PDF_SIDECAR_PORT", "5053"))
    # Bind to localhost only — not externally reachable.
    app.run(host="127.0.0.1", port=port, debug=False, threaded=True)
