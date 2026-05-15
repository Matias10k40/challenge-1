# Reporte Técnico — CVE-2026-31431 "Copy Fail"
**Autor:** Matias Quinteros  
**Email:** maquinterosye@uide.edu.ec

## 1. Bug raíz y ubicación

El bug se encuentra en el archivo `crypto/algif_aead.c` del kernel Linux, específicamente en la función `_aead_recvmsg()`. En 2017 se introdujo una optimización que encadenaba el TX SGL (scatterlist de transmisión) al final del RX SGL (scatterlist de recepción) usando `sg_chain()`, y luego ejecutaba `req->src = req->dst`. Esto causaba que ambos punteros apuntaran exactamente a las mismas páginas físicas de memoria, permitiendo escrituras no autorizadas en el page cache del kernel.

## 2. Por qué el write a dst[assoclen + cryptlen] es peligroso

Cuando `req->src` y `req->dst` apuntan al mismo scatterlist, el subsistema criptográfico AEAD puede escribir datos controlados por el atacante en páginas del page cache que corresponden a archivos del sistema de archivos. En este exploit, el atacante logra escribir exactamente 4 bytes en la página de memoria que contiene el binario `/usr/bin/su`. Este binario tiene el bit setuid activado, lo que significa que se ejecuta siempre con privilegios de root. Al corromper su código en memoria, el atacante puede hacer que ejecute código arbitrario con UID 0 sin ningún privilegio previo.

## 3. Por qué el exploit es stealthy

El exploit es completamente indetectable porque opera exclusivamente en el page cache del kernel, que es la copia en RAM de los archivos del disco. El archivo `/usr/bin/su` en el disco permanece intacto con su hash SHA256 original. Herramientas como AIDE, Tripwire o cualquier antivirus basado en análisis de disco no detectarían nada porque solo comparan hashes de archivos en disco, no el contenido de la RAM.

## 4. Conexión con conceptos del curso

- **Page cache:** El kernel mantiene en RAM una copia de los archivos para mejorar el rendimiento. El exploit abusa de esto para modificar el comportamiento de un binario sin tocar el disco.
- **setuid y chmod:** El bit setuid hace que `/usr/bin/su` se ejecute siempre con privilegios de root sin importar quién lo invoque.
- **Inodos:** El exploit no modifica el inodo ni los bloques de datos en disco, solo la página en RAM referenciada por el page cache.
- **authencesn:** Es el algoritmo criptográfico compuesto que el exploit usa para activar el código vulnerable en `algif_aead.c`.

## 5. Reflexión final

Este CVE demuestra cómo múltiples decisiones técnicas correctas individualmente pueden combinarse para crear una vulnerabilidad grave. La optimización in-place de 2017 era razonable en términos de rendimiento. El uso de scatterlists encadenados era práctica estándar. Pero juntas crearon un camino donde un usuario sin privilegios puede escribir en memoria protegida del kernel. La lección es que en seguridad siempre hay que analizar las interacciones entre componentes, no solo cada componente individualmente.
