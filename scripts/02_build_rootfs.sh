#!/usr/bin/env bash
# scripts/02_build_rootfs.sh
# Construye el initramfs con BusyBox + Python 3.10 + SSH
# Los estudiantes necesitan Python 3.10+ para ejecutar el PoC (os.splice)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUSYBOX_SRC="$WORKSPACE_ROOT/kernel/busybox"
KERNEL_SRC="$WORKSPACE_ROOT/kernel/linux"
INITRAMFS_DIR="$WORKSPACE_ROOT/kernel/initramfs"
BUILD_DIR="$WORKSPACE_ROOT/kernel/build"
JOBS=$(nproc)

GREEN='\033[1;32m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${CYAN}[1/6] Clonando BusyBox...${NC}"
if [ ! -d "$BUSYBOX_SRC" ]; then
  git clone --depth 1 https://git.busybox.net/busybox "$BUSYBOX_SRC"
fi

cd "$BUSYBOX_SRC"
echo -e "${CYAN}[2/6] Configurando BusyBox (binario estático)...${NC}"
make defconfig
make oldconfig < /dev/null
# Compilación estática para no necesitar librerías externas

sed -i 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config
grep -q "CONFIG_STATIC=y" .config || echo "CONFIG_STATIC=y" >> .config
sed -i 's/CONFIG_TC=y/CONFIG_TC=n/' .config   

echo -e "${CYAN}[3/6] Compilando BusyBox...${NC}"
make -j"$JOBS" 2>&1 | tail -3

echo -e "${CYAN}[4/6] Instalando BusyBox en el initramfs...${NC}"
mkdir -p "$INITRAMFS_DIR"
make CONFIG_PREFIX="$INITRAMFS_DIR" install

# ── Estructura mínima del sistema de archivos ──────────────────────────────────
mkdir -p "$INITRAMFS_DIR"/{proc,sys,dev,tmp,etc,root,home,usr/bin,run}
mkdir -p "$INITRAMFS_DIR/home/student"
chmod 0755 "$INITRAMFS_DIR/home"
chmod 0755 "$INITRAMFS_DIR/home/student"
chown 1001:1001 "$INITRAMFS_DIR/home/student"

# Python 3 del host → copiarlo al initramfs con sus dependencias
echo -e "${CYAN}[5/6] Incluyendo Python 3 en el initramfs...${NC}"
PYTHON_BIN=$(which python3)
cp "$PYTHON_BIN" "$INITRAMFS_DIR/usr/bin/python3"
# Copiar librerías necesarias para Python
for lib in $(ldd "$PYTHON_BIN" 2>/dev/null | grep -oE '/[^ ]+\.so[^ ]*'); do
  mkdir -p "$INITRAMFS_DIR$(dirname $lib)"
  cp -L "$lib" "$INITRAMFS_DIR$lib" 2>/dev/null || true
done
# Python stdlib mínima
PYTHON_VER=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
mkdir -p "$INITRAMFS_DIR/usr/lib"
# Copiar stdlib completa de Python para asegurar módulos como 'encodings'
if [ -d "/usr/lib/python${PYTHON_VER}" ]; then
  cp -a "/usr/lib/python${PYTHON_VER}" "$INITRAMFS_DIR/usr/lib/" || true
elif [ -d "/usr/lib/python3" ]; then
  cp -a "/usr/lib/python3" "$INITRAMFS_DIR/usr/lib/" || true
fi
ln -sf python3 "$INITRAMFS_DIR/usr/bin/python"
ln -sf python3 "$INITRAMFS_DIR/usr/bin/python" 2>/dev/null || true
# Asegurar que /usr/bin/su exista (algunos PoC buscan /usr/bin/su)
mkdir -p "$INITRAMFS_DIR/usr/bin"
ln -sf /bin/su "$INITRAMFS_DIR/usr/bin/su" 2>/dev/null || true

# Copiar PoC del exploit al initramfs para pruebas dentro de la VM
if [ -f "$WORKSPACE_ROOT/copy_fail_exp.py" ]; then
  mkdir -p "$INITRAMFS_DIR/tmp"
  cp "$WORKSPACE_ROOT/copy_fail_exp.py" "$INITRAMFS_DIR/tmp/copy_fail_exp.py"
  chmod +x "$INITRAMFS_DIR/tmp/copy_fail_exp.py"
fi

# Copiar módulos del kernel al initramfs para que modprobe funcione en la VM
KERNEL_VERSION="$(make -sC "$KERNEL_SRC" kernelrelease 2>/dev/null || true)"
if [ -n "$KERNEL_VERSION" ]; then
  MODULE_DEST="$INITRAMFS_DIR/lib/modules/$KERNEL_VERSION"
  rm -rf "$MODULE_DEST"
  mkdir -p "$MODULE_DEST"

  if [ -d "$WORKSPACE_ROOT/kernel/build/lib/modules/$KERNEL_VERSION" ]; then
    cp -a "$WORKSPACE_ROOT/kernel/build/lib/modules/$KERNEL_VERSION"/* "$MODULE_DEST/" 2>/dev/null || true
  fi

  if [ -d "$KERNEL_SRC/crypto" ]; then
    (cd "$KERNEL_SRC" && find crypto -name '*.ko' -print0 | cpio -pdm0 "$MODULE_DEST" 2>/dev/null || true)
  fi

  if command -v depmod >/dev/null 2>&1; then
    depmod -b "$INITRAMFS_DIR" "$KERNEL_VERSION" 2>/dev/null || true
  fi
fi

# ── Usuario student (sin privilegios, como en el reto real) ───────────────────
cat > "$INITRAMFS_DIR/etc/passwd" << 'EOF'
root:x:0:0:root:/root:/bin/sh
student:x:1001:1001:student:/home/student:/bin/sh
EOF

cat > "$INITRAMFS_DIR/etc/shadow" << 'EOF'
root::19000:0:99999:7:::
student:$6$salt$hashedpassword:19000:0:99999:7:::
EOF

cat > "$INITRAMFS_DIR/etc/group" << 'EOF'
root:x:0:
student:x:1001:student
EOF

# ── /etc/profile con PATH útil ─────────────────────────────────────────────────
cat > "$INITRAMFS_DIR/etc/profile" << 'EOF'
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PS1='[\u@copy-fail \w]\$ '
echo ""
echo "  Bienvenido al kernel vulnerable (CVE-2026-31431)"
echo "  Hostname: $(hostname)"
echo "  Usuario: $(id)"
echo "  whoami: $(whoami)"
echo "  Kernel:  $(uname -r)"
echo "  Módulos cargados con algif:"
echo "  $(cat /proc/modules | grep -i alg || echo '  (ninguno detectado aún)')"
echo ""
EOF

# ── Script init ────────────────────────────────────────────────────────────────
cat > "$INITRAMFS_DIR/init" << 'INITEOF'
#!/bin/sh
mkdir -p /proc /sys /dev /tmp
mount -t proc none /proc || echo "[INIT] ERROR: proc mount failed"
mount -t sysfs none /sys || echo "[INIT] ERROR: sysfs mount failed"
mount -t devtmpfs none /dev 2>/dev/null || mdev -s
mount -t tmpfs none /tmp || echo "[INIT] ERROR: tmpfs mount failed"

echo "[INIT] /proc mount status:"
mount | grep ' on /proc ' || true

echo "[INIT] /proc content sample:"
ls /proc | head -20 || true

echo "[INIT] /proc/modules content:"
cat /proc/modules 2>&1 || true

echo "[INIT] /proc/self/mounts:"
cat /proc/self/mounts 2>&1 || true

# Cargar módulos crypto necesarios para la vulnerabilidad
modprobe algif_aead 2>&1 || echo "[INIT] modprobe algif_aead failed"
modprobe authencesn 2>&1 || echo "[INIT] modprobe authencesn failed"

# Hostname identificador (para validación anti-copia)
STUDENT_ID="${STUDENT_ID:-unknown}"
hostname "copy-fail-${STUDENT_ID}"

echo ""
echo "  ╔══════════════════════════════════════════╗"
echo "  ║   KERNEL VULNERABLE — CVE-2026-31431     ║"
echo "  ║   $(uname -r | cut -c1-42)               ║"
echo "  ╚══════════════════════════════════════════╝"
echo ""

# Iniciar SSH daemon si existe
if [ -x /usr/sbin/sshd ]; then
  /usr/sbin/sshd -D &
fi

# Login como student (sin privilegios)
# Use su without - to avoid BusyBox login shell home-directory issues.
# Asegurar permisos de la raíz para que usuarios no-root puedan ejecutar /bin/sh
chmod 0755 /
exec su student
INITEOF

chmod +x "$INITRAMFS_DIR/init"
chmod 0755 "$INITRAMFS_DIR"

echo -e "${CYAN}[6/6] Empaquetando initramfs...${NC}"
chmod 0755 "$INITRAMFS_DIR"
cd "$INITRAMFS_DIR"
# Normalizar permisos: directorios 0755, archivos 0644
find . -type d -exec chmod 0755 {} \; >/dev/null 2>&1 || true
find . -type f -exec chmod 0644 {} \; >/dev/null 2>&1 || true
# Restaurar permisos ejecutables para init y binarios necesarios
chmod 0755 ./init || true
chmod 0755 ./bin/busybox ./bin/su ./bin/sh 2>/dev/null || true
chmod 0755 usr/bin/python3 2>/dev/null || true
chmod 0755 tmp/copy_fail_exp.py 2>/dev/null || true
# Marcar como ejecutables todos los archivos ELF (intérpretes y binarios)
for f in $(find . -type f); do
  if [ "$(head -c4 "$f")" = $'\x7fELF' ] 2>/dev/null; then
    chmod a+x "$f" 2>/dev/null || true
  fi
done

find . | cpio -o -H newc | gzip > "$BUILD_DIR/initramfs.cpio.gz"

echo ""
echo -e "${GREEN}✓ rootfs listo → kernel/build/initramfs.cpio.gz${NC}"
echo ""
echo -e "  Siguiente paso: ${CYAN}make qemu${NC}"
echo -e "  (o: ${CYAN}STUDENT_ID=tunombre make qemu${NC})"
