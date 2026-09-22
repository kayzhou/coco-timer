#!/usr/bin/env python3
"""Pack or unpack a project tree. Rejects paths that escape the destination."""

import os
import sys
import zipfile

MAX_FILES = 200
MAX_TOTAL = 80 * 1024 * 1024
MAX_ONE = 20 * 1024 * 1024


def fail(message):
    print(message, file=sys.stderr)
    sys.exit(2)


def safe_parts(name):
    name = name.replace("\\", "/")
    if name.startswith("/") or re_bad(name):
        fail("压缩包路径不安全")
    parts = [part for part in name.split("/") if part not in ("", ".")]
    if not parts or any(part == ".." for part in parts):
        fail("压缩包路径不安全")
    return parts


def re_bad(name):
    return "/../" in f"/{name}/" or name.startswith("../")


def pack(src, dest):
    src = os.path.realpath(src)
    with zipfile.ZipFile(dest, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for dirpath, dirnames, filenames in os.walk(src):
            dirnames.sort()
            for filename in sorted(filenames):
                full = os.path.join(dirpath, filename)
                rel = os.path.relpath(full, src).replace(os.sep, "/")
                safe_parts(rel)
                archive.write(full, rel)


def unpack(zip_path, dest):
    os.makedirs(dest, exist_ok=True)
    dest_real = os.path.realpath(dest)
    written = 0
    with zipfile.ZipFile(zip_path) as archive:
        infos = [info for info in archive.infolist() if not info.is_dir()]
        if len(infos) > MAX_FILES:
            fail("压缩包文件过多")
        for info in infos:
            mode = (info.external_attr >> 16) & 0o170000
            if mode == 0o120000:
                fail("压缩包不能包含链接")
            parts = safe_parts(info.filename)
            target = os.path.realpath(os.path.join(dest, *parts))
            if target != dest_real and not target.startswith(dest_real + os.sep):
                fail("压缩包路径不安全")
            os.makedirs(os.path.dirname(target), exist_ok=True)
            with archive.open(info) as source, open(target, "wb") as output:
                while True:
                    chunk = source.read(64 * 1024)
                    if not chunk:
                        break
                    written += len(chunk)
                    if written > MAX_TOTAL or os.path.getsize(target) + len(chunk) > MAX_ONE:
                        fail("压缩包过大")
                    output.write(chunk)


def main():
    if len(sys.argv) != 4:
        fail("用法：zip_tool.py pack|unpack 源 目标")
    command, source, dest = sys.argv[1:]
    if command == "pack":
        pack(source, dest)
    elif command == "unpack":
        unpack(source, dest)
    else:
        fail("未知命令")


if __name__ == "__main__":
    try:
        main()
    except zipfile.BadZipFile:
        fail("这不是有效的 ZIP 文件")
