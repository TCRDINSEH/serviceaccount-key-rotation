#!/bin/bash
set -euo pipefail

############################################
# Global Configuration
############################################
PROJECT_ID="formal-cascade-484404-g4"
ROTATION_DAYS=0        # Rotate keys older than this
MAX_KEYS=1              # Keep only 1 active user-managed key
NOW=$(date +%s)

############################################
# Service Accounts (ONE PER LINE)
############################################
SERVICE_ACCOUNTS=(
  "tf-jenkins@formal-cascade-484404-g4.iam.gserviceaccount.com"
)

############################################
# Set project
############################################
gcloud config set project "$PROJECT_ID" >/dev/null

############################################
# Main loop
############################################
for SA_EMAIL in "${SERVICE_ACCOUNTS[@]}"; do
  echo "=================================================="
  echo "🔍 Processing $SA_EMAIL"

  SA_NAME="${SA_EMAIL%@*}"
  SECRET_ID="${SA_NAME}-sakey"

  ############################################
  # List USER-MANAGED keys (oldest first)
  ############################################
  KEYS=$(gcloud iam service-accounts keys list \
    --iam-account="$SA_EMAIL" \
    --managed-by=user \
    --sort-by=validAfterTime \
    --format="value(name.basename(),validAfterTime)" || true)

  ############################################
  # Bootstrap if no keys exist
  ############################################
  if [[ -z "$KEYS" ]]; then
    echo "⚠️ No keys found — creating initial key"

    KEY_FILE=$(mktemp)
    chmod 600 "$KEY_FILE"

    gcloud iam service-accounts keys create "$KEY_FILE" \
      --iam-account="$SA_EMAIL"

    gcloud secrets describe "$SECRET_ID" >/dev/null 2>&1 || \
      gcloud secrets create "$SECRET_ID" \
        --replication-policy=automatic

    gcloud secrets versions add "$SECRET_ID" --data-file="$KEY_FILE"
    rm -f "$KEY_FILE"

    echo "✅ Initial key created and stored"
    continue
  fi

  ############################################
  # Oldest key age
  ############################################
  OLDEST_TIME=$(echo "$KEYS" | head -n1 | awk '{print $2}')
  OLDEST_SEC=$(date -d "$OLDEST_TIME" +%s)
  AGE_DAYS=$(( (NOW - OLDEST_SEC) / 86400 ))

  echo "⏱ Oldest key age: ${AGE_DAYS} days"

  if [[ "$AGE_DAYS" -lt "$ROTATION_DAYS" ]]; then
    echo "⏩ Rotation not required"
    continue
  fi

  ############################################
  # Rotate key
  ############################################
  echo "🔁 Rotating key"

  KEY_FILE=$(mktemp)
  chmod 600 "$KEY_FILE"

  gcloud iam service-accounts keys create "$KEY_FILE" \
    --iam-account="$SA_EMAIL"

  gcloud secrets versions add "$SECRET_ID" --data-file="$KEY_FILE"
  rm -f "$KEY_FILE"

############################################
# Enforce MAX_KEYS strictly (KEEP NEWEST ONLY)
############################################
KEY_IDS=$(gcloud iam service-accounts keys list \
  --iam-account="$SA_EMAIL" \
  --managed-by=user \
  --sort-by=validAfterTime \
  --format="value(name.basename())")

COUNT=$(echo "$KEY_IDS" | sed '/^\s*$/d' | wc -l | tr -d ' ')
echo "🔢 Active user-managed keys: $COUNT"

if [[ "$COUNT" -gt "$MAX_KEYS" ]]; then
  echo "🗑 Deleting all old keys, keeping newest only"

  # Delete everything EXCEPT the newest key (last line)
  echo "$KEY_IDS" | head -n -"$MAX_KEYS" | while read -r KEY_ID; do
    [[ -z "$KEY_ID" ]] && continue
    echo "🗑 Deleting key $KEY_ID"
    gcloud iam service-accounts keys delete "$KEY_ID" \
      --iam-account="$SA_EMAIL" \
      --quiet
  done
fi


  echo "✅ Completed rotation for $SA_EMAIL"
done

echo "🎉 All service accounts processed successfully"
