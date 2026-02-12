import argparse
import importlib.metadata
import json
from pathlib import Path
import sys
from typing import List, Optional
from urllib.error import HTTPError, URLError
from urllib.parse import urljoin
from urllib.request import Request, urlopen

from ._core import generate

DEFAULT_REPO = "doublewordai/shenron"
DEFAULT_INDEX_ASSET = "configs-index.txt"
GITHUB_API = "https://api.github.com"


class CliError(RuntimeError):
    pass


def _normalize_tag(value: str) -> str:
    return value if value.startswith("v") else f"v{value}"


def _read_text(url: str) -> str:
    req = Request(url, headers={"User-Agent": "shenron-cli"})
    with urlopen(req) as resp:
        return resp.read().decode("utf-8")


def _read_json(url: str) -> dict:
    req = Request(
        url,
        headers={
            "User-Agent": "shenron-cli",
            "Accept": "application/vnd.github+json",
        },
    )
    with urlopen(req) as resp:
        return json.loads(resp.read().decode("utf-8"))


def _get_latest_release_tag(repo: str) -> str:
    payload = _read_json(f"{GITHUB_API}/repos/{repo}/releases/latest")
    tag = payload.get("tag_name")
    if not tag:
        raise CliError(f"could not determine latest release tag for {repo}")
    return tag


def _resolve_release_tag(release: Optional[str], repo: str) -> str:
    if release:
        if release == "latest":
            return _get_latest_release_tag(repo)
        return _normalize_tag(release)

    try:
        package_version = importlib.metadata.version("shenron")
        return _normalize_tag(package_version)
    except importlib.metadata.PackageNotFoundError as exc:
        raise CliError(
            "could not determine installed shenron version; pass --release or use --release latest"
        ) from exc


def _release_download_base(repo: str, tag: str) -> str:
    return f"https://github.com/{repo}/releases/download/{tag}/"


def _as_asset_base_url(value: str) -> str:
    if value.endswith("/"):
        return value
    return f"{value}/"


def _parse_index(index_text: str) -> List[str]:
    configs: List[str] = []
    seen = set()
    for raw in index_text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        name = line.split()[0]
        if not (name.endswith(".yml") or name.endswith(".yaml")):
            continue
        if name not in seen:
            configs.append(name)
            seen.add(name)
    return configs


def _configs_from_release_api(repo: str, tag: str) -> List[str]:
    payload = _read_json(f"{GITHUB_API}/repos/{repo}/releases/tags/{tag}")
    assets = payload.get("assets", [])
    configs = []
    for asset in assets:
        name = asset.get("name", "")
        if name.endswith(".yml") or name.endswith(".yaml"):
            configs.append(name)
    return sorted(dict.fromkeys(configs))


def _load_configs_for_release(repo: str, tag: str, index_url: Optional[str]) -> List[str]:
    if index_url:
        return _parse_index(_read_text(index_url))

    base_url = _release_download_base(repo, tag)
    derived_index_url = urljoin(base_url, DEFAULT_INDEX_ASSET)

    try:
        return _parse_index(_read_text(derived_index_url))
    except (HTTPError, URLError):
        # Backward compatibility with older releases that predate configs-index.txt.
        return _configs_from_release_api(repo, tag)


def _interactive_select(options: List[str]) -> str:
    if not options:
        raise CliError("no configs available")
    if not sys.stdin.isatty() or not sys.stdout.isatty():
        raise CliError("interactive selection requires a TTY; use --name in non-interactive environments")

    try:
        import termios
        import tty
    except Exception as exc:
        raise CliError("interactive selection is unsupported on this platform; use --name") from exc

    idx = 0
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)

    def render() -> None:
        sys.stdout.write("\x1b[2J\x1b[H")
        sys.stdout.write(
            "Select a Shenron config (arrow keys, Enter to confirm, q to cancel):\r\n\r\n"
        )
        for i, option in enumerate(options):
            prefix = "> " if i == idx else "  "
            sys.stdout.write(f"{prefix}{option}\r\n")
        sys.stdout.flush()

    try:
        tty.setraw(fd)
        render()
        while True:
            ch = sys.stdin.read(1)
            if ch in ("\r", "\n"):
                sys.stdout.write("\r\n")
                return options[idx]
            if ch in ("q", "Q"):
                raise CliError("selection cancelled")
            if ch == "\x03":
                raise KeyboardInterrupt
            if ch == "\x1b":
                seq = sys.stdin.read(2)
                if seq == "[A":
                    idx = (idx - 1) % len(options)
                    render()
                elif seq == "[B":
                    idx = (idx + 1) % len(options)
                    render()
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)


def _download_file(url: str, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    req = Request(url, headers={"User-Agent": "shenron-cli"})
    with urlopen(req) as resp, destination.open("wb") as out:
        out.write(resp.read())


def _yaml_scalar(value: str) -> str:
    return json.dumps(value)


def _apply_config_overrides(
    config_path: Path,
    api_key: Optional[str],
    scouter_api_key: Optional[str],
    scouter_collector_instance: Optional[str],
) -> None:
    overrides = {}
    if api_key is not None:
        overrides["api_key"] = api_key
    if scouter_api_key is not None:
        overrides["scouter_ingest_api_key"] = scouter_api_key
    if scouter_collector_instance is not None:
        overrides["scouter_collector_instance"] = scouter_collector_instance

    if not overrides:
        return

    lines = config_path.read_text(encoding="utf-8").splitlines()
    updated_lines: list[str] = []
    seen = set()

    for line in lines:
        if line and not line.startswith(" ") and ":" in line:
            key = line.split(":", 1)[0]
            if key in overrides:
                updated_lines.append(f"{key}: {_yaml_scalar(overrides[key])}")
                seen.add(key)
                continue
        updated_lines.append(line)

    for key, value in overrides.items():
        if key in seen:
            continue
        if updated_lines and updated_lines[-1].strip():
            updated_lines.append("")
        updated_lines.append(f"{key}: {_yaml_scalar(value)}")

    config_path.write_text("\n".join(updated_lines) + "\n", encoding="utf-8")


def _run_generate(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        prog="shenron",
        description="Generate Shenron docker-compose deployment files from a YAML config.",
    )
    parser.add_argument(
        "target",
        nargs="?",
        default=".",
        help="Config file path or directory containing one config YAML (default: current directory).",
    )
    parser.add_argument(
        "--output-dir",
        default=None,
        help="Directory where files are written (default: target directory).",
    )

    args = parser.parse_args(argv)

    generated = generate(args.target, args.output_dir)
    print("Generated files:")
    for path in generated:
        print(path)
    return 0


def _run_get(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        prog="shenron get",
        description="Download a release config and generate Shenron deployment files.",
    )
    parser.add_argument(
        "--release",
        default=None,
        help="Release tag (e.g. v0.6.3 or 0.6.3). Use 'latest' for newest release. Default: installed shenron version.",
    )
    parser.add_argument(
        "--repo",
        default=DEFAULT_REPO,
        help=f"GitHub repo in owner/name form (default: {DEFAULT_REPO}).",
    )
    parser.add_argument(
        "--name",
        default=None,
        help="Config filename to download directly (skips interactive picker).",
    )
    parser.add_argument(
        "--api-key",
        default=None,
        help="Override api_key in the downloaded config.",
    )
    parser.add_argument(
        "--scouter-api-key",
        default=None,
        help="Override scouter_ingest_api_key in the downloaded config.",
    )
    parser.add_argument(
        "--scouter-colector-instance",
        "--scouter-collector-instance",
        dest="scouter_collector_instance",
        default=None,
        help="Override scouter_collector_instance in the downloaded config.",
    )
    parser.add_argument(
        "--dir",
        default=".",
        help="Directory to write the selected config and generated files (default: current directory).",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Overwrite config file if it already exists.",
    )
    parser.add_argument(
        "--index-url",
        default=None,
        help=argparse.SUPPRESS,
    )
    parser.add_argument(
        "--base-url",
        default=None,
        help=argparse.SUPPRESS,
    )

    args = parser.parse_args(argv)

    release_tag = _resolve_release_tag(args.release, args.repo)
    base_url = _as_asset_base_url(args.base_url or _release_download_base(args.repo, release_tag))

    try:
        configs = _load_configs_for_release(args.repo, release_tag, args.index_url)
    except (HTTPError, URLError) as exc:
        raise CliError(f"failed to load config index for release {release_tag}: {exc}") from exc

    if not configs and args.release is None and args.index_url is None:
        latest_tag = _get_latest_release_tag(args.repo)
        if latest_tag != release_tag:
            release_tag = latest_tag
            base_url = _as_asset_base_url(args.base_url or _release_download_base(args.repo, release_tag))
            configs = _load_configs_for_release(args.repo, release_tag, args.index_url)

    if not configs:
        raise CliError(f"no config entries found for release {release_tag}")

    selected = args.name
    if selected is None:
        selected = _interactive_select(configs)
    elif selected not in configs:
        available = ", ".join(configs)
        raise CliError(f"config '{selected}' not found in index; available: {available}")

    out_dir = Path(args.dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    config_path = out_dir / selected
    if config_path.exists() and not args.force:
        raise CliError(f"config already exists: {config_path} (pass --force to overwrite)")

    config_url = urljoin(base_url, selected)
    try:
        _download_file(config_url, config_path)
    except (HTTPError, URLError) as exc:
        raise CliError(f"failed to download config from {config_url}: {exc}") from exc

    _apply_config_overrides(
        config_path,
        api_key=args.api_key,
        scouter_api_key=args.scouter_api_key,
        scouter_collector_instance=args.scouter_collector_instance,
    )

    generated = generate(str(config_path), str(out_dir))

    print(f"Downloaded config: {config_path}")
    print("Generated files:")
    for path in generated:
        print(path)
    return 0


def main() -> int:
    try:
        if len(sys.argv) > 1 and sys.argv[1] == "get":
            return _run_get(sys.argv[2:])
        return _run_generate(sys.argv[1:])
    except Exception as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
