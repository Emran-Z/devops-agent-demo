"""
Inventory API — BUGGY version (introduced in commit that triggers the demo)

BUG: Every call to POST /api/process appends the full request body AND a
large pre-computed result list into a module-level list (_leak_storage).
This list is never cleared, so RSS grows ~2-4 MB per request and the
process exhausts the 1 GB available on the t3.micro within minutes under
moderate load.

The bug is intentionally obvious for demo purposes — it mirrors a real-world
pattern where developers cache "hot" computation results without an eviction
policy.
"""

import os
import time
import logging

import psutil
from flask import Flask, jsonify, request

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)
log = logging.getLogger(__name__)

app = Flask(__name__)

# In-memory store (bounded)
_MAX_ITEMS = 1_000
_items: list[dict] = []

# ⚠️  MEMORY LEAK — unbounded cache, never evicted
_leak_storage: list[dict] = []


# ---------------------------------------------------------------------------
# Health / metrics
# ---------------------------------------------------------------------------

@app.get("/health")
def health():
    return jsonify({"status": "ok", "version": "1.1.0-buggy"})


@app.get("/metrics")
def metrics():
    proc = psutil.Process(os.getpid())
    mem = proc.memory_info()
    vm  = psutil.virtual_memory()
    return jsonify({
        "process_rss_mb":      round(mem.rss  / 1024 / 1024, 2),
        "process_vms_mb":      round(mem.vms  / 1024 / 1024, 2),
        "system_used_pct":     round(vm.percent, 2),
        "system_available_mb": round(vm.available / 1024 / 1024, 2),
        "items_in_store":      len(_items),
        "leak_cache_size":     len(_leak_storage),
        "uptime_seconds":      round(time.time() - _START, 1),
    })


# ---------------------------------------------------------------------------
# Inventory endpoints
# ---------------------------------------------------------------------------

@app.get("/api/items")
def list_items():
    return jsonify({"count": len(_items), "items": _items[-100:]})


@app.post("/api/items")
def add_item():
    body = request.get_json(force=True, silent=True) or {}
    item = {
        "id":        len(_items) + 1,
        "name":      str(body.get("name", "unnamed"))[:128],
        "value":     int(body.get("value", 0)),
        "created_at": time.time(),
    }
    _items.append(item)
    if len(_items) > _MAX_ITEMS:
        _items.pop(0)
    log.info("item added id=%d total=%d", item["id"], len(_items))
    return jsonify(item), 201


@app.post("/api/process")
def process_data():
    """
    Simulate a compute job.

    BUG (line 84): result is cached in _leak_storage with no eviction.
    Each entry is ~2–4 MB.  Under load the process runs out of memory.
    """
    body  = request.get_json(force=True, silent=True) or {}
    value = int(body.get("value", 1))

    # Compute result
    result = sum(i * value for i in range(1_000))

    # ⚠️  BUG: cache the result forever — _leak_storage grows without bound
    _leak_storage.append({
        "timestamp":  time.time(),
        "request":    body,
        "value":      value,
        "result":     result,
        # Padding simulates caching intermediate computation state (~2 MB/entry)
        "_cache":     list(range(250_000)),
    })

    log.info(
        "process_data ok  cache_entries=%d  rss_mb=%.1f",
        len(_leak_storage),
        psutil.Process(os.getpid()).memory_info().rss / 1024 / 1024,
    )
    return jsonify({"status": "processed", "result": result,
                    "cache_entries": len(_leak_storage)})


# ---------------------------------------------------------------------------

_START = time.time()

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    log.info("Starting BUGGY app on port %d", port)
    app.run(host="0.0.0.0", port=port)
