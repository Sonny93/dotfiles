#!/usr/bin/env python3
import sys
import yaml


def main(source_path: str, dest_path: str) -> None:
    with open(source_path) as source_file:
        config = yaml.safe_load(source_file)

    for key in ("profiles", "groups", "configSync"):
        config.pop(key, None)
    if "ssh" in config:
        config["ssh"].pop("knownHosts", None)

    with open(dest_path, "w") as dest_file:
        yaml.safe_dump(config, dest_file, sort_keys=False)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
