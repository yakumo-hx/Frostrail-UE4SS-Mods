"""Build package-v2 ZIPs. No player config or probes."""
import argparse
import json
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
BASE = Path('Frostrail/Binaries/Win64')
RUNTIME = ROOT / 'tools/ue4ss-3.0.1-1183'


def build(package_id, output_dir=None):
    source_root = ROOT / 'mods' / package_id
    manifest = json.loads((source_root / 'mod.json').read_text(encoding='utf-8-sig'))
    selected = {}
    def add(source, relative):
        if not source.is_file():
            raise FileNotFoundError(source)
        selected[relative.as_posix()] = source
    if package_id == 'FrostrailCore':
        for relative in ('dwmapi.dll', 'ue4ss/UE4SS.dll', 'ue4ss/LICENSE', 'ue4ss/UE4SS-settings.ini'):
            add(RUNTIME / relative, BASE / relative)
        for source in (ROOT / 'mods/shared/Frostrail').rglob('*.lua'):
            add(source, BASE / 'ue4ss/Mods/shared/Frostrail' / source.relative_to(ROOT / 'mods/shared/Frostrail'))
    destination = BASE / 'ue4ss/Mods' / package_id if package_id == 'FrostrailCore' else Path(package_id)
    if package_id == 'FrostrailDemoContinue':
        add(source_root / 'Scripts/main.lua', destination / 'Scripts/main.lua')
    else:
        for source in source_root.rglob('*'):
            if source.is_file() and (source.suffix in ('.lua', '.png') or source.name.endswith('.mesh.json') or source.name in
                                   ('mod.json', 'settings.json', 'defaults.json', 'items.json')):
                add(source, destination / source.relative_to(source_root))
    if package_id in ('FrostrailAssist', 'FrostrailItems', 'FrostrailWoodcutting'):
        for ext in ('pak', 'utoc', 'ucas'):
            source = ROOT / 'build' / (package_id + '_P.' + ext)
            add(source, Path(source.name))
    if package_id == 'FrostrailAutosave':
        add(ROOT / 'build/FrostrailAutosave/autosave.dll', destination / 'native/autosave.dll')
    output_dir = Path(output_dir).resolve() if output_dir else ROOT / 'dist' / manifest['version']
    output_dir.mkdir(parents=True, exist_ok=True)
    name = 'UE4SS-FrostrailCore' if package_id == 'FrostrailCore' else package_id
    output = output_dir / (name + '-' + manifest['version'] + '.zip')
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
        archive.write(source_root / 'mod.json', 'mod.json')
        archive.write(ROOT / 'LICENSE', 'LICENSE')
        if (source_root / 'README.md').is_file():
            archive.write(source_root / 'README.md', 'README.md')
        else:
            archive.write(ROOT / 'docs/安装与配置.md', '安装与配置.md')
        if package_id == 'FrostrailAutosave':
            archive.write(ROOT / 'tools/minhook-1.3.4/LICENSE.txt', 'MinHook-LICENSE.txt')
        if package_id == 'FrostrailItems':
            archive.write(source_root / 'assets/Kenney-License.txt', 'Kenney-License.txt')
            archive.write(source_root / 'assets/Kenney-Furniture-License.txt', 'Kenney-Furniture-License.txt')
        for relative, source in sorted(selected.items()):
            archive.write(source, relative)
    display = output.relative_to(ROOT) if output.is_relative_to(ROOT) else output
    print(f'{display}: {len(selected)} deployment files; {output.stat().st_size} bytes')
    return output


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--only', nargs='+', help='Build only the specified package IDs.')
    parser.add_argument('--output', type=Path, help='Place packages with different versions in one delivery directory.')
    args = parser.parse_args()
    for package_id in args.only or ['FrostrailCore', 'FrostrailAssist', 'FrostrailCapacity', 'FrostrailAutosave', 'FrostrailItems', 'FrostrailConsole', 'FrostrailWoodcutting']:
        build(package_id, args.output)
