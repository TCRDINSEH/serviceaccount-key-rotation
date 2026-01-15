#!/bin/bash
set -e

ROTATION_DAYS=1
MAX_KEYS=2
CONFIG_FILE="sa_config.env"
NOW=$(date +%s)

while IFS=',' read -r PROJECT_ID SA_EMAIL
do
  [[ -z "$PROJECT_ID" || "$PROJECT_ID" =~ ^# ]] && continue

  echo "🔍 Processing $SA_EMAIL in $PROJECT_ID"

  gcloud config set project "$PROJECT_ID" >/dev/null

  SECRET_ID=$(echo "$SA_EMAIL" | sed 's/@/-/g;s/\./-/g')

  KEYS=$(gcloud iam service-accounts keys list \
    --iam-account="$SA_EMAIL" \
    --format="value(name,validAfterTime)")

  if [ -n "$KEYS" ]; then
    OLDEST_TIME=$(echo "$KEYS" | head -n1 | awk '{print $2}')
    OLDEST_SEC=$(date -d "$OLDEST_TIME" +%s)
    AGE_DAYS=$(( (NOW - OLDEST_SEC) / 86400 ))
  else
    AGE_DAYS=$ROTATION_DAYS
  fi

  if [ "$AGE_DAYS" -lt "$ROTATION_DAYS" ]; then
    echo "⏩ Rotation not required"
    continue
  fi

  echo "🔑 Creating new key"
  KEY_FILE=$(mktemp)

  gcloud iam service-accounts keys create "$KEY_FILE" \
    --iam-account="$SA_EMAIL"

  gcloud secrets describe "$SECRET_ID" >/dev/null 2>&1 || \
    gcloud secrets create "$SECRET_ID" --replication-policy=automatic

  gcloud secrets versions add "$SECRET_ID" --data-file="$KEY_FILE"
  rm -f "$KEY_FILE"

  KEY_NAMES=$(gcloud iam service-accounts keys list \
    --iam-account="$SA_EMAIL" \
    --format="value(name)")

  COUNT=$(echo "$KEY_NAMES" | wc -l)

  if [ "$COUNT" -gt "$MAX_KEYS" ]; then
    DELETE_COUNT=$((COUNT - MAX_KEYS))
    echo "$KEY_NAMES" | head -n "$DELETE_COUNT" | while read key; do
      echo "🗑 Deleting old key $key"
      gcloud iam service-accounts keys delete "$key" \
        --iam-account="$SA_EMAIL" --quiet
    done
  fi

  echo "✅ Completed for $SA_EMAIL"
done < "$CONFIG_FILE"
