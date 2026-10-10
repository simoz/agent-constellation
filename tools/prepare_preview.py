"""Assemble an isolated Quickshell config with the installed host UI modules."""

from pathlib import Path
import shutil
import tempfile

repository = Path(__file__).resolve().parents[1]
target = Path(tempfile.mkdtemp(prefix="constellation-preview-"))
plugin = target / "plugin"
plugin.mkdir()
for pattern in ("*.qml", "*.js"):
    for source in repository.glob(pattern):
        shutil.copy2(source, plugin / source.name)
shutil.copytree(repository / "ui", plugin / "ui")
(plugin / "tools").mkdir()
shutil.copy2(repository / "tools" / "collect.py", plugin / "tools" / "collect.py")
for folder in ("Commons", "Ui"):
    shutil.copytree(Path("/usr/share/omarchy/shell") / folder, target / folder)
preview = (repository / "tools" / "preview.qml").read_text()
preview = preview.replace('import ".." as Plugin', 'import "plugin" as Plugin')
preview = preview.replace('import "../ui" as Constellation', 'import "plugin/ui" as Constellation')
(target / "shell.qml").write_text(preview)
print(target)
