name: Security

on:
  schedule:
    - cron: '0 9 * * 1'
  workflow_dispatch:

jobs:
  composer-audit:
    name: Composer Security Audit
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
      - name: Composer audit
        run: composer audit
        working-directory: {{DRUPAL_ROOT}}

  drupal-security:
    name: Drupal Security Advisories
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
      - name: Check Drupal security advisories
        run: ./vendor/bin/drush pm:security
        working-directory: {{DRUPAL_ROOT}}
        continue-on-error: true
