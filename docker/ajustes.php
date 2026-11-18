<?php
// Ajustes del aula que se aplican en cada arranque del contenedor.
//
// Va en un fichero y no como una linea suelta dentro del entrypoint porque un
// PHP con comillas escapadas dentro de un `su -c "..."` es imposible de leer y
// se rompe al primer cambio.

define('CLI_SCRIPT', true);

require(__DIR__ . '/../config.php');
require_once($CFG->dirroot . '/user/lib.php');

$correo = getenv('MOODLE_ADMIN_EMAIL');

if ($correo === false || trim($correo) === '') {
    exit(0);
}

$correo = \core_text::strtolower(trim($correo));

if (!validate_email($correo)) {
    fwrite(STDERR, "[aula] MOODLE_ADMIN_EMAIL no es una direccion valida: {$correo}\n");
    exit(1);
}

$admin = get_admin();

if (!$admin) {
    fwrite(STDERR, "[aula] no hay cuenta de administracion\n");
    exit(1);
}

if ($admin->email === $correo) {
    echo "[aula] el correo del administrador ya es {$correo}\n";
    exit(0);
}

// Otra cuenta con ese correo impediria recuperar la contrasena: Moodle no sabria
// a cual de las dos mandar el enlace.
$repetido = $DB->get_record_select('user',
    'LOWER(email) = ? AND id <> ? AND deleted = 0', [$correo, $admin->id], 'id, username');

if ($repetido) {
    fwrite(STDERR, "[aula] el correo {$correo} ya lo usa la cuenta '{$repetido->username}';"
        . " no se cambia para no dejar dos cuentas con el mismo correo\n");
    exit(1);
}

$anterior = $admin->email;
$admin->email = $correo;
user_update_user($admin, false, false);

echo "[aula] correo del administrador: {$anterior} -> {$correo}\n";
