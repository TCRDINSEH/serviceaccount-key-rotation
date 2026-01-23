#!/bin/bash
set -euo pipefail

########################################
# Configuration
########################################
ROTATION_DAYS=45
CONFIG_FILE="sa_config.env"
NOW=$(date +%s)

log() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"
}

########################################
# Main
########################################
while IFS=',' read -r PROJECT_ID SA_EMAIL; do
  [[ -z "${PROJECT_ID:-}" || "$PROJECT_ID" =~ ^# ]] && continue

  log "Processing $SA_EMAIL in $PROJECT_ID"

  gcloud config set project "$PROJECT_ID" >/dev/null

  ########################################
  # List user-managed keys (oldest → newest)
  ########################################
  KEYS=$(gcloud iam service-accounts keys list \
    --iam-account="$SA_EMAIL" \
    --managed-by=user \
    --sort-by=validAfterTime \
    --format="value(name,validAfterTime)" || true)

  ########################################
  # Decide if rotation is needed
  ########################################
  ROTATE=true

  if [[ -n "$KEYS" ]]; then
    NEWEST_TIME=$(echo "$KEYS" | tail -n1 | awk '{print $2}')
    NEWEST_SEC=$(date -d "$NEWEST_TIME" +%s)
    AGE_DAYS=$(( (NOW - NEWEST_SEC) / 86400 ))

    log "Newest key age: ${AGE_DAYS} days"

    if [[ "$AGE_DAYS" -lt "$ROTATION_DAYS" ]]; then
      log "Rotation not required"
      ROTATE=false
    fi
  fi

  ########################################
  # Create new key if required
  ########################################
  if [[ "$ROTATE" == true ]]; then
    log "Creating new key"
    gcloud iam service-accounts keys create /tmp/key.json \
      --iam-account="$SA_EMAIL"
  fi

  ########################################
  # Delete all old keys, keep newest only
  ########################################
  KEY_NAMES=$(gcloud iam service-accounts keys list \
    --iam-account="$SA_EMAIL" \
    --managed-by=user \
    --sort-by=validAfterTime \
    --format="value(name)" || true)

  COUNT=$(echo "$KEY_NAMES" | sed '/^\s*$/d' | wc -l)

  if [[ "$COUNT" -gt 1 ]]; then
    log "Deleting old keys"
    echo "$KEY_NAMES" | head -n -1 | while read -r KEY; do
      log "Deleting $KEY"
      gcloud iam service-accounts keys delete "$KEY" \
        --iam-account="$SA_EMAIL" --quiet
    done
  else
    log "Only one key exists — nothing to delete"
  fi

  log "Completed $SA_EMAIL"
done < "$CONFIG_FILE"

log "All service accounts processed"
