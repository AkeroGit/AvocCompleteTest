from pathlib import Path

from avoc.main import getVoiceCardsDir


def testGetVoiceCardsDirUsesNewDirectoryName(monkeypatch, tmp_path):
    monkeypatch.setenv("AVOC_DATA_DIR", str(tmp_path))

    voice_cards_dir = getVoiceCardsDir()

    assert voice_cards_dir == str(tmp_path / "voice_cards")


def testGetVoiceCardsDirMigratesLegacyDirectory(monkeypatch, tmp_path):
    monkeypatch.setenv("AVOC_DATA_DIR", str(tmp_path))

    legacy_dir = tmp_path / "voice_cards_dir"
    legacy_dir.mkdir()
    legacy_file = legacy_dir / "card.json"
    legacy_file.write_text("legacy")

    migrated_dir = Path(getVoiceCardsDir())

    assert migrated_dir == tmp_path / "voice_cards"
    assert (migrated_dir / "card.json").read_text() == "legacy"
    assert not legacy_dir.exists()


def testGetVoiceCardsDirMigrationIsIdempotent(monkeypatch, tmp_path):
    monkeypatch.setenv("AVOC_DATA_DIR", str(tmp_path))

    new_dir = tmp_path / "voice_cards"
    new_dir.mkdir()
    existing_file = new_dir / "existing.json"
    existing_file.write_text("new")

    legacy_dir = tmp_path / "voice_cards_dir"
    legacy_dir.mkdir()
    (legacy_dir / "legacy.json").write_text("legacy")

    resolved_dir = Path(getVoiceCardsDir())

    assert resolved_dir == new_dir
    assert existing_file.read_text() == "new"
    assert (legacy_dir / "legacy.json").read_text() == "legacy"
