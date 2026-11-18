# Moodle en tu propio servidor con Easypanel

Plantilla para montar **Moodle 5** en un VPS con **Docker + Easypanel**, sin programar.
Es la receta que se explica paso a paso en el vídeo de EOPOS.

## Qué hace

- Descarga **Moodle oficial** (github.com/moodle/moodle) en la versión de `MOODLE_VERSION` (línea 9 del `Dockerfile`).
- PHP 8.4 + Apache con todas las extensiones que Moodle exige.
- En cada arranque (`docker/entrypoint.sh`):
  1. genera `config.php` a partir de las variables de entorno (las contraseñas nunca van en este repositorio);
  2. espera a que la base de datos esté lista;
  3. **instala** Moodle si la base está vacía, o lo **actualiza** si el código es más nuevo;
  4. configura el correo y arranca el **cron** (cada minuto).

## Cómo usarla

1. Pulsa **Use this template → Create a new repository** (puede ser público: aquí no hay contraseñas).
2. En Easypanel, dentro de un proyecto (por ejemplo `academia`):
   - Servicio **MariaDB**: nombre `db`, base de datos `moodle`, usuario `moodle`, contraseña larga.
     Copia el **Internal Host** (será `academia_db`).
   - Servicio **App** (por ejemplo `aula`):
     - **Source → Git**: la URL de tu copia, rama `main`.
     - **Build → Dockerfile**.
     - **Environment**: copia el bloque de abajo y cambia lo que va en MAYÚSCULAS.
     - **Mounts**: volumen `moodledata` en `/var/moodledata` (**imprescindible**: ahí van los ficheros de los alumnos).
     - **Domains**: `aula.tudominio.com`, HTTPS activado, puerto `80`.
3. En la zona DNS de tu dominio: registro **A**, nombre `aula`, valor la IP del servidor.
   Si usas Cloudflare, créalo con la nube **gris** y pásala a **naranja** cuando el aula ya tenga el candado.
4. Pulsa **Deploy** y mira los registros (Logs). La primera vez tarda varios minutos:
   **no toques nada mientras pone `instalando Moodle`**.

## Variables de entorno

```
MOODLE_DB_HOST=academia_db
MOODLE_DB_NAME=moodle
MOODLE_DB_USER=moodle
MOODLE_DB_PASS=CONTRASEÑA_DE_LA_BASE_DE_DATOS
MOODLE_WWWROOT=https://aula.TUDOMINIO.com
MOODLE_ADMIN_PASS=CONTRASEÑA_DEL_ADMIN
MOODLE_ADMIN_EMAIL=TU_CORREO
MOODLE_SMTP_HOSTS=SMTP.TUPROVEEDOR.COM:587
MOODLE_SMTP_USER=CORREO_QUE_ENVIA
MOODLE_SMTP_PASS=CONTRASEÑA_DEL_CORREO
```

- Las **cinco primeras son obligatorias**: si falta alguna, el contenedor no arranca y el registro dice cuál.
- `MOODLE_ADMIN_PASS` solo se usa en la primera instalación (usuario `admin`).
- Sin `MOODLE_SMTP_HOSTS`, Moodle no puede enviar correos (ni el de «he olvidado mi contraseña»).

Opcionales: `MOODLE_SITENAME`, `MOODLE_SITESHORT`, `MOODLE_LANG` (por defecto `es`), `MOODLE_SMTP_SECURE` (`tls`),
`MOODLE_NOREPLY`, `MOODLE_SUPPORT_EMAIL`, `MOODLE_THEME`, `MOODLE_CRON_INLINE` (`1`).

## Actualizar Moodle

1. **Antes, copia de seguridad** de la base de datos y del volumen `moodledata`.
2. En tu copia en GitHub, abre el `Dockerfile`, pulsa el lápiz y cambia `ARG MOODLE_VERSION=` por la nueva versión
   (las tienes en https://github.com/moodle/moodle/tags). Guarda.
3. En Easypanel, **Deploy**. Al arrancar, el aula se actualiza sola.

## Si una instalación se cortó a medias

Añade `MOODLE_RESET_DB=1`, despliega una vez y **quítala después** (vacía la base de datos: solo si no hay datos que perder).
