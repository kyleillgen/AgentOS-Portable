"""Filesystem safety and atomic records shared by operations processes."""
import contextlib, json, os, tempfile
from pathlib import Path

class ControlError(ValueError):
    pass

def ensure_within(root: Path, path: Path, label: str, strict: bool = False) -> Path:
    resolved = path.resolve(strict=strict)
    try:
        resolved.relative_to(root)
    except ValueError:
        raise ControlError(f"{label} escapes root: {path}")
    return resolved


def reject_redirects(root: Path, path: Path, label: str) -> None:
    """Reject symlinks, junctions, and other reparse points below root."""
    absolute = Path(os.path.abspath(path))
    try:
        relative = absolute.relative_to(root)
    except ValueError:
        raise ControlError(f"{label} escapes root: {path}")
    current = root
    for part in relative.parts:
        current = current / part
        if not current.exists() and not current.is_symlink():
            continue
        stat = current.lstat()
        is_junction = getattr(current, "is_junction", lambda: False)()
        is_reparse = bool(getattr(stat, "st_file_attributes", 0) & 0x400)
        if current.is_symlink() or is_junction or is_reparse:
            raise ControlError(f"{label} contains redirected path component: {current}")


def atomic_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp_name = tempfile.mkstemp(prefix=path.name + ".", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
            json.dump(value, handle, ensure_ascii=False, indent=2, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temp_name, path)
    finally:
        with contextlib.suppress(FileNotFoundError):
            os.unlink(temp_name)
