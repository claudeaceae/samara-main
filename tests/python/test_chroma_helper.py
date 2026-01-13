import os
import sys
import tempfile
import types
import unittest
from pathlib import Path

TESTS_DIR = os.path.abspath(os.path.dirname(__file__))
sys.path.insert(0, TESTS_DIR)
LIB_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "lib"))
sys.path.insert(0, LIB_DIR)

from service_test_utils import load_service_module

CHROMA_PATH = os.path.join(LIB_DIR, "chroma_helper.py")


def write_text(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


class _FakeCollection:
    def __init__(self, name, metadata=None):
        self.name = name
        self.metadata = metadata or {}
        self.docs = []
        self.metas = []
        self.ids = []

    def add(self, ids, documents, metadatas):
        self.ids.extend(ids)
        self.docs.extend(documents)
        self.metas.extend(metadatas)

    def query(self, query_texts, n_results, where=None, include=None):
        indices = list(range(len(self.docs)))
        if where:
            filtered = []
            for idx, meta in enumerate(self.metas):
                if all(meta.get(key) == value for key, value in where.items()):
                    filtered.append(idx)
            indices = filtered

        docs = [self.docs[i] for i in indices][:n_results]
        metas = [self.metas[i] for i in indices][:n_results]
        distances = [0.1 for _ in docs]
        return {
            "documents": [docs],
            "metadatas": [metas],
            "distances": [distances],
        }

    def count(self):
        return len(self.ids)


class _FakeClient:
    def __init__(self, path, settings):
        self.path = path
        self.settings = settings
        self.collections = {}

    def get_or_create_collection(self, name, metadata=None):
        if name not in self.collections:
            self.collections[name] = _FakeCollection(name, metadata)
        return self.collections[name]

    def create_collection(self, name, metadata=None):
        self.collections[name] = _FakeCollection(name, metadata)
        return self.collections[name]

    def delete_collection(self, name):
        self.collections.pop(name, None)


def make_chroma_stubs():
    chromadb_module = types.ModuleType("chromadb")
    config_module = types.ModuleType("chromadb.config")

    class Settings:
        def __init__(self, anonymized_telemetry=False):
            self.anonymized_telemetry = anonymized_telemetry

    chromadb_module.PersistentClient = _FakeClient
    config_module.Settings = Settings

    return {
        "chromadb": chromadb_module,
        "chromadb.config": config_module,
    }


class ChromaHelperTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.mind_path = Path(self.temp_dir.name) / ".claude-mind"
        (self.mind_path / "memory" / "episodes").mkdir(parents=True, exist_ok=True)
        (self.mind_path / "memory" / "reflections").mkdir(parents=True, exist_ok=True)
        self.env = {
            "SAMARA_MIND_PATH": str(self.mind_path),
            "MIND_PATH": str(self.mind_path),
        }

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_parse_episode_and_sections(self):
        episode = """# Episode
## 09:00
[iMessage]
This is a sufficiently long section of text that should be indexed.
## 10:00
Short
"""
        episode_path = self.mind_path / "memory" / "episodes" / "2026-01-01.md"
        write_text(episode_path, episode)

        with load_service_module(CHROMA_PATH, env=self.env, stubs=make_chroma_stubs()) as module:
            index = module.MemoryIndex()
            docs = index._parse_episode(episode_path, "2026-01-01")

        self.assertEqual(len(docs), 1)
        self.assertEqual(docs[0]["metadata"]["channel"], "imessage")

    def test_parse_dated_sections_and_decisions(self):
        learnings = """# Learnings
## 2026-01-01
- Learned something important.
"""
        decisions = """# Decisions
## 2026-01-02: Big Choice
This is a decision entry that has enough content to be indexed.
"""
        learnings_path = self.mind_path / "memory" / "learnings.md"
        decisions_path = self.mind_path / "memory" / "decisions.md"
        write_text(learnings_path, learnings)
        write_text(decisions_path, decisions)

        with load_service_module(CHROMA_PATH, env=self.env, stubs=make_chroma_stubs()) as module:
            index = module.MemoryIndex()
            dated_docs = index._parse_dated_sections(learnings_path, "learning")
            decision_docs = index._parse_decisions(decisions_path)

        self.assertEqual(len(dated_docs), 1)
        self.assertEqual(dated_docs[0]["metadata"]["date"], "2026-01-01")
        self.assertEqual(len(decision_docs), 1)
        self.assertIn("Big Choice", decision_docs[0]["metadata"]["title"])

    def test_rebuild_and_search(self):
        episode = """# Episode
## 09:00
[iMessage]
This is a sufficiently long section of text that should be indexed.
"""
        reflection = """# Reflection: 2026-01-02
This reflection has enough content to be indexed and analyzed.
"""
        learnings = """# Learnings
## 2026-01-03
- Learned something important.
"""
        observations = """# Observations
## 2026-01-03
- Observed something noteworthy.
"""
        decisions = """# Decisions
## 2026-01-04: Key Decision
This decision entry is long enough to be included in the index.
"""

        write_text(self.mind_path / "memory" / "episodes" / "2026-01-01.md", episode)
        write_text(self.mind_path / "memory" / "reflections" / "2026-01-02.md", reflection)
        write_text(self.mind_path / "memory" / "learnings.md", learnings)
        write_text(self.mind_path / "memory" / "observations.md", observations)
        write_text(self.mind_path / "memory" / "decisions.md", decisions)

        with load_service_module(CHROMA_PATH, env=self.env, stubs=make_chroma_stubs()) as module:
            index = module.MemoryIndex()
            stats = index.rebuild()
            results = index.search("indexed", n_results=5, source_filter="episode")

        self.assertEqual(stats["episodes"], 1)
        self.assertEqual(stats["reflections"], 1)
        self.assertEqual(stats["learnings"], 1)
        self.assertEqual(stats["observations"], 1)
        self.assertEqual(stats["decisions"], 1)
        self.assertEqual(stats["total"], 5)
        self.assertEqual(len(results), 1)
        self.assertEqual(results[0]["metadata"]["source"], "episode")


if __name__ == "__main__":
    unittest.main()
