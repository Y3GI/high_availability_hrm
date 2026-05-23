apiVersion: v1
kind: serviceAccount
metadata:
    name: software-sa
    namespace: software
    annotations:
        iam.gke.io/gcp-service-account: ${ENV}-software-sa@${GOOGLE_CLOUD_PROJECT}.iam.gserviceaccount.com