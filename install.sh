#!/data/data/com.termux/files/usr/bin/bash
# google-cloud-sdk-termux-native — installer
# Runs gcloud / gsutil / bq NATIVE in Termux (aarch64), no proot, on an ELF-patched glibc Python.
set -euo pipefail

SDK_HOME="$HOME/google-cloud-sdk"
LOADER="$PREFIX/glibc/lib/ld-linux-aarch64.so.1"
CERT="$PREFIX/etc/tls/cert.pem"
CLI_URL="https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-arm.tar.gz"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

echo "==> preflight"
[ "$(uname -m)" = "aarch64" ] || { echo "ERROR: aarch64 only"; exit 1; }
command -v patchelf >/dev/null || { echo "ERROR: pkg install patchelf"; exit 1; }
command -v curl     >/dev/null || { echo "ERROR: pkg install curl"; exit 1; }
[ -f "$LOADER" ] || { echo "ERROR: glibc loader not found ($LOADER). Install the Termux glibc packages first."; exit 1; }
[ -f "$CERT"   ] || echo "WARN: $CERT missing (pkg install ca-certificates) — TLS verification will fail."

echo "==> download Cloud CLI (linux-arm) -> $SDK_HOME"
curl -fsSL -o "$WORK/cli.tgz" "$CLI_URL"
rm -rf "$SDK_HOME"
tar xzf "$WORK/cli.tgz" -C "$HOME"

echo "==> fetch relocatable glibc aarch64 CPython (python-build-standalone)"
API="https://api.github.com/repos/astral-sh/python-build-standalone/releases/latest"
PY_URL=""
for _ in 1 2 3; do
  PY_URL=$(curl -fsSL "$API" \
    | grep -oE 'https://[^"]+cpython-3\.13\.[0-9]+\+[0-9]+-aarch64-unknown-linux-gnu-install_only\.tar\.gz' \
    | sort -V | tail -1 || true)
  [ -n "$PY_URL" ] && break
done
[ -n "$PY_URL" ] || { echo "ERROR: could not resolve a python-build-standalone aarch64 asset"; exit 1; }
echo "    $PY_URL"
curl -fsSL -o "$WORK/py.tgz" "$PY_URL"
tar xzf "$WORK/py.tgz" -C "$WORK"                      # extracts to $WORK/python
DEST="$SDK_HOME/platform/bundledpythonunix"
rm -rf "$DEST"; mkdir -p "$SDK_HOME/platform"
mv "$WORK/python" "$DEST"

echo "==> patch python ELF interpreter -> Termux glibc loader"
PYBIN="$(ls "$DEST"/bin/python3.1* | grep -E 'python3\.[0-9]+$' | head -1)"
patchelf --set-interpreter "$LOADER" "$PYBIN"
echo -n "    native run: "; "$DEST/bin/python3" --version

echo "==> wrappers in \$PREFIX/bin (always on PATH, always the patched python)"
OPENER="$(command -v termux-open-url || true)"
BROWSER_LINE=""; [ -n "$OPENER" ] && BROWSER_LINE=": \"\${BROWSER:=$OPENER}\"; export BROWSER"
for t in gcloud gsutil bq; do
  {
    echo "#!$PREFIX/bin/bash"
    echo "export CLOUDSDK_PYTHON=\"$DEST/bin/python3\""
    echo ": \"\${SSL_CERT_FILE:=$CERT}\"; export SSL_CERT_FILE"
    echo ": \"\${REQUESTS_CA_BUNDLE:=$CERT}\"; export REQUESTS_CA_BUNDLE"
    [ -n "$BROWSER_LINE" ] && echo "$BROWSER_LINE"
    echo "exec \"$SDK_HOME/bin/$t\" \"\$@\""
  } > "$PREFIX/bin/$t"
  chmod +x "$PREFIX/bin/$t"
done

echo "==> ~/.bashrc"
MARK="# --- google-cloud-sdk-termux-native ---"
if ! grep -qF "$MARK" "$HOME/.bashrc" 2>/dev/null; then
  {
    echo ""
    echo "$MARK"
    echo "export CLOUDSDK_PYTHON=\"$DEST/bin/python3\""
    echo "export SSL_CERT_FILE=\"$CERT\""
    echo "export REQUESTS_CA_BUNDLE=\"$CERT\""
    [ -n "$OPENER" ] && echo "export BROWSER=\"\${BROWSER:-$OPENER}\""
    echo "[ -f \"$SDK_HOME/path.bash.inc\" ] && . \"$SDK_HOME/path.bash.inc\""
    echo "[ -f \"$SDK_HOME/completion.bash.inc\" ] && . \"$SDK_HOME/completion.bash.inc\""
  } >> "$HOME/.bashrc"
fi

echo "==> verify"
export CLOUDSDK_PYTHON="$DEST/bin/python3"
"$SDK_HOME/bin/gcloud" version | head -1
"$SDK_HOME/bin/gcloud" info 2>/dev/null | grep -i "python location" || true
echo
echo "DONE.  Open a new shell (or: source ~/.bashrc), then:"
echo "  gcloud auth login          # non-interactive shell? see README 'Auth' (fifo bridge)"
echo "  gcloud config set project YOUR_PROJECT_ID"
