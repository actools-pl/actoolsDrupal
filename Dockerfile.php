FROM drupal:11-php8.3-fpm
RUN apt-get update -qq && apt-get install -y -qq git unzip && rm -rf /var/lib/apt/lists/*
RUN pecl install redis && docker-php-ext-enable redis
