#!/bin/bash

# Copy sample data from production to development database
# This script copies 500 recent cases with their associated offenders

set -e

echo "🔄 Copying sample data from production to development..."

# Production database details (update these)
PROD_HOST="${PROD_DB_HOST:-your-production-host.com}"
PROD_PORT="${PROD_DB_PORT:-5432}"
PROD_DB="${PROD_DB_NAME:-ehs_enforcement_prod}"
PROD_USER="${PROD_DB_USER:-postgres}"

# Development database details
DEV_HOST="localhost"
DEV_PORT="5434"
DEV_DB="sertantai_enforcement_dev"
DEV_USER="postgres"
DEV_PASSWORD="postgres"

# Temporary file for data
TEMP_FILE="/tmp/ehs_prod_sample_$(date +%Y%m%d_%H%M%S).sql"

echo "📦 Dumping 500 recent cases and related data from production..."

# Dump query that gets 500 recent cases with their offenders
ssh $PROD_USER@$PROD_HOST "PGPASSWORD=\$PROD_DB_PASSWORD pg_dump -h $PROD_HOST -p $PROD_PORT -U $PROD_USER -d $PROD_DB \
  --table=cases \
  --table=offenders \
  --table=agencies \
  --data-only \
  --column-inserts \
  --on-conflict-do-nothing \
  --where=\"id IN (SELECT id FROM cases ORDER BY offence_action_date DESC LIMIT 500)\"" > $TEMP_FILE

echo "📥 Loading data into development database..."

PGPASSWORD=$DEV_PASSWORD psql -h $DEV_HOST -p $DEV_PORT -U $DEV_USER -d $DEV_DB < $TEMP_FILE

echo "✅ Successfully copied sample data!"
echo "📊 Checking counts..."

PGPASSWORD=$DEV_PASSWORD psql -h $DEV_HOST -p $DEV_PORT -U $DEV_USER -d $DEV_DB -c "
SELECT
  'Cases' as table, COUNT(*) as count FROM cases
UNION ALL
SELECT
  'Offenders' as table, COUNT(*) as count FROM offenders
UNION ALL
SELECT
  'Agencies' as table, COUNT(*) as count FROM agencies;
"

# Cleanup
rm $TEMP_FILE

echo "🎉 Done! You can now test with real data."
