#!/usr/bin/env python3
"""Create dedicated NoWave secrets once. Never rotate existing values implicitly."""
import os
from pathlib import Path
import secrets

root = Path('/opt/nowave')
if os.geteuid() != 0:
    raise SystemExit('Run as root on the VPS.')
for dirname in ['secrets', 'backups', 'config', 'releases', 'logs']:
    (root / dirname).mkdir(mode=0o700, parents=True, exist_ok=True)

secret_dir = root / 'secrets'
def write_once(name, contents, group):
    path = secret_dir / name
    if not path.exists():
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, 'w') as output:
            output.write(contents + '\n')
    os.chown(path, 0, group)
    os.chmod(path, 0o440)
    return path.read_text().strip()

admin = write_once('db_admin_password', secrets.token_hex(48), 70)
runtime = write_once('db_runtime_password', secrets.token_hex(48), 10001)
write_once('database_admin_url', f'postgresql://nowave_owner:{admin}@database:5432/nowave', 10001)
write_once('database_url', f'postgresql://nowave_runtime:{runtime}@database:5432/nowave', 10001)
print('NoWave directories and private database credentials are ready.')
