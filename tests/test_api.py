from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health():
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json() == {"status": "ok"}


def test_create_and_get_note():
    r = client.post("/notes", json={"title": "first", "body": "hello"})
    assert r.status_code == 201
    note_id = r.json()["id"]

    r = client.get(f"/notes/{note_id}")
    assert r.status_code == 200
    assert r.json()["title"] == "first"


def test_delete_note():
    note_id = client.post("/notes", json={"title": "tmp"}).json()["id"]
    assert client.delete(f"/notes/{note_id}").status_code == 204
    assert client.get(f"/notes/{note_id}").status_code == 404


def test_validation():
    assert client.post("/notes", json={"title": ""}).status_code == 422
    assert client.post("/notes", json={"title": "x" * 101}).status_code == 422


def test_missing_note():
    assert client.get("/notes/99999").status_code == 404
