gcloud builds submit \
  --tag gcr.io/formal-cascade-484404-g4/sa-key-rotator

gcloud container images list \
  --repository=gcr.io/formal-cascade-484404-g4


gcloud run jobs create sa-key-rotation \
  --image=gcr.io/formal-cascade-484404-g4/sa-key-rotator \
  --region=us-central1 \
  --service-account=sa-key-rotator@formal-cascade-484404-g4.iam.gserviceaccount.com

gcloud run jobs execute sa-key-rotation


gcloud scheduler jobs create http sa-key-rotation-schedule   --project=formal-cascade-484404-g4   --location=us-central1   --schedule="*/2 * * * *"   --time-zone="UTC"   --http-method=POST   --uri="https://us-central1-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/formal-cascade-484404-g4/jobs/sa-key-rotation:run"   --oauth-service-account-email=sa-key-rotator@formal-cascade-484404-g4.iam.gserviceaccount.com   --oauth-token-scope="https://www.googleapis.com/auth/cloud-platform"



gcloud run jobs deploy sa-key-rotation-job \
  --source . \
  --region us-central1 \
  --service-account sa-key-rotator@formal-cascade-484404-g4.iam.gserviceaccount.com


