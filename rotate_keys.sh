#!/bin/bash
set -euo pipefail

PROJECT_ID="formal-cascade-484404-g4"
SA_EMAIL="tf-jenkins@formal-cascade-484404-g4.iam.gserviceaccount.com"
ROTATION_DAYS=45
NOW=$(date +%s)

echo "🔍 Checking keys for $SA_EMAIL"

KEYS=$(gcloud iam service-accounts keys list \
  --project="$PROJECT_ID" \
  --iam-account="$SA_EMAIL" \
  --managed-by=user \
  --sort-by=validAfterTime \
  --format="value(name,validAfterTime)" || true)

# Bootstrap
if [[ -z "$KEYS" ]]; then
  echo "⚠️ No keys found — creating initial key"
  gcloud iam service-accounts keys create sa-key.json \
    --project="$PROJECT_ID" \
    --iam-account="$SA_EMAIL"
  rm -f sa-key.json
  exit 0
fi

OLDEST_KEY=$(echo "$KEYS" | head -n1)
KEY_NAME=$(awk '{print $1}' <<< "$OLDEST_KEY")
KEY_TIME=$(awk '{print $2}' <<< "$OLDEST_KEY")

KEY_SEC=$(date -d "$KEY_TIME" +%s)
AGE_DAYS=$(( (NOW - KEY_SEC) / 86400 ))

echo "⏱ Oldest key age: $AGE_DAYS days"

if [[ "$AGE_DAYS" -lt "$ROTATION_DAYS" ]]; then
  echo "✅ Rotation not required"
  exit 0
fi

echo "🔁 Rotating key"

gcloud iam service-accounts keys create sa-key.json \
  --project="$PROJECT_ID" \
  --iam-account="$SA_EMAIL"

gcloud iam service-accounts keys delete "$KEY_NAME" \
  --project="$PROJECT_ID" \
  --iam-account="$SA_EMAIL" \
  --quiet

rm -f sa-key.json
echo "🎉 Key rotation completed"
