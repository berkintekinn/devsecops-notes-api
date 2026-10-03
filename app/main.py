from datetime import datetime, timezone
from itertools import count
from threading import Lock

from fastapi import FastAPI, HTTPException, status
from pydantic import BaseModel, Field

app = FastAPI(title="notes-api", version="0.1.0")


class NoteIn(BaseModel):
    title: str = Field(min_length=1, max_length=100)
    body: str = Field(default="", max_length=5000)


class Note(NoteIn):
    id: int
    created_at: datetime


_notes: dict[int, Note] = {}
_ids = count(1)
_lock = Lock()


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/notes", response_model=list[Note])
def list_notes():
    return list(_notes.values())


@app.post("/notes", response_model=Note, status_code=status.HTTP_201_CREATED)
def create_note(payload: NoteIn):
    with _lock:
        note = Note(id=next(_ids), created_at=datetime.now(timezone.utc), **payload.model_dump())
        _notes[note.id] = note
    return note


@app.get("/notes/{note_id}", response_model=Note)
def get_note(note_id: int):
    note = _notes.get(note_id)
    if note is None:
        raise HTTPException(status_code=404, detail="note not found")
    return note


@app.delete("/notes/{note_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_note(note_id: int):
    with _lock:
        if _notes.pop(note_id, None) is None:
            raise HTTPException(status_code=404, detail="note not found")
