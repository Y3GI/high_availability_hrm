apiVersion: v1
kind: serviceAccount
metadata:
    name: db-engineering-sa
    namespace: db-engineering
    annotations:
        iam.gke.io/gcp-service-account: ${ENV}-db-engineering-sa@${GOOGLE_CLOUD_PROJECT}.iam.gserviceaccount.com