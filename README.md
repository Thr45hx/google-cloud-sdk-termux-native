# google-cloud-sdk-termux-native

Run the **Google Cloud CLI** (`gcloud`, `gsutil`, `bq`) **natively in Termux** on aarch64 —
no proot, no Ubuntu/PRoot container — on an ELF-patched glibc CPython.

Part of the Termux-native agent toolchain (same glibc-loader patch approach as the
[grok](https://github.com/Thr45hx/grok-cli-termux-native),
opencode/copilot, and [antigravity](https://github.com/Thr45hx/antigravity-cli-termux-native) ports).

## Why this is needed

Three things break a straight `gcloud` install on Termux/aarch64:

1. **No bundled Python on ARM.** The `linux-arm` Cloud CLI tarball ships *no* bundled Python, so it
   falls back to Termux's bionic `python3` — which trips some gcloud paths.
2. **The bundled-python check is hardcoded to x86_64.** In `bin/gcloud`:
   ```sh
   if [ -x ".../bundledpythonunix/bin/python3" ] && [ "$ARCH" = "x86_64" ] && ...
   ```
   so even if you drop a Python in that slot, aarch64 never uses it.
3. **No aarch64 bundled-python component** is published (`gcloud components install
   bundled-python3-unix` → *unknown component*).

**Fix:** drop a relocatable **glibc aarch64 CPython** (from
[python-build-standalone](https://github.com/astral-sh/python-build-standalone)) into the SDK's
`platform/bundledpythonunix/` slot, `patchelf --set-interpreter` its ELF interpreter to the Termux
glibc loader so it runs native, then point `CLOUDSDK_PYTHON` at it (bypassing the x86_64 gate).
Add `SSL_CERT_FILE`/`REQUESTS_CA_BUNDLE` → Termux's CA bundle (the standalone Python's baked cert
path `/etc/ssl/cert.pem` doesn't exist in Termux, so TLS verify fails without it).

## Requirements

- Termux, **aarch64**
- Termux **glibc** loader at `$PREFIX/glibc/lib/ld-linux-aarch64.so.1` (from the Termux glibc repo)
- `pkg install patchelf curl tar ca-certificates`

## Install

```sh
git clone https://github.com/Thr45hx/google-cloud-sdk-termux-native
cd google-cloud-sdk-termux-native
./install.sh
```

Then open a new shell (or `source ~/.bashrc`). `gcloud` / `gsutil` / `bq` are on PATH and run on the
patched native Python:

```
$ gcloud info | grep -i 'python location'
Python Location: [~/google-cloud-sdk/platform/bundledpythonunix/bin/python3]
$ gcloud info --run-diagnostics     # Reachability Check passed.
```

## Auth from a non-interactive shell (Claude Code `!`, CI, tmux pipes…)

Modern gcloud dropped the localhost-loopback flow — `gcloud auth login` (with or without
`--no-launch-browser`) now redirects to `sdk.cloud.google.com/authcode.html` and **waits for a code
on stdin**. A shell with no interactive stdin makes it crash (`EOFError: EOF when reading a line`).
Bridge stdin with a fifo:

```sh
mkfifo /tmp/gauth.pipe
setsid bash -c 'exec 3<>/tmp/gauth.pipe; gcloud auth login --no-launch-browser <&3' \
  >/tmp/gauth.out 2>&1 &
# 1. read the login URL from /tmp/gauth.out  (termux-open-url "$URL" to open it on-device)
# 2. sign in, copy the verification code, then:
echo '<paste-code-here>' > /tmp/gauth.pipe
# gcloud exchanges the code and writes creds to ~/.config/gcloud
```

Opening the fifo read-write (`exec 3<>`) is the trick — it keeps a writer attached so gcloud's
`input()` blocks (waiting) instead of hitting EOF.

## How it works

See [`NATIVE_PATCH_NOTE.md`](NATIVE_PATCH_NOTE.md) for the exact recipe and file layout.

## Notes

- `stop`, don't `delete`, any Compute Engine VMs you spin up — and shut them down after use;
  RUNNING instances bill by the minute.
- Uninstall: remove `~/google-cloud-sdk`, the `$PREFIX/bin/{gcloud,gsutil,bq}` wrappers, and the
  `google-cloud-sdk-termux-native` block in `~/.bashrc`.

## License

MIT.
