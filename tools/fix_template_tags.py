import zipfile, re, io, shutil
from datetime import datetime

src = r'C:\Users\jfcoste\OneDrive\Apps\WordMerger\templates\contrat_remplacement.docx'
ts = datetime.now().strftime('%Y%m%d-%H%M%S')
bak = src.replace('.docx', f'.fix-backup-{ts}.docx')
shutil.copy2(src, bak)
print(f'Backup: {bak}')

with open(src, 'rb') as f:
    in_bytes = f.read()

in_ms = io.BytesIO(in_bytes)
out_ms = io.BytesIO()

with zipfile.ZipFile(in_ms, 'r') as zin, zipfile.ZipFile(out_ms, 'w', zipfile.ZIP_DEFLATED) as zout:
    for item in zin.infolist():
        data = zin.read(item.filename)
        if item.filename == 'word/document.xml':
            xml = data.decode('utf-8')
            before = xml.count('}}')
            # Fix {{FIELD} (one closing brace) -> {{FIELD}}
            fixed = re.sub(r'(\{\{[A-Z0-9_]+\})(?!\})', r'\1}', xml)
            # Fix {{FIELD (no closing brace) immediately before </w:t> -> {{FIELD}}
            fixed = re.sub(r'(\{\{[A-Z0-9_]+)(?!\})(</w:t>)', r'\1}}\2', fixed)
            count = fixed.count('}}') - before
            print(f'Tags fixed: {count}')
            data = fixed.encode('utf-8')
        zout.writestr(item, data)

with open(src, 'wb') as f:
    f.write(out_ms.getvalue())
print(f'Template saved: {len(out_ms.getvalue())} bytes')
