FROM drupal:11-php8.3-fpm
RUN pecl install redis && docker-php-ext-enable redis
