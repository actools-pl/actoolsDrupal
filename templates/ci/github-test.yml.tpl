name: Test

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main, develop]

jobs:
  phpcs:
    name: PHP Code Standards
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Setup PHP
        uses: shivammathur/setup-php@v2
        with:
          php-version: '{{PHP_VERSION}}'
          tools: composer
      - name: Install dependencies
        run: composer install --no-interaction --prefer-dist
        working-directory: {{DRUPAL_ROOT}}
      - name: PHP CodeSniffer
        run: ./vendor/bin/phpcs --standard=Drupal,DrupalPractice web/modules/custom
        working-directory: {{DRUPAL_ROOT}}
        continue-on-error: true

  phpstan:
    name: Static Analysis
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Setup PHP
        uses: shivammathur/setup-php@v2
        with:
          php-version: '{{PHP_VERSION}}'
          tools: composer
      - name: Install dependencies
        run: composer install --no-interaction --prefer-dist
        working-directory: {{DRUPAL_ROOT}}
      - name: PHPStan
        run: ./vendor/bin/phpstan analyse web/modules/custom --level=1
        working-directory: {{DRUPAL_ROOT}}
        continue-on-error: true

  composer-validate:
    name: Composer Validate
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Setup PHP
        uses: shivammathur/setup-php@v2
        with:
          php-version: '{{PHP_VERSION}}'
      - name: Validate composer.json
        run: composer validate --strict
        working-directory: {{DRUPAL_ROOT}}
