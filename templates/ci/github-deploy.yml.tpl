name: Deploy

on:
  push:
    branches: [main]

jobs:
  deploy:
    name: Deploy to Production
    runs-on: ubuntu-latest
    steps:
      - name: Deploy to {{BASE_DOMAIN}}
        uses: appleboy/ssh-action@master
        with:
          host: {{BASE_DOMAIN}}
          username: actools
          key: ${{ secrets.DEPLOY_SSH_KEY }}
          script: |
            set -e
            echo "=== Deploying to {{BASE_DOMAIN}} ==="

            cd /home/actools

            echo "Step 1: Pre-deploy snapshot..."
            actools backup

            echo "Step 2: Pull latest images..."
            docker compose pull db redis php_prod

            echo "Step 3: Update containers..."
            docker compose up -d

            echo "Step 4: Run database updates..."
            docker compose exec -T php_prod bash -c \
              "cd /var/www/html/prod && ./vendor/bin/drush updb --yes && ./vendor/bin/drush cr"

            echo "Step 5: Health check..."
            sleep 10
            STATUS=$(curl -sso /dev/null -w "%{http_code}" --max-time 10 https://{{BASE_DOMAIN}})
            if [ "$STATUS" != "200" ]; then
              echo "HEALTH CHECK FAILED: HTTP $STATUS"
              exit 1
            fi

            echo "=== Deploy complete: {{BASE_DOMAIN}} ==="
