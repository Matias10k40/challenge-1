# Historial de build y corrección - challenge-1

## Problema resuelto
La compilación del kernel fallaba en este repositorio porque el sistema no tenía instalado el compresor `xz`.

### Error original
Durante `make kernel`, la compilación fallaba con:
- `./scripts/xz_wrap.sh: 36: xz: not found`
- `make[3]: *** [arch/x86/boot/compressed/Makefile:133: arch/x86/boot/compressed/vmlinux.bin.xz] Error 127`

## Pasos ejecutados
1. Inspeccioné el `Makefile` y el script `scripts/01_build_kernel.sh`.
2. Ejecuté `make kernel` para reproducir el error.
3. Instalé la herramienta faltante:
   - `apt-get install -y xz-utils`
4. Reejecuté `make kernel` y la compilación completó correctamente.
5. Ejecuté `make rootfs` para crear el `initramfs`.
6. Verifiqué el ambiente con `make info`.
7. Arranqué la VM vulnerable en QEMU y capturé resultados parciales.

## Resultados
- Kernel vulnerable compilado y presente en `kernel/build/bzImage_vuln`.
- Initramfs generado en `kernel/build/initramfs.cpio.gz`.
- `make info` muestra:
  - `STUDENT_ID: Matias-Quinteros`
  - `bzImage_vuln: ✓`
  - `initramfs: ✓`

## Resultado de la VM (hito 1)
- `uname -r` -> `6.12.0`
- `id` -> `uid=1001(student) gid=1001(student) groups=1001(student)`
- `whoami` -> `student`

### Observación
La verificación automatizada con la VM headless produjo un problema al leer `/proc/modules`. La VM arrancó bien, pero el comando `cat /proc/modules | grep algif` devolvió:
- `cat: can't open '/proc/modules': No such file or directory`

Esto indica que la verificación completa del estado del módulo dentro de la VM debe hacerse con una sesión interactiva directa.

## Qué falta resolver en el repositorio
- Confirmar `algif_aead` dentro de la VM con una sesión operativa interactiva.
- Crear el resto de evidencias de hitos: `hito2_root_shell.txt`, `hito3_mitigation.txt`, `hito4_patched.txt`.
- Generar y aplicar el parche permanente en `patches/fix_algif_aead.patch`.
- Opcional: mejorar `scripts/02_build_rootfs.sh` o el proceso de init si `/proc/modules` sigue inaccesible en VM.

## Estado del `Makefile`
El `Makefile` en sí está correcto. No requiere cambios estructurales.
El problema fue un requisito del entorno de compilación (`xz-utils`) que no está incluido en la imagen base.

## Próximos pasos recomendados
1. Abrir la VM con `make qemu` en una terminal interactiva.
2. Ejecutar manualmente:
   - `uname -r`
   - `id`
   - `whoami`
   - `cat /proc/modules | grep algif`
3. Guardar esa salida real en `evidence/hito1_vuln_confirmed.txt`.
4. Continuar con el exploit para hito 2 y la mitigación para hito 3.
5. Crear el parche definitivo para hito 4 en `patches/fix_algif_aead.patch`.
