"""Repeat controlled Android profile scenarios; real MapScreen, no production API.

Requires map_performance_profile.dart with NOWAVE_MAP_PROFILE=true. A separate
main.dart session is needed for real-world visual/GPS/report validation.
"""

import argparse
import asyncio
import hashlib
import json
from pathlib import Path
import re
import subprocess

from websockets.asyncio.client import connect


def adb(device, *args):
    return subprocess.check_output(['adb', '-s', device, *args])


async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('log', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--device', required=True)
    parser.add_argument('--trials', type=int, default=3)
    args = parser.parse_args()
    match = re.search(r'available at: (http://127\.0\.0\.1:\d+/[^\s]+/)', args.log.read_text())
    if not match:
        raise RuntimeError('Local VM service URL not found in the Flutter log')
    args.output.mkdir(parents=True, exist_ok=True)
    async with connect(match[1].replace('http:', 'ws:') + 'ws', max_size=64 * 1024 * 1024) as ws:
        sequence = 0

        async def rpc(method, params=None):
            nonlocal sequence
            sequence += 1
            await ws.send(json.dumps({'jsonrpc': '2.0', 'id': sequence, 'method': method, 'params': params or {}}))
            while True:
                result = json.loads(await ws.recv())
                if result.get('id') == sequence:
                    if 'error' in result:
                        raise RuntimeError(result['error'])
                    return result['result']

        vm = await rpc('getVM')
        isolate = next(i['id'] for i in vm['isolates'] if i['name'] == 'main')

        async def extension(name, **params):
            return await rpc('ext.nowave.' + name, {'isolateId': isolate, **{k: str(v) for k, v in params.items()}})

        async def camera(zoom, lon=5.934, lat=43.085, bearing=0, pitch=45, action='camera'):
            return await extension('marine', action=action, zoom=zoom, lon=lon, lat=lat, bearing=bearing, pitch=pitch, duration=4000)

        async def snapshot(scenario, trial, before):
            result = await extension('performance', action='end')
            state = await extension('marine')
            metrics = state['metrics']
            feature_ids = {
                family: hashlib.sha256(json.dumps(sorted(str(f['id']) for f in data)).encode()).hexdigest()
                for family, data in state['data'].items()
            }
            sample = {
                'scenario': scenario, 'trial': trial, 'performance': result,
                'requests': metrics['requests'] - before['requests'],
                'errors': metrics['errors'] - before['errors'],
                'cache_hits': metrics['cache_hits'] - before['cache_hits'],
                'active_at_end': metrics['active'],
                'camera': state['camera'], 'feature_ids': feature_ids,
                'features': {k: len(v) for k, v in state['data'].items()},
            }
            try:
                memory = await rpc('getAllocationProfile', {'isolateId': isolate})
                sample['dart_memory'] = memory.get('memoryUsage')
            except RuntimeError:
                sample['dart_memory'] = None
            samples.append(sample)
            (args.output / 'results.json').write_text(json.dumps(samples, indent=2) + '\n')
            print(json.dumps({'scenario': scenario, 'trial': trial, 'ui': result['flutter_ui']['p95_us'], 'raster': result['flutter_raster']['p95_us'], 'native': result['mapbox_render']['p95_us'], 'errors': sample['errors']}), flush=True)
            if trial == 1:
                (args.output / f'{scenario}.png').write_bytes(adb(args.device, 'exec-out', 'screencap', '-p'))

        samples = []
        for trial in range(1, args.trials + 1):
            for scenario in ['compass', 'dense_port', 'zoom_12_18', 'globe_rotation']:
                await extension('profileInput', headings='off', network='normal')
                if scenario == 'globe_rotation':
                    await camera(.7, lon=15, lat=12, pitch=0)
                    adb(args.device, 'shell', 'input', 'swipe', '360', '800', '390', '800', '160')
                else:
                    await camera(12 if scenario == 'zoom_12_18' else 13.8)
                await asyncio.sleep(2)
                # synchronize waits for the shared download drain. Do not
                # compare a cold baseline against an already warm variant.
                await extension('marine', action='sync')
                await asyncio.sleep(.3)
                await extension('marine', action='sync')
                await asyncio.sleep(1)
                before = (await extension('marine'))['metrics']
                await extension('performance', action='begin')
                if scenario == 'compass':
                    await extension('profileInput', headings='rotate')
                elif scenario == 'dense_port':
                    await camera(13.8, lon=5.941, lat=43.09, bearing=160, pitch=60, action='animate')
                elif scenario == 'zoom_12_18':
                    await camera(18, bearing=90, pitch=63.75, action='animate')
                await asyncio.sleep(6)
                await snapshot(scenario, trial, before)
        await extension('profileInput', headings='off')
    (args.output / 'battery.txt').write_bytes(adb(args.device, 'shell', 'dumpsys', 'battery'))
    (args.output / 'thermal.txt').write_bytes(adb(args.device, 'shell', 'dumpsys', 'thermalservice'))
    (args.output / 'meminfo.txt').write_bytes(adb(args.device, 'shell', 'dumpsys', 'meminfo', 'fr.blueway.app'))


if __name__ == '__main__':
    asyncio.run(main())
