#!/bin/bash
set -euo pipefail

############################################
# Configuration
############################################
ROTATION_DAYS=1        # Rotate if oldest key >= this age
MAX_KEYS=2             # Maximum user-managed keys allowed
CONFIG_FILE="sa_config.env"
NOW=$(date +%s)

############################################
# Main loop
############################################
while IFS=',' read -r PROJECT_ID SA_EMAIL
do
  # Skip empty or commented lines
  [[ -z "${PROJECT_ID:-}" || "$PROJECT_ID" =~ ^# ]] && continue

  echo "=================================================="
  echo "🔍 Processing $SA_EMAIL in project $PROJECT_ID"

  ############################################
  # Set project
  ############################################
  echo "➡️ Setting gcloud project to '$PROJECT_ID'"
  gcloud config set project "$PROJECT_ID" >/dev/null

  ############################################
  # Secret name (stable + valid)
  ############################################
  SECRET_ID=$(echo "$SA_EMAIL" | sed 's/@/-/g; s/\./-/g')

  ############################################
  # List USER-MANAGED keys only
  ############################################
  echo "📋 Listing existing USER-MANAGED keys:"
  KEYS=$(gcloud iam service-accounts keys list \
    --iam-account="$SA_EMAIL" \
    --managed-by=user \
    --sort-by=validAfterTime \
    --format="value(name,validAfterTime)" || true)

  ############################################
  # Case 1: No user-managed keys exist
  ############################################
  if [[ -z "$KEYS" ]]; then
    echo "⚠️ No user-managed keys found — creating initial key"

    KEY_FILE=$(mktemp)

    echo "🔑 Creating first key"
    gcloud iam service-accounts keys create "$KEY_FILE" \
      --iam-account="$SA_EMAIL"

    echo "🔐 Ensuring secret '$SECRET_ID' exists"
    gcloud secrets describe "$SECRET_ID" >/dev/null 2>&1 || \
      gcloud secrets create "$SECRET_ID" --replication-policy=automatic

    echo "➕ Storing key in Secret Manager"
    gcloud secrets versions add "$SECRET_ID" --data-file="$KEY_FILE"

    rm -f "$KEY_FILE"

    echo "✅ Initial key created and stored"
    continue
  fi

  ############################################
  # Display existing keys
  ############################################
  echo "$KEYS"

  ############################################
  # Determine oldest key age
  ############################################
  OLDEST_TIME=$(echo "$KEYS" | head -n1 | awk '{print $2}')
  OLDEST_SEC=$(date -d "$OLDEST_TIME" +%s)
  AGE_DAYS=$(( (NOW - OLDEST_SEC) / 86400 ))

  echo "⏱ Oldest key age: ${AGE_DAYS} days (created: $OLDEST_TIME)"

  ############################################
  # Skip rotation if not needed
  ############################################
  if [[ "$AGE_DAYS" -lt "$ROTATION_DAYS" ]]; then
    echo "⏩ Rotation not required"
    continue
  fi

  ############################################
  # Rotate key
  ############################################
  echo "🔁 Rotating key"

  KEY_FILE=$(mktemp)

  gcloud iam service-accounts keys create "$KEY_FILE" \
    --iam-account="$SA_EMAIL"

  echo "🔐 Ensuring secret '$SECRET_ID' exists"
  gcloud secrets describe "$SECRET_ID" >/dev/null 2>&1 || \
    gcloud secrets create "$SECRET_ID" --replication-policy=automatic

  echo "➕ Adding rotated key to Secret Manager"
  gcloud secrets versions add "$SECRET_ID" --data-file="$KEY_FILE"

  rm -f "$KEY_FILE"

  ############################################
  # List keys after rotation
  ############################################
  KEY_NAMES=$(gcloud iam service-accounts keys list \
    --iam-account="$SA_EMAIL" \
    --managed-by=user \
    --sort-by=validAfterTime \
    --format="value(name)" || true)

  COUNT=$(echo "$KEY_NAMES" | sed '/^\s*$/d' | wc -l | tr -d ' ')
  echo "🔢 User-managed key count: $COUNT"

  ############################################
  # Delete old keys if exceeding MAX_KEYS
  ############################################
  if [[ "$COUNT" -gt "$MAX_KEYS" ]]; then
    DELETE_COUNT=$((COUNT - MAX_KEYS))
    echo "🗑 Deleting $DELETE_COUNT old key(s)"

    echo "$KEY_NAMES" | head -n "$DELETE_COUNT" | while read -r KEY; do
      [[ -z "$KEY" ]] && continue
      echo "🗑 Deleting key $KEY"
      gcloud iam service-accounts keys delete "$KEY" \
        --iam-account="$SA_EMAIL" \
        --quiet
    done
  else
    echo "✅ No old keys to delete"
  fi

  echo "✅ Completed rotation for $SA_EMAIL"

done < "$CONFIG_FILE"

echo "🎉 All service accounts processed successfully"
