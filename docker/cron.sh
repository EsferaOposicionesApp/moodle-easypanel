#!/bin/sh
# Cron de Moodle.
#
# Se despliega como un servicio aparte en Easypanel, con la MISMA imagen y las
# mismas variables, pero con este comando en vez del servidor web. Separarlo
# tiene una razón práctica: una tarea larga (una restauración, un envío masivo)
# no compite con las peticiones de los alumnos, y se puede parar el cron sin
# tirar el aula.
#
# Moodle avisa en todas sus pantallas si el cron lleva más de una hora sin
# correr, así que si esto no está levantado se nota enseguida.

set -e

INTERVALO="${MOODLE_CRON_INTERVAL:-60}"

echo "Cron de Moodle cada ${INTERVALO}s"

while true; do
    su -s /bin/sh -c "php /var/www/html/admin/cli/cron.php --keep-alive=0" www-data || \
        echo "El cron ha terminado con error; se reintenta en ${INTERVALO}s"
    sleep "$INTERVALO"
done
