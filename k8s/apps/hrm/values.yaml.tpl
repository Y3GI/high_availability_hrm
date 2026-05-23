namespace: hrm
domain: hrm.domain.com
project: "$GOOGLE_CLOUD_PROJECT"

serviceAccount:
    name: hrm-app
    gcpServiceAccountEmail: "$APP_SA_EMAIL"

iap:
    secretName: iap-oauth-secret

image: 
    repository: europe-west4-docker.pkg.dev/$GOOGLE_CLOUD_PROJECT/hrm/hrm-app
    tag: latest
    pullPolicy: Always

resources:
    requests:
        cpu: 100m
        memory: 128Mi
    limits:
        cpu: 500m
        memory: 512Mi

cloudSql:
  instanceConnectionName: "$INSTANCE_CONNECTION_NAME"
