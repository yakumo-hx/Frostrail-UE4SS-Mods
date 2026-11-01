"""Build the pinned native Autosave bridge. Does not deploy or launch the game."""
from __future__ import annotations

import argparse
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/pydeps"))
import pefile
from ue4ss_lua_api import pdb_public_symbols


def build(output: Path):
    output.mkdir(parents=True, exist_ok=True)
    loader = ROOT / "tools/ue4ss-3.0.1-1183/ue4ss/UE4SS.dll"
    with pefile.PE(str(loader)) as pe:
        if (pe.FILE_HEADER.TimeDateStamp, pe.OPTIONAL_HEADER.SizeOfImage) != (0x6ade4f39, 0x13c3000):
            raise RuntimeError("Expected UE4SS 3.0.1-1183-gcdbc0b66")
        with zipfile.ZipFile(ROOT / "tools/zDEV-UE4SS_v3.0.1-1183-gcdbc0b66.zip") as archive:
            if archive.read("ue4ss/UE4SS.dll") != loader.read_bytes():
                raise RuntimeError("PDB package and pinned loader differ")
            symbols = pdb_public_symbols(archive.read("ue4ss/UE4SS.pdb"), pe)
    names = ["lua_tointegerx", "lua_pushboolean", "lua_pushstring", "lua_pushinteger", "lua_pushcclosure"]
    header = "/* Generated from the official cdbc0b66 PDB; no second Lua runtime. */\n"
    header += "\n".join(f"#define RVA_{name} 0x{symbols[name]:x}" for name in names) + "\n"
    (output / "ue4ss_lua_api.h").write_text(header, encoding="utf8")
    compiler = ROOT / "tools/llvm-mingw-20261020-ucrt-x86_64/bin/clang.exe"
    minhook = ROOT / "tools/minhook-1.3.4"
    sources = [ROOT / "native/FrostrailAutosave/autosave.c"]
    sources += [minhook / "src" / name for name in ("buffer.c", "hook.c", "trampoline.c", "hde/hde64.c")]
    flags = [str(compiler), "--target=x86_64-w64-windows-gnu", "-O2", "-Wall", "-Wextra", "-Werror",
             "-I" + str(output), "-I" + str(minhook / "include")]
    dll = output / "autosave.dll"
    subprocess.run([*flags, "-shared", *map(str, sources), "-o", str(dll)], check=True)
    print(dll)
    return flags, sources[1:]


if __name__ == "__main__":
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "build/FrostrailAutosave")
    parser.add_argument("--test", action="store_true", help="Run native version-gate checks after building.")
    args = parser.parse_args()
    flags, minhook_sources = build(args.output.resolve())
    if args.test:
        test = args.output.resolve() / "version-test.exe"
        subprocess.run([*flags, str(ROOT / "scripts/tests/autosave_native_test.c"),
                        *map(str, minhook_sources), "-o", str(test)], check=True)
        subprocess.run([str(test)], check=True)
