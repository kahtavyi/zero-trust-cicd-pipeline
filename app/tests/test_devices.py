from fastapi.testclient import TestClient

from app.main import app


def test_list_devices_returns_seeded_inventory() -> None:
    with TestClient(app) as client:
        response = client.get("/api/v1/devices")

    assert response.status_code == 200
    body = response.json()
    assert body["count"] >= 4
    hub_ids = {item["hub_id"] for item in body["devices"]}
    assert "HUB-2P-001" in hub_ids
    assert "MP-002" in hub_ids


def test_search_devices_by_hub_id() -> None:
    with TestClient(app) as client:
        response = client.get(
            "/api/v1/devices/search",
            params={"hub_id": "HUB-2P-001"},
        )

    assert response.status_code == 200
    body = response.json()
    assert body["count"] == 1
    assert body["devices"][0]["device_name"] == "Ajax Hub 2 Plus Central"


def test_search_devices_rejects_sql_injection_payload() -> None:
    with TestClient(app) as client:
        response = client.get(
            "/api/v1/devices/search",
            params={"hub_id": "HUB-2P-001' OR '1'='1"},
        )

    assert response.status_code == 422


def test_diagnostics_ping_endpoint_and_input_validation() -> None:
    with TestClient(app) as client:
        ok_resp = client.post("/api/v1/diagnostics/ping", json={"target": "127.0.0.1"})
        bad_resp = client.post(
            "/api/v1/diagnostics/ping",
            json={"target": "127.0.0.1; cat /etc/passwd"},
        )

    assert ok_resp.status_code == 200
    assert ok_resp.json()["exit_code"] == 0
    assert bad_resp.status_code == 422


def test_security_headers_are_set_on_responses() -> None:
    with TestClient(app) as client:
        response = client.get("/health")

    assert response.status_code == 200
    assert response.headers["X-Content-Type-Options"] == "nosniff"
    assert response.headers["X-Frame-Options"] == "DENY"
    assert "default-src 'none'" in response.headers["Content-Security-Policy"]
    assert "no-store" in response.headers["Cache-Control"]
    assert response.headers["Cross-Origin-Embedder-Policy"] == "require-corp"
