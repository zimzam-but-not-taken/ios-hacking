# ios-dump

Decrypt an installed iOS app and pull a decrypted `.ipa` back to the host over
SSH, using Frida. A Frida 17 port of AloneMonkey's `frida-ios-dump`, whose
upstream agent fails on Frida 17.

This folder is self-contained: the runnable tool, plus the small build project
for its injected agent.

| Path            | What it is                                                   |
|-----------------|--------------------------------------------------------------|
| `dump.py`       | Driver (SSH + Frida orchestration). Run this.                |
| `dump.js`       | **Built** agent bundle, loaded by `dump.py`. Do not hand-edit. |
| `agent/dump.js` | Agent **source**. Edit this, then rebuild.                   |
| `package.json`  | Build toolchain: `frida-compile` + `frida-objc-bridge`.      |
| `requirements.txt` | Python dependencies.                                      |

## Setup

```bash
pip3 install -r requirements.txt     # host-side Python deps
```

The host `frida` Python package must match the `frida-server` version on the
device (both are 17.x here).

## Use

The device must be reachable over SSH (default `root@localhost:2222`, matching
`host_scripts/connect.sh` which forwards it with `iproxy`), and `frida-server`
must be running on the device.

```bash
python3 dump.py -l                                    # list installed apps
python3 dump.py -K ~/.ssh/ios_devices com.foo.bar     # decrypt -> <name>.ipa (CWD)
python3 dump.py -K ~/.ssh/ios_devices -o MyApp com.foo.bar
```

`-K ~/.ssh/ios_devices` is passwordless key auth. Without it `dump.py` falls
back to the password `alpine`. Other SSH overrides: `-H host`, `-p port`,
`-u user` (`root` or `mobile`), `-P password`.

### Easiest path: the wrapper

`host_scripts/decrypt_and_pull.sh` wraps this with a numbered multi-select menu,
defaults to key auth (`~/.ssh/ios_devices`), and drops the `.ipa`s into your
working directory.

## Rebuilding the agent

Only needed if you edit `agent/dump.js` or upgrade Frida.

```bash
npm install          # first time only (fetches the build toolchain)
npm run build        # compiles agent/dump.js -> dump.js
npm run watch        # rebuild on change
```

`node_modules/` is git-ignored and regenerable with `npm install`.

The toolchain is pinned to the Frida 17 line (`frida-compile` ^17,
`frida-objc-bridge` ^8). If you upgrade Frida on the host and device, bump these
to match and rebuild.

### Why the upstream agent breaks on Frida 17

The Python driver still works; the injected agent did not. Frida 17 removed or
moved four things the old `dump.js` relied on:

- **`ObjC` is no longer a runtime global** — it ships as the `frida-objc-bridge`
  package, bundled in at build time.
- **Legacy `Memory.readX` / `Memory.writeX` helpers were removed** in Frida 16;
  reads/writes go through `NativePointer` methods.
- **`Module.findExportByName(null, …)` and `Module.ensureInitialized()` were
  removed as statics**; the global C-export lookup is now
  `Module.getGlobalExportByName()` (the agent feature-detects for Frida 16).
- **`Process.enumerateModulesSync()` was removed**; `enumerateModules()` is
  synchronous.

Frida 17 release notes: https://frida.re/news/2025/05/17/frida-17-0-0-released/

## Credits

Original tool by AloneMonkey (https://github.com/AloneMonkey/frida-ios-dump),
MIT-licensed (see `LICENSE`). This copy only modernizes the agent for Frida 17.
