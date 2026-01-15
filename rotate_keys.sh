#!/bin/bash
set -euo pipefail

# Rotation policy
ROTATION_DAYS=1
MAX_KEYS=2
CONFIG_FILE="sa_config.env"
NOW=$(date +%s)

while IFS=',' read -r PROJECT_ID SA_EMAIL
do
  # Skip empty lines or commented lines
  [[ -z "${PROJECT_ID:-}" || "${PROJECT_ID}" =~ ^# ]] && continue

  echo "🔍 Processing $SA_EMAIL in $PROJECT_ID"

  # Log and update project
  echo "➡️ Updating gcloud project to '$PROJECT_ID'"
  gcloud config set project "$PROJECT_ID" >/dev/null

  SECRET_ID=$(echo "$SA_EMAIL" | sed 's/@/-/g;s/\./-/g')

  # List keys sorted by validAfterTime (oldest first)
  echo "📋 Listing existing keys (raw):"
  KEYS=$(gcloud iam service-accounts keys list \
    --iam-account="$SA_EMAIL" \
    --sort-by=validAfterTime \
    --format="value(name,validAfterTime)" || true)

  if [ -z "$KEYS" ]; then
    echo "⚠️ No existing keys found for $SA_EMAIL — creating initial key"
    KEY_FILE=$(mktemp)

    echo "🔑 Creating new key for $SA_EMAIL"
    gcloud iam service-accounts keys create "$KEY_FILE" \
      --iam-account="$SA_EMAIL"

    echo "🔐 Ensuring secret '$SECRET_ID' exists"
    gcloud secrets describe "$SECRET_ID" >/dev/null 2>&1 || \
      gcloud secrets create "$SECRET_ID" --replication-policy=automatic

    echo "➕ Adding new key to secret '$SECRET_ID'"
    gcloud secrets versions add "$SECRET_ID" --data-file="$KEY_FILE"
    rm -f "$KEY_FILE"

    echo "✅ Created first key for $SA_EMAIL and stored in secret $SECRET_ID"
    echo "📋 Current keys (table):"
    gcloud iam service-accounts keys list \
      --iam-account="$SA_EMAIL" \
      --format="table(name,validAfterTime)" || true

    # Move to next service account after creating first key
    continue
  fi

  echo "$KEYS" | sed -n '1,5p' || true

  # Determine age of the oldest key (first line after sorting ascending)
  OLDEST_TIME=$(echo "$KEYS" | head -n1 | awk '{print $2}')
  if [ -n "$OLDEST_TIME" ]; then
    OLDEST_SEC=$(date -d "$OLDEST_TIME" +%s)
    AGE_DAYS=$(( (NOW - OLDEST_SEC) / 86400 ))
    echo "⏱ Oldest key age: ${AGE_DAYS} days (created: $OLDEST_TIME)"
  else
    # Defensive fallback (shouldn't happen because empty KEYS handled above)
    AGE_DAYS=$ROTATION_DAYS
    echo "⚠️ Could not determine oldest key time; forcing rotation path"
  fi

  if [ "$AGE_DAYS" -lt "$ROTATION_DAYS" ]; then
    echo "⏩ Rotation not required (age ${AGE_DAYS} < ${ROTATION_DAYS})"
    continue
  fi

  echo "🔑 Creating new key (rotation) for $SA_EMAIL"
  KEY_FILE=$(mktemp)

  gcloud iam service-accounts keys create "$KEY_FILE" \
    --iam-account="$SA_EMAIL"

  echo "🔐 Ensuring secret '$SECRET_ID' exists"
  gcloud secrets describe "$SECRET_ID" >/dev/null 2>&1 || \
    gcloud secrets create "$SECRET_ID" --replication-policy=automatic

  echo "➕ Adding rotated key to secret '$SECRET_ID'"
  gcloud secrets versions add "$SECRET_ID" --data-file="$KEY_FILE"
  rm -f "$KEY_FILE"

  echo "📋 Listing keys (names only) after creation:"
  KEY_NAMES=$(gcloud iam service-accounts keys list \
    --iam-account="$SA_EMAIL" \
    --sort-by=validAfterTime \
    --format="value(name)" || true)

  echo "$KEY_NAMES" || echo "(no keys listed)"

  # Count non-empty lines only
  COUNT=$(echo "$KEY_NAMES" | sed '/^\s*$/d' | wc -l | tr -d ' ')
  echo "🔢 Key count: $COUNT (max allowed: $MAX_KEYS)"

  if [ "$COUNT" -gt "$MAX_KEYS" ]; then
    DELETE_COUNT=$((COUNT - MAX_KEYS))
    echo "🗑 Need to delete $DELETE_COUNT old key(s)"
    # Delete the oldest keys (head of sorted list)
    echo "$KEY_NAMES" | head -n "$DELETE_COUNT" | while read -r key; do
      [ -z "$key" ] && continue
      echo "🗑 Deleting old key $key"
      gcloud iam service-accounts keys delete "$key" \
        --iam-account="$SA_EMAIL" --quiet || \
        echo "❗ Failed to delete key $key"
    done
  else
    echo "✅ No old keys to delete"
  fi

  echo "✅ Completed for $SA_EMAIL"
done < "$CONFIG_FILE"
