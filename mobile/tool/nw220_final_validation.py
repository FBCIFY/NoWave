"""Final installed APK checks against real published source objects."""

import asyncio, json, re, sys
from pathlib import Path
from websockets.asyncio.client import connect
from nw220_device_validation import Device
from nw220_extra_validation import adb


async def run(log, directory):
    out = Path(directory)
    out.mkdir(parents=True, exist_ok=True)
    base = re.search(
        r"available at: (http://127.0.0.1:8181/[^\s]+)", Path(log).read_text()
    )[1]
    async with connect(
        base.replace("http:", "ws:") + "ws", max_size=64 * 1024 * 1024
    ) as ws:
        d = Device(ws, None)
        vm = await d.rpc("getVM")
        d.isolate = next(i["id"] for i in vm["isolates"] if i["name"] == "main")

        async def snap(name, lon, lat, zoom):
            await d.camera(lon, lat, zoom)
            await d.settle()
            result = await d.marine(project="true")
            (out / f"{name}.json").write_text(json.dumps(result, indent=2))
            await d.capture(out / f"{name}.png")
            ids = {f["feature"].get("id") for f in result["rendered"]}
            print(
                json.dumps(
                    {
                        "name": name,
                        "zoom": result["camera"]["zoom"],
                        "rendered": len(ids),
                        "errors": result["metrics"]["errors"],
                    }
                ),
                flush=True,
            )
            return result

        targets = json.loads(
            Path("test-results/NW-220/safety-targets.json").read_text()
        )
        targets.sort(key=lambda f: f["geometry"]["coordinates"][0] < -20)
        for i, f in enumerate(targets):
            lon, lat = f["geometry"]["coordinates"]
            p = f["properties"]
            label = p["type"] + "-" + p.get("category", "")
            for zoom in [12, 16]:
                await snap(f"{i:02d}-{label}-z{zoom}", lon, lat, zoom)
        lorient = await snap("lorient-z12", -3.38, 47.68, 12)
        isolated = [
            f
            for f in lorient["data"]["seamarks"]
            if f["properties"].get("type") == "buoy_isolated_danger"
        ]
        (out / "isolated-buoy-available.json").write_text(
            json.dumps(isolated, indent=2)
        )
        if isolated:
            lon, lat = isolated[0]["geometry"]["coordinates"]
            for zoom in [12, 16]:
                await snap(f"isolated-buoy-z{zoom}", lon, lat, zoom)
        for zoom in [8, 10, 14, 18]:
            await snap(
                f"final-port-z{zoom}", 5.925691723823536, 43.07947960619061, zoom
            )
        for zoom in [12.99, 13, 15, 18]:
            await snap(f"final-line-z{zoom}", 5.9293, 43.0637, zoom)
        await snap("final-map", 5.9293, 43.0637, 13)
        # Native Mapbox attribution UI, read only.
        await adb("shell", "input", "tap", "234", "1537")
        await asyncio.sleep(1)
        await d.capture(out / "credits.png")
        await adb("shell", "input", "keyevent", "KEYCODE_BACK")
        (out / "meminfo.txt").write_bytes(
            await adb("shell", "dumpsys", "meminfo", "fr.blueway.app")
        )
        (out / "gfxinfo.txt").write_bytes(
            await adb("shell", "dumpsys", "gfxinfo", "fr.blueway.app")
        )
        (out / "dart-memory.json").write_text(
            json.dumps(
                await d.rpc("getMemoryUsage", {"isolateId": d.isolate}), indent=2
            )
        )


if __name__ == "__main__":
    asyncio.run(run(*sys.argv[1:]))
