# gcloud on native Termux — the recipe (ELF-patched glibc bundled python)

## The problem
- The `linux-arm` Cloud CLI tarball ships NO bundled python (uses system python).
- gcloud's bundled-python check is hardcoded to x86_64 (`bin/gcloud` ~line 112:
  `[ "$ARCH" = "x86_64" ]`) → on aarch64 it always falls back to Termux's bionic python3.
- No aarch64 `bundled-python3-unix` component exists to `gcloud components install`.

## The recipe
1. **SDK:** `google-cloud-cli-linux-arm.tar.gz` → extract to `~/google-cloud-sdk`.
2. **Bundled python:** a relocatable glibc aarch64 CPython from python-build-standalone
   (`cpython-3.13.x-aarch64-unknown-linux-gnu-install_only`) → placed at
   `~/google-cloud-sdk/platform/bundledpythonunix/`.
3. **ELF patch** (interpreter only — same as the grok/opencode/copilot native ports):
   ```sh
   patchelf --set-interpreter $PREFIX/glibc/lib/ld-linux-aarch64.so.1 \
     ~/google-cloud-sdk/platform/bundledpythonunix/bin/python3.13
   ```
   The binary's rpath stays `$ORIGIN/../lib` so `libpython3.13.so` + stdlib `.so` modules resolve
   relatively; the Termux glibc loader finds `libc`/`libm`/… from `$PREFIX/glibc/lib` (its default
   search path) — no rpath edit or `LD_LIBRARY_PATH` needed.
4. **Wire gcloud to it** (bypasses the x86_64 gate), in `~/.bashrc` and/or `$PREFIX/bin` wrappers:
   ```sh
   export CLOUDSDK_PYTHON=~/google-cloud-sdk/platform/bundledpythonunix/bin/python3
   export SSL_CERT_FILE=$PREFIX/etc/tls/cert.pem       # standalone python's baked CA path
   export REQUESTS_CA_BUNDLE=$PREFIX/etc/tls/cert.pem   # (/etc/ssl/cert.pem) doesn't exist in Termux
   export BROWSER=termux-open-url                        # optional: gcloud auth opens phone browser
   . ~/google-cloud-sdk/path.bash.inc
   . ~/google-cloud-sdk/completion.bash.inc
   ```

## Verify
```
gcloud info | grep -i 'python location'
  Python Location: [~/google-cloud-sdk/platform/bundledpythonunix/bin/python3]
gcloud info --run-diagnostics
  Reachability Check passed.
```

## Deps
`patchelf`, `curl`, `tar`, `ca-certificates`, and the Termux glibc loader at
`$PREFIX/glibc/lib/ld-linux-aarch64.so.1`.
