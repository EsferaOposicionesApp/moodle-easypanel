#!/bin/sh
# Arranque del contenedor del aula (plantilla Moodle + Easypanel).
#
# Hace tres cosas, en este orden:
#   1. Compone config.php a partir de las variables de entorno, para que la
#      contraseña de la base de datos no pase por git.
#   2. Espera a que la base de datos acepte conexiones.
#   3. Deja el aula al día: la instala si está vacía, y la actualiza si el
#      código que se acaba de desplegar es más nuevo que la base.
#
# El paso 3 es lo que convierte "git push" en un despliegue completo. También
# evita depender de una consola web para instalar, que es frágil: si la sesión
# se corta a mitad de la instalación, la base queda a medias.

set -e

CONFIG=/var/www/html/config.php

faltan=""
for v in MOODLE_DB_HOST MOODLE_DB_NAME MOODLE_DB_USER MOODLE_DB_PASS MOODLE_WWWROOT; do
    eval "valor=\$$v"
    [ -z "$valor" ] && faltan="$faltan $v"
done

if [ -n "$faltan" ]; then
    echo "ERROR: faltan variables de entorno:$faltan" >&2
    echo "Defínelas en Easypanel, en la pestaña Entorno del servicio." >&2
    exit 1
fi

MOODLE_DB_TYPE="${MOODLE_DB_TYPE:-mariadb}"
MOODLE_DB_PREFIX="${MOODLE_DB_PREFIX:-mdl_}"
MOODLE_DB_PORT="${MOODLE_DB_PORT:-3306}"
MOODLE_DATAROOT="${MOODLE_DATAROOT:-/var/moodledata}"

mkdir -p "$MOODLE_DATAROOT"
chown -R www-data:www-data "$MOODLE_DATAROOT"

# --- 1. config.php ---------------------------------------------------------
cat > "$CONFIG" <<PHP
<?php
// Generado por docker/entrypoint.sh en el arranque. No editar a mano.

unset(\$CFG);
global \$CFG;
\$CFG = new stdClass();

\$CFG->dbtype    = '${MOODLE_DB_TYPE}';
\$CFG->dblibrary = 'native';
\$CFG->dbhost    = '${MOODLE_DB_HOST}';
\$CFG->dbname    = '${MOODLE_DB_NAME}';
\$CFG->dbuser    = '${MOODLE_DB_USER}';
\$CFG->dbpass    = '${MOODLE_DB_PASS}';
\$CFG->prefix    = '${MOODLE_DB_PREFIX}';
\$CFG->dboptions = [
    'dbpersist' => 0,
    'dbport' => '${MOODLE_DB_PORT}',
    'dbsocket' => '',
    'dbcollation' => 'utf8mb4_unicode_ci',
];

\$CFG->wwwroot   = '${MOODLE_WWWROOT}';
\$CFG->dataroot  = '${MOODLE_DATAROOT}';
\$CFG->admin     = 'admin';
\$CFG->directorypermissions = 02777;

// Easypanel termina el TLS por delante y entrega HTTP al contenedor.
\$CFG->sslproxy  = true;

\$CFG->debug = ${MOODLE_DEBUG:-0};
\$CFG->debugdisplay = ${MOODLE_DEBUGDISPLAY:-0};

require_once(__DIR__ . '/public/lib/setup.php');
PHP

chown www-data:www-data "$CONFIG"
chmod 640 "$CONFIG"
echo "[aula] config.php generado para ${MOODLE_WWWROOT}"

# --- 2. Esperar a la base de datos -----------------------------------------
# El contenedor de la base puede tardar en aceptar conexiones. Sin esta espera,
# el primer arranque tras un reinicio del servidor fallaría por pura carrera.
estado_bd() {
    php -r '
        mysqli_report(MYSQLI_REPORT_OFF);               // PHP 8.1+: sin esto, un fallo de conexion es una excepcion
        $m = @new mysqli(getenv("MOODLE_DB_HOST"), getenv("MOODLE_DB_USER"),
                         getenv("MOODLE_DB_PASS"), getenv("MOODLE_DB_NAME"),
                         (int) (getenv("MOODLE_DB_PORT") ?: 3306));
        if ($m->connect_errno) { exit(2); }              // 2 = sin conexión
        $p = getenv("MOODLE_DB_PREFIX") ?: "mdl_";
        $r = $m->query("SHOW TABLES LIKE \"" . $p . "config\"");
        exit(($r && $r->num_rows) ? 0 : 1);              // 0 = instalada, 1 = vacía
    ' 2>/dev/null
    return $?
}

intento=0
while [ $intento -lt 30 ]; do
    # con set -e, un "estado_bd" que devuelve 1 o 2 pararia el script: se recoge el codigo asi
    if estado_bd; then codigo=0; else codigo=$?; fi
    [ $codigo -ne 2 ] && break
    intento=$((intento + 1))
    echo "[aula] esperando a la base de datos... ($intento)"
    sleep 2
done

if [ $codigo -eq 2 ]; then
    echo "ERROR: no se ha podido conectar con ${MOODLE_DB_HOST}:${MOODLE_DB_PORT} tras 60 segundos." >&2
    exit 1
fi

# --- 3. Instalar o actualizar ----------------------------------------------
# Solo el servicio web toca la base de datos. El del cron arranca con
# MOODLE_SKIP_BOOTSTRAP=1: si ambos intentaran instalar o actualizar a la vez,
# dos procesos estarian modificando el esquema en paralelo, que es la forma mas
# rapida de dejar una base de Moodle inservible.
if [ "${MOODLE_SKIP_BOOTSTRAP}" = "1" ]; then
    echo "[aula] MOODLE_SKIP_BOOTSTRAP=1: no se toca la base de datos"
    echo "[aula] listo"
    exec "$@"
fi

# Escotilla de emergencia: vacía la base antes de instalar. Solo para cuando una
# instalación quedó a medias y no hay datos que perder. Hay que quitarla después.
if [ "${MOODLE_RESET_DB}" = "1" ]; then
    echo "[aula] MOODLE_RESET_DB=1: vaciando la base de datos antes de instalar"
    php -r '
        $m = new mysqli(getenv("MOODLE_DB_HOST"), getenv("MOODLE_DB_USER"),
                        getenv("MOODLE_DB_PASS"), getenv("MOODLE_DB_NAME"),
                        (int) (getenv("MOODLE_DB_PORT") ?: 3306));
        $m->query("SET FOREIGN_KEY_CHECKS = 0");
        $r = $m->query("SHOW TABLES");
        $tablas = [];
        while ($f = $r->fetch_array()) { $tablas[] = $f[0]; }
        foreach ($tablas as $t) { $m->query("DROP TABLE IF EXISTS `" . $t . "`"); }
        $m->query("SET FOREIGN_KEY_CHECKS = 1");
        echo "[aula] " . count($tablas) . " tablas eliminadas\n";
    '
    codigo=1
fi

if [ $codigo -eq 1 ]; then
    if [ -z "${MOODLE_ADMIN_PASS}" ]; then
        echo "[aula] La base de datos está vacía y no hay MOODLE_ADMIN_PASS." >&2
        echo "[aula] Define esa variable en Easypanel con la contraseña que quieras" >&2
        echo "[aula] para la cuenta admin y vuelve a desplegar. El aula no se" >&2
        echo "[aula] instalará sola con una contraseña que nadie conozca." >&2
        exit 1
    fi

    echo "[aula] base vacía: instalando Moodle"
    su -s /bin/sh -c "php /var/www/html/admin/cli/install_database.php \
        --agree-license --lang='${MOODLE_LANG:-es}' \
        --fullname='${MOODLE_SITENAME:-Mi aula virtual}' \
        --shortname='${MOODLE_SITESHORT:-aula}' \
        --adminuser='${MOODLE_ADMIN_USER:-admin}' \
        --adminpass='${MOODLE_ADMIN_PASS}' \
        --adminemail='${MOODLE_ADMIN_EMAIL:-admin@example.com}'" www-data
    echo "[aula] instalación terminada"
else
    echo "[aula] base ya instalada: aplicando actualizaciones pendientes"
    su -s /bin/sh -c "php /var/www/html/admin/cli/upgrade.php --non-interactive" www-data || \
        echo "[aula] no había nada que actualizar"
fi

# Ajustes que conviene que viajen con el despliegue y no vivan solo en la
# memoria de quien configuro el aula un dia.
if [ -n "${MOODLE_THEME}" ]; then
    echo "[aula] tema: ${MOODLE_THEME}"
    su -s /bin/sh -c "php /var/www/html/admin/cli/cfg.php --name=theme --set='${MOODLE_THEME}'" www-data || true
fi

# Correo. El contenedor no trae sendmail: sin SMTP configurado, Moodle no manda
# nada y la recuperacion de contrasena falla en silencio, que es la peor forma
# de fallar. Si no hay servidor definido, se avisa en el registro.
if [ -n "${MOODLE_SMTP_HOSTS}" ]; then
    echo "[aula] correo saliente por ${MOODLE_SMTP_HOSTS}"
    su -s /bin/sh -c "php /var/www/html/admin/cli/cfg.php --name=smtphosts --set='${MOODLE_SMTP_HOSTS}'" www-data || true
    su -s /bin/sh -c "php /var/www/html/admin/cli/cfg.php --name=smtpsecure --set='${MOODLE_SMTP_SECURE:-tls}'" www-data || true
    su -s /bin/sh -c "php /var/www/html/admin/cli/cfg.php --name=smtpauthtype --set='${MOODLE_SMTP_AUTH:-LOGIN}'" www-data || true
    su -s /bin/sh -c "php /var/www/html/admin/cli/cfg.php --name=smtpuser --set='${MOODLE_SMTP_USER}'" www-data || true
    su -s /bin/sh -c "php /var/www/html/admin/cli/cfg.php --name=smtppass --set='${MOODLE_SMTP_PASS}'" www-data || true
    su -s /bin/sh -c "php /var/www/html/admin/cli/cfg.php --name=noreplyaddress --set='${MOODLE_NOREPLY:-${MOODLE_SMTP_USER}}'" www-data || true
    [ -n "${MOODLE_SUPPORT_EMAIL}" ] &&         su -s /bin/sh -c "php /var/www/html/admin/cli/cfg.php --name=supportemail --set='${MOODLE_SUPPORT_EMAIL}'" www-data || true
else
    echo "[aula] AVISO: sin MOODLE_SMTP_HOSTS no se puede enviar correo," >&2
    echo "[aula] asi que la recuperacion de contrasena no funcionara." >&2
fi

# Correo de la cuenta de administracion. Se aplica en cada arranque para que
# cambiarlo sea editar una variable, no ir a buscarlo por la interfaz.
if [ -n "${MOODLE_ADMIN_EMAIL}" ]; then
    su -s /bin/sh -c "php /var/www/html/docker/ajustes.php" www-data ||         echo "[aula] no se ha podido aplicar el correo del administrador"
fi

su -s /bin/sh -c "php /var/www/html/admin/cli/purge_caches.php" www-data || true

# --- 4. Cron ---------------------------------------------------------------
# Se arranca dentro de este mismo contenedor, en segundo plano. La alternativa
# es un servicio aparte, que es mas limpio de operar pero obliga a guardar una
# segunda copia de la contrasena de la base de datos en el panel. Para el tamano
# de esta aula no compensa: duplicar un secreto es peor que compartir un
# contenedor. Si algun dia el cron molesta al trafico, se separa poniendo
# MOODLE_CRON_INLINE=0 aqui y creando el servicio con MOODLE_SKIP_BOOTSTRAP=1.
if [ "${MOODLE_CRON_INLINE:-1}" = "1" ]; then
    echo "[aula] arrancando el cron en segundo plano"
    /var/www/html/docker/cron.sh &
fi

echo "[aula] listo, arrancando el servidor web"

exec "$@"
