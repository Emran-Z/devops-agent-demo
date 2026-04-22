"""
Inventory API — HEALTHY version
No memory leak. Deployed on EC2 t3.micro for the AWS DevOps Agent demo.
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

# In-memory store (bounded — last 1 000 items only)
_MAX_ITEMS = 1_000
_items: list[dict] = []


# ---------------------------------------------------------------------------
# Health / metrics
# ---------------------------------------------------------------------------

@app.get("/health")
def health():
    return jsonify({"status": "ok", "version": "1.0.0-healthy"})


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
    # Keep store bounded so memory stays flat
    if len(_items) > _MAX_ITEMS:
        _items.pop(0)
    log.info("item added id=%d total=%d", item["id"], len(_items))
    return jsonify(item), 201


@app.post("/api/process")
def process_data():
    """
    Simulate a lightweight compute job.
    HEALTHY: result is computed and returned; nothing is cached globally.
    """
    body  = request.get_json(force=True, silent=True) or {}
    value = int(body.get("value", 1))
    # Compute result locally — no global accumulation
    result = sum(i * value for i in range(1_000))
    return jsonify({"status": "processed", "result": result})


# ---------------------------------------------------------------------------

_START = time.time()

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    log.info("Starting HEALTHY app on port %d", port)
    app.run(host="0.0.0.0", port=port)
