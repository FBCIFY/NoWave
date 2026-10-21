"""Additional real-device navigation and source checks; no synthetic objects."""

import asyncio, json, re, sys, time
from pathlib import Path
from websockets.asyncio.client import connect
from nw220_device_validation import Device


async def adb(*args):
    p = await asyncio.create_subprocess_exec(
        "adb", "-s", "AV5PJV6328H03108", *args, stdout=asyncio.subprocess.PIPE
    )
    out, _ = await p.communicate()
    return out


async def main(log, directory):
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
        for _ in range(60):
            info = await d.rpc("getIsolate", {"isolateId": d.isolate})
            if "ext.nowave.marine" in info.get("extensionRPCs", []):
                break
            await asyncio.sleep(0.5)

        async def save(name, result=None):
            result = result or await d.marine(project="true")
            (out / f"{name}.json").write_text(json.dumps(result, indent=2))
            await d.capture(out / f"{name}.png")
            print(
                json.dumps(
                    {
                        "name": name,
                        "camera": result["camera"],
                        "rendered": len(result["rendered"]),
                        "features": {k: len(v) for k, v in result["data"].items()},
                        "requests": result["metrics"]["requests"],
                        "errors": result["metrics"]["errors"],
                        "active": result["metrics"]["active"],
                    }
                ),
                flush=True,
            )
            return result

        async def view(name, lon, lat, zoom, bearing=0, pitch=0):
            await d.camera(lon, lat, zoom, bearing, pitch)
            await d.settle()
            return await save(name)

        await view("toulon-safety-z12", 5.93, 43.08, 12)
        await view("marseille-preload-z10", 5.37, 43.27, 10)
        await view("marseille-fade-z11", 5.37, 43.27, 11)
        await view("marseille-fade-z11.99", 5.37, 43.27, 11.99)
        await view("marseille-visible-z12", 5.37, 43.27, 12)
        await view("porquerolles-z12", 6.205, 43.0, 12)
        await view("martinique-isolated-z12", -60.87015, 14.46085, 12)
        await view("martinique-isolated-z16", -60.87015, 14.46085, 16)
        await view("line-baseline", 5.9293, 43.0637, 13)
        await view("rotation-pitch", 5.9293, 43.0637, 13, 90, 60)
        await d.marine(action="reload")
        await asyncio.sleep(2)
        await d.settle()
        await save("style-reload")
        await adb("shell", "input", "keyevent", "KEYCODE_HOME")
        await asyncio.sleep(3)
        await save("background")
        await adb("shell", "am", "start", "-n", "fr.blueway.app/.MainActivity")
        await asyncio.sleep(2)
        await d.settle()
        await save("foreground")
        # Interrupt only USB forwarding for the local public marine API. Business
        # services retain their normal HTTPS backend and authenticated connection.
        await adb("reverse", "--remove", "tcp:8004")
        await d.camera(6.4, 43.05, 12)
        await d.settle()
        await save("marine-disconnected")
        await adb("reverse", "tcp:8004", "tcp:8004")
        await asyncio.sleep(17)
        await d.settle()
        await save("marine-reconnected")
        for z in [8, 10, 12, 13, 16, 18, 12, 8, 13]:
            await d.marine(action="camera", lon=5.9293, lat=43.0637, zoom=z)
            await asyncio.sleep(0.08)
        await d.settle()
        await save("rapid-zoom")
        await view("longpress-before", 5.925691723823536, 43.07947960619061, 8)
        await adb("shell", "input", "swipe", "360", "805", "360", "805", "900")
        await asyncio.sleep(1)
        await d.capture(out / "longpress-sheet.png")
        await adb("shell", "input", "keyevent", "KEYCODE_BACK")
        # Leave the user's original application open on the tested map.
        await view("final-map", 5.9293, 43.0637, 13)
        (out / "meminfo.txt").write_bytes(
            await adb("shell", "dumpsys", "meminfo", "fr.blueway.app")
        )
        (out / "gfxinfo.txt").write_bytes(
            await adb("shell", "dumpsys", "gfxinfo", "fr.blueway.app")
        )


if __name__ == "__main__":
    asyncio.run(main(*sys.argv[1:]))
