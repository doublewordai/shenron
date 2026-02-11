import argparse
import sys

from ._core import generate


def main() -> int:
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

    args = parser.parse_args()

    try:
        generated = generate(args.target, args.output_dir)
    except Exception as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    print("Generated files:")
    for path in generated:
        print(path)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
