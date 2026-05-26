apiVersion: v1
kind: Pod
metadata:
  name: ${EMPLOYEE_ID}
  namespace: ${DEPARTMENT}
  labels:
    employee-id: "${EMPLOYEE_ID}"
    department: "${DEPARTMENT}"
    managed-by: "hrm-cloud-function"
spec:
  serviceAccountName: ${DEPARTMENT}-sa
  restartPolicy: Always
  containers:
    - name: workspace
      image:  europe-west4-docker.pkg.dev/${GOOGLE_CLOUD_PROJECT}/hrm/${DEPARTMENT}-workspace:latest
      resources:
        requests:
          cpu: 100m
          memory: 128Mi
        limits:
          cpu: 500m
          memory: 512Mi
      env:
        - name: PASSWORD
          valueFrom:
            secretKeyRef:
              name: ${EMPLOYEE_ID}-workspace-secret
              key: password