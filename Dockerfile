# Moodle en Easypanel · plantilla
#
# Descarga Moodle oficial (github.com/moodle/moodle) en la versión de
# MOODLE_VERSION y lo deja listo para arrancar. Para actualizar Moodle:
# cambia el número de esta línea, guarda y pulsa Deploy en Easypanel.
FROM php:8.4-apache

# versión de Moodle que se descarga al compilar
ARG MOODLE_VERSION=v5.3.1

# Paquetes del sistema que necesitan las extensiones de PHP.
RUN apt-get update && apt-get install -y --no-install-recommends \
        libicu-dev libzip-dev libpng-dev libjpeg62-turbo-dev libfreetype6-dev \
        libxml2-dev libsodium-dev libcurl4-openssl-dev zlib1g-dev \
        curl unzip ghostscript ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Extensiones que Moodle 5 exige (sodium, intl y zip son obligatorias).
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j"$(nproc)" gd intl zip soap exif opcache mysqli pdo_mysql sodium

RUN a2enmod rewrite headers expires deflate

WORKDIR /var/www/html

# Moodle oficial, en la versión indicada arriba.
RUN curl -fsSL "https://github.com/moodle/moodle/archive/refs/tags/${MOODLE_VERSION}.tar.gz" \
        | tar xz --strip-components=1 -C /var/www/html

COPY docker/php-moodle.ini /usr/local/etc/php/conf.d/zz-moodle.ini
COPY docker/apache-moodle.conf /etc/apache2/sites-available/000-default.conf
COPY docker/ /var/www/html/docker/

# moodledata vive fuera del código: en Easypanel se monta aquí un volumen.
# Sin volumen, cada despliegue borraría los ficheros de los alumnos.
RUN mkdir -p /var/moodledata \
    && chown -R www-data:www-data /var/moodledata /var/www/html \
    && chmod +x /var/www/html/docker/entrypoint.sh /var/www/html/docker/cron.sh

EXPOSE 80

ENTRYPOINT ["/var/www/html/docker/entrypoint.sh"]
CMD ["apache2-foreground"]
