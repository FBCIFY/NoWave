"""VM service driver for the actual lib/main.dart Android build; no fixtures."""

import asyncio, json, re, sys
from pathlib import Path
from websockets.asyncio.client import connect


async def main():
    log = Path(sys.argv[1]).read_text()
    base = re.search(r"available at: (http://127.0.0.1:8181/[^\s]+)", log)[1]
    async with connect(
        base.replace("http:", "ws:") + "ws", max_size=64 * 1024 * 1024
    ) as ws:
        seq = 0

        async def rpc(method, params=None):
            nonlocal seq
            seq += 1
            await ws.send(
                json.dumps(
                    dict(jsonrpc="2.0", id=seq, method=method, params=params or {})
                )
            )
            while True:
                msg = json.loads(await ws.recv())
                if msg.get("id") == seq:
                    if "error" in msg:
                        raise RuntimeError(msg["error"])
                    return msg["result"]

        vm = await rpc("getVM")
        isolate = next(i["id"] for i in vm["isolates"] if i["name"] == "main")
        args = json.loads(sys.argv[2]) if len(sys.argv) > 2 else {}
        result = await rpc("ext.nowave.marine", dict(isolateId=isolate, **args))
        if len(sys.argv) > 3:
            Path(sys.argv[3]).write_text(json.dumps(result, indent=2))
        print(
            json.dumps(
                {k: v for k, v in result.items() if k not in ["data", "rendered"]},
                ensure_ascii=False,
            )
        )
        print(
            "rendered",
            len(result.get("rendered", [])),
            "data",
            {k: len(v) for k, v in result.get("data", {}).items()},
        )


if __name__ == "__main__":
    asyncio.run(main())
