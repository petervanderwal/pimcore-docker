ARG PHP_VERSION="8.2"
ARG DEBIAN_VERSION="bullseye"

FROM php:${PHP_VERSION}-fpm-${DEBIAN_VERSION} as pimcore_php_fpm

RUN set -eux; \
    DPKG_ARCH="$(dpkg --print-architecture)"; \
    apt-get update; \
    echo "deb http://deb.debian.org/debian bullseye-backports main" > /etc/apt/sources.list.d/backports.list; \
    echo "deb https://www.deb-multimedia.org bullseye main non-free" > /etc/apt/sources.list.d/deb-multimedia.list; \
    apt-get update -oAcquire::AllowInsecureRepositories=true; \
    apt-get install -y --allow-unauthenticated imagemagick-7 libmagickwand-7-dev; \
    \
    # tools used by Pimcore
    apt-get install -y --allow-unauthenticated \
        ffmpeg ghostscript jpegoptim exiftool poppler-utils optipng pngquant webp graphviz locales locales-all; \
    \
    # dependencies fór building PHP extensions
    apt-get install -y --allow-unauthenticated \
        libicu-dev zlib1g-dev libpng-dev libwebp-dev libjpeg62-turbo-dev libfreetype6-dev libzip-dev; \
    \
    docker-php-ext-configure pcntl --enable-pcntl; \
    docker-php-ext-configure gd -enable-gd --with-freetype --with-jpeg --with-webp; \
    docker-php-ext-install pcntl intl bcmath pdo_mysql exif zip opcache sockets gd; \
    \
    pecl install -f apcu redis imagick; \
    docker-php-ext-enable redis apcu imagick; \
    ldconfig /usr/local/lib; \
    \
    sync;

#RUN set -eux; \
#    cd /tmp; \
#    apt-get install -y
#    wget https://imagemagick.org/archive/ImageMagick.tar.gz; \
#        tar -xvf ImageMagick.tar.gz; \
#        cd ImageMagick-7.*; \
#        ./configure; \
#        make --jobs=$(nproc); \
#        make V=0; \
#        make install; \
#        cd ..; \
#        rm -rf ImageMagick*; \
#    \
#    pecl install -f imagick; \
#    docker-php-ext-enable imagick; \
#    ldconfig /usr/local/lib; \
#    \
#    sync;

RUN set -eux; \
    apt-get autoremove -y; \
            apt-get remove -y autoconf automake libtool nasm make cmake ninja-build pkg-config build-essential g++; \
            apt-get clean; \
            rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /usr/share/doc/* ~/.composer || true; \
    sync;

RUN echo "upload_max_filesize = 100M" >> /usr/local/etc/php/conf.d/20-pimcore.ini; \
    echo "memory_limit = 256M" >> /usr/local/etc/php/conf.d/20-pimcore.ini; \
    echo "post_max_size = 100M" >> /usr/local/etc/php/conf.d/20-pimcore.ini

ENV COMPOSER_ALLOW_SUPERUSER 1
ENV COMPOSER_MEMORY_LIMIT -1
COPY --from=composer/composer:2-bin /composer /usr/bin/composer

WORKDIR /var/www/html

CMD ["php-fpm"]

FROM pimcore_php_fpm as pimcore_php_debug

RUN apt-get update; \
    apt-get install -y --no-install-recommends \
      autoconf automake libtool nasm make pkg-config libz-dev build-essential g++ iproute2; \
    pecl install xdebug; \
    docker-php-ext-enable xdebug; \
    apt-get autoremove -y; \
    apt-get remove -y autoconf automake libtool nasm make pkg-config libz-dev build-essential g++; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /usr/share/doc/* ~/.composer || true

# allow container to run as custom user, this won't work otherwise because config is changed in entrypoint.sh
RUN chmod -R 0777 /usr/local/etc/php/conf.d

ENV PHP_IDE_CONFIG serverName=localhost

COPY files/entrypoint.sh /usr/local/bin
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["php-fpm"]

FROM pimcore_php_fpm as pimcore_php_supervisord

RUN apt-get update && apt-get install -y supervisor cron
COPY files/supervisord.conf /etc/supervisor/supervisord.conf

RUN chmod gu+rw /var/run
RUN chmod gu+s /usr/sbin/cron

CMD ["/usr/bin/supervisord"]
