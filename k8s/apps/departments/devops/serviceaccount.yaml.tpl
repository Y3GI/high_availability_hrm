apiVersion: v1
kind: ServiceAccount
metadata:
    name: devops-sa
    namespace: devops
    annotations:
        iam.gke.io/gcp-service-account: ${ENV}-devops-sa@${GOOGLE_CLOUD_PROJECT}.iam.gserviceaccount.com