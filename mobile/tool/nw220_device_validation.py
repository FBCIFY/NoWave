"""Real Android camera/query/capture matrix. Requires the running main app."""

import asyncio, json, re, sys, time
from pathlib import Path
from websockets.asyncio.client import connect


class Device:
    def __init__(self, ws, isolate):
        self.ws, self.isolate, self.seq = ws, isolate, 0

    async def rpc(self, method, params=None):
        self.seq += 1
        await self.ws.send(
            json.dumps(
                dict(jsonrpc="2.0", id=self.seq, method=method, params=params or {})
            )
        )
        while True:
            result = json.loads(await asyncio.wait_for(self.ws.recv(), 30))
            if result.get("id") == self.seq:
                if "error" in result:
                    raise RuntimeError(result["error"])
                return result["result"]

    async def marine(self, **args):
        return await self.rpc(
            "ext.nowave.marine",
            dict(isolateId=self.isolate, **{k: str(v) for k, v in args.items()}),
        )

    async def camera(self, lon, lat, zoom, bearing=0, pitch=0):
        await self.marine(
            action="camera", lon=lon, lat=lat, zoom=zoom, bearing=bearing, pitch=pitch
        )
        await asyncio.sleep(0.6)
        # The normal globe controller restores the detailed pitch after Z6.
        # Reapply the requested camera after that transition has completed.
        await self.marine(
            action="camera", lon=lon, lat=lat, zoom=zoom, bearing=bearing, pitch=pitch
        )

    async def settle(self):
        start = time.monotonic()
        quiet = 0
        while time.monotonic() - start < 45:
            await asyncio.sleep(0.4)
            result = await self.marine()
            if result["metrics"]["active"] == 0 and not result["metrics"].get(
                "busy", False
            ):
                quiet += 1
            else:
                quiet = 0
            if quiet >= 3:
                return result
        return result

    async def capture(self, path):
        p = await asyncio.create_subprocess_exec(
            "adb",
            "-s",
            "AV5PJV6328H03108",
            "exec-out",
            "screencap",
            "-p",
            stdout=asyncio.subprocess.PIPE,
        )
        data, _ = await p.communicate()
        path.write_bytes(data)


async def run(log, out, mode):
    base = re.search(
        r"available at: (http://127.0.0.1:8181/[^\s]+)", Path(log).read_text()
    )[1]
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    async with connect(
        base.replace("http:", "ws:") + "ws", max_size=64 * 1024 * 1024
    ) as ws:
        d = Device(ws, None)
        vm = await d.rpc("getVM")
        d.isolate = next(i["id"] for i in vm["isolates"] if i["name"] == "main")
        for _ in range(60):
            info = await d.rpc("getIsolate", {"isolateId": d.isolate})
            if "ext.nowave.marine" in info.get("extensionRPCs", []):
                break
            await asyncio.sleep(0.5)
        zooms = [
            4.99,
            5.0,
            5.01,
            5.99,
            6.0,
            7.99,
            8.0,
            9.0,
            9.99,
            10.0,
            11.0,
            11.99,
            12.0,
            12.99,
            13.0,
            14.0,
            15.0,
            16.0,
            18.0,
        ]
        steps = [("forward", z) for z in zooms] + [
            ("reverse", z) for z in reversed(zooms)
        ]
        if mode == "ports":
            lon, lat = 5.925691723823536, 43.07947960619061
            steps = [("ports", z) for z in [7.99, 8, 9, 10, 12, 14, 16, 18]]
        elif mode.startswith("contours"):
            lon, lat = 5.9293, 43.0637
            if mode == "contours100":
                lon, lat = 5.9313, 43.0442
            if mode == "contours200":
                lon, lat = 5.9645, 43.0492
            steps = [
                ("contours", z) for z in [12, 12.99, 13, 14, 15, 16, 18, 16, 13, 12.99]
            ]
        else:
            lon, lat = 5.93, 43.08
        summary = []
        for index, (direction, zoom) in enumerate(steps):
            start = time.monotonic()
            await d.camera(lon, lat, zoom)
            result = await d.settle()
            stem = f"{index:02d}-{direction}-z{zoom:.2f}"
            (out / f"{stem}.json").write_text(json.dumps(result, indent=2))
            await d.capture(out / f"{stem}.png")
            counts = {}
            for f in result["rendered"]:
                for layer in f["layers"]:
                    counts[layer] = counts.get(layer, 0) + 1
            row = {
                "file": stem,
                "camera": result["camera"],
                "rendered": counts,
                "metrics": result["metrics"],
                "settle_s": round(time.monotonic() - start, 2),
            }
            summary.append(row)
            print(
                json.dumps({k: v for k, v in row.items() if k != "metrics"}), flush=True
            )
            (out / "summary.json").write_text(json.dumps(summary, indent=2))


if __name__ == "__main__":
    asyncio.run(run(*sys.argv[1:]))
