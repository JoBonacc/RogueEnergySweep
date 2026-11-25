import argparse, hashlib, pathlib, re, zipfile
p = argparse.ArgumentParser()
p.add_argument('--version', required=True)
p.add_argument('--output', default='dist')
a = p.parse_args()
if not re.fullmatch(r'\d+\.\d+\.\d+', a.version): p.error('expected X.Y.Z')
root = pathlib.Path(__file__).resolve().parents[1]
source = root / 'addon' / 'RogueEnergySweep'
toc = (source/'RogueEnergySweep.toc').read_text()
lua = (source/'RogueEnergySweep.lua').read_text()
assert re.search(r'^## Version: '+re.escape(a.version)+r'\s*$', toc, re.M), 'TOC version mismatch'
assert lua.startswith('-- Rogue Energy Sweep '+a.version+' '), 'Lua version mismatch'
assert re.search(r'^## Interface: (\d+)',toc,re.M).group(1) == re.search(r'local SUPPORTED_INTERFACE = (\d+)',lua).group(1), 'Interface mismatch'
assert ('## v'+a.version+'\n') in (root/'CHANGELOG.md').read_text(), 'Missing changelog entry'
out = pathlib.Path(a.output); out.mkdir(parents=True, exist_ok=True)
archive = out / f'RogueEnergySweep-{a.version}.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
    for f in sorted(source.iterdir()):
        if f.is_file(): z.write(f, 'RogueEnergySweep/'+f.name)
    z.write(root/'CHANGELOG.md','RogueEnergySweep/CHANGELOG.md')
(archive.with_suffix('.zip.sha256')).write_text(hashlib.sha256(archive.read_bytes()).hexdigest()+'  '+archive.name+'\n')
print(archive)
