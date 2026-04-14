# lib/python_install.sh — install the two Python packages to /usr/local/lib.
#
# The generated backup script runs:
#   PYTHONPATH=/usr/local/lib python3 -m vcb_dumper run ...
#   PYTHONPATH=/usr/local/lib python3 -m vcb_notify send ...
#
# So we just copy the two packages as-is. No setuptools, no pip, no venv.

PYTHON_INSTALL_BASE="/usr/local/lib"

install_python_packages() {
    local pkg
    for pkg in vcb_dumper vcb_notify; do
        local src="${VCB_ROOT}/${pkg}"
        local dst="${PYTHON_INSTALL_BASE}/${pkg}"
        if [[ ! -d "$src" ]]; then
            warn "expected Python package $src is missing — skipping"
            continue
        fi
        log "installing Python package: $dst"
        rm -rf "$dst"
        mkdir -p "$dst"
        cp -r "$src/." "$dst/"
        chown -R root:root "$dst"
        find "$dst" -type d -exec chmod 755 {} +
        find "$dst" -type f -exec chmod 644 {} +
    done
}
