import logging
import os
from pathlib import Path

APP_DIR = Path(__file__).resolve().parent
PROJECT_DIR = APP_DIR.parent

os.chdir(str(PROJECT_DIR))

from dotenv import load_dotenv
load_dotenv(PROJECT_DIR / ".env")

from flask import Flask, abort, jsonify, render_template, request, send_file


# --------------------------------------------------
# Runtime logging
# --------------------------------------------------

LOG_FILE = Path(
    os.getenv("MEDIA_SERVER_LOG_FILE") or "/var/log/media_server.log"
)

LOG_FILE.parent.mkdir(parents=True, exist_ok=True)

logging.basicConfig(
    filename=str(LOG_FILE),
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
    force=True,
)

# --------------------------------------------------
# Server configuration
# --------------------------------------------------

VIDEO_DIR = Path(
    os.getenv("VIDEO_DIR") or str(PROJECT_DIR / "media")
).expanduser()

VIDEO_TEST_DIR = Path(
    os.getenv("VIDEO_TEST_DIR") or str(VIDEO_DIR)
).expanduser()

PORT = int(os.getenv("MEDIA_SERVER_PORT") or "8081")
HOST = os.getenv("MEDIA_SERVER_BIND") or "0.0.0.0"

if not 1 <= PORT <= 65535:
    raise RuntimeError(
        f"MEDIA_SERVER_PORT must be between 1 and 65535; got {PORT}."
    )

MEDIA_EXT = (".mp4", ".m4v", ".webm", ".mkv", ".mov")

app = Flask(__name__)


def is_within(path: Path, root: Path) -> bool:
    try:
        path.relative_to(root)
        return True
    except ValueError:
        return False


def get_allowed_roots(configured_base: Path) -> list[Path]:
    """
    Allow the configured media directory and the targets of its
    immediate child directory symlinks.

    This supports layouts such as:
        media/
            local_storage -> /mnt/local_storage
            storage       -> /mnt/usb_storage

    Symlinks elsewhere in the directory tree are not automatically trusted.
    """
    base = configured_base.resolve()

    allowed_roots = [base]

    try:
        with os.scandir(base) as entries:
            for entry in entries:
                try:
                    if not entry.is_dir(follow_symlinks=True):
                        continue

                    if not entry.is_symlink():
                        continue

                    target = Path(entry.path).resolve()

                    if target not in allowed_roots:
                        allowed_roots.append(target)

                except OSError:
                    continue

    except OSError:
        pass

    return allowed_roots


def is_allowed_path(path: Path, allowed_roots: list[Path]) -> bool:
    return any(
        is_within(path, root)
        for root in allowed_roots
    )


def resolve_media_path(relative_path: str) -> tuple[Path, list[Path], Path]:
    subpath = relative_path.strip("/")

    if subpath == "test" or subpath.startswith("test/"):
        configured_base = VIDEO_TEST_DIR
        rel_sub = (
            subpath[4:].strip("/")
            if subpath.startswith("test/")
            else ""
        )
    else:
        configured_base = VIDEO_DIR
        rel_sub = subpath

    configured_base = configured_base.absolute()
    target_base = configured_base.resolve()

    if not target_base.exists() or not target_base.is_dir():
        raise FileNotFoundError(
            f"Storage base not found: {target_base}"
        )

    allowed_roots = get_allowed_roots(configured_base)

    candidate = (configured_base / rel_sub).resolve()

    if not is_allowed_path(candidate, allowed_roots):
        abort(403)

    return target_base, allowed_roots, candidate


def has_playable_media(
    directory: Path,
    allowed_roots: list[Path],
    depth: int = 2,
) -> bool:
    if depth < 0:
        return False

    try:
        with os.scandir(directory) as entries:
            for entry in entries:
                if entry.name.startswith("."):
                    continue

                try:
                    entry_path = Path(entry.path).resolve()

                    if not is_allowed_path(entry_path, allowed_roots):
                        continue

                    if (
                        entry.is_file(follow_symlinks=True)
                        and entry.name.lower().endswith(MEDIA_EXT)
                    ):
                        return True

                    if entry.is_dir(follow_symlinks=True):
                        if has_playable_media(
                            entry_path,
                            allowed_roots,
                            depth - 1,
                        ):
                            return True

                except OSError:
                    continue

    except OSError:
        return False

    return False


def make_item_path(
    is_test: bool,
    subpath: str,
    entry_name: str,
) -> str:
    prefix = "test" if is_test else ""

    parts = [
        part
        for part in subpath.split("/")
        if part and part != "test"
    ]

    if prefix:
        parts.insert(0, prefix)

    parts.append(entry_name)

    return "/".join(parts)


@app.route("/")
def index():
    return render_template(
        "index.html",
        initial_path="",
    )


@app.route("/test")
@app.route("/test/<path:subpath>")
def test_index(subpath=""):
    initial_path = "test"

    if subpath:
        initial_path += "/" + subpath

    return render_template(
        "index.html",
        initial_path=initial_path,
    )


@app.route("/api/list")
def list_media():
    raw_path = request.args.get("path", "").strip("/")

    is_test = (
        raw_path == "test"
        or raw_path.startswith("test/")
    )

    try:
        _, allowed_roots, target_dir = resolve_media_path(raw_path)

    except FileNotFoundError as error:
        return jsonify({"error": str(error)}), 403

    except Exception:
        app.logger.exception("Invalid media directory request.")
        return jsonify({"error": "Invalid path request."}), 403

    if not target_dir.exists() or not target_dir.is_dir():
        return jsonify([])

    items = []

    try:
        with os.scandir(target_dir) as entries:
            for entry in entries:
                if entry.name.startswith("."):
                    continue

                try:
                    entry_path = Path(entry.path).resolve()

                    if not is_allowed_path(entry_path, allowed_roots):
                        continue

                    is_dir = entry.is_dir(follow_symlinks=True)

                    if is_dir:
                        if not has_playable_media(
                            entry_path,
                            allowed_roots,
                        ):
                            continue

                        items.append({
                            "name": entry.name,
                            "is_dir": True,
                            "path": make_item_path(
                                is_test,
                                raw_path,
                                entry.name,
                            ),
                        })

                    else:
                        if not entry.name.lower().endswith(MEDIA_EXT):
                            continue

                        items.append({
                            "name": entry.name,
                            "is_dir": False,
                            "path": make_item_path(
                                is_test,
                                raw_path,
                                entry.name,
                            ),
                        })

                except OSError:
                    continue

    except OSError:
        app.logger.exception(
            "Unable to scan media directory %s",
            target_dir,
        )

        return jsonify({
            "error": "Unable to read this directory."
        }), 500

    items.sort(
        key=lambda item: (
            not item["is_dir"],
            item["name"].lower(),
        )
    )

    return jsonify(items)


@app.route("/video/<path:filename>")
def serve_video(filename: str):
    try:
        _, _, media_file = resolve_media_path(filename)

    except Exception:
        abort(403)

    if not media_file.is_file():
        abort(404)

    if not media_file.name.lower().endswith(MEDIA_EXT):
        abort(404)

    return send_file(
        media_file,
        conditional=True,
        etag=True,
    )


if __name__ == "__main__":
    app.run(
        host=HOST,
        port=PORT,
        threaded=True,
    )