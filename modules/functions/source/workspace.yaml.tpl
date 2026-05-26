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
      image: europe-west4-docker.pkg.dev/${GOOGLE_CLOUD_PROJECT}/hrm/${DEPARTMENT}-workspace:latest
      args:
        - --bind-addr=0.0.0.0:8080
        - --base-path=/workspace/${EMPLOYEE_ID}
        - /home/coder
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
      ports:
        - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: ${EMPLOYEE_ID}-workspace
  namespace: ${DEPARTMENT}
  annotations:
    cloud.google.com/neg: '{"ingress": true}'
spec:
  selector:
    employee-id: "${EMPLOYEE_ID}"
  ports:
    - port: 80
      targetPort: 8080
  type: ClusterIP
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${EMPLOYEE_ID}-workspace
  namespace: ${DEPARTMENT}
  annotations:
    kubernetes.io/ingress.class: "gce"
    kubernetes.io/ingress.global-static-ip-name: "hrm-ingress-ip"
    networking.gke.io/managed-certificates: "${EMPLOYEE_ID}-workspace-cert"
spec:
  rules:
    - host: cs3-hrm-app.duckdns.org
      http:
        paths:
          - path: /workspace/${EMPLOYEE_ID}
            pathType: Prefix
            backend:
              service:
                name: ${EMPLOYEE_ID}-workspace
                port:
                  number: 80
---
apiVersion: networking.gke.io/v1
kind: ManagedCertificate
metadata:
  name: ${EMPLOYEE_ID}-workspace-cert
  namespace: ${DEPARTMENT}
spec:
  domains:
    - cs3-hrm-app.duckdns.org
