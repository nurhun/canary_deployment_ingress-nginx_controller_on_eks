##################### 7-app #####################

resource "kubectl_manifest" "app_namespace" {
  yaml_body = <<YAML
apiVersion: v1
kind: Namespace
metadata:
  name: app
  labels:
    # This will allow Prometheus to scrape PodMonitor, ServiceMonitor, probeSelector, PrometheusRules, 
    prometheus: "true"
YAML

  depends_on = [
    helm_release.kube_prometheus_stack,
  ]
}


resource "kubectl_manifest" "nginx_config" {
  yaml_body = <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
  namespace: app
data:
  default.conf: |
    server {
        listen 80;
        server_name _;
        server_tokens off;

        client_max_body_size 20M;

        location / {
            root   /usr/share/nginx/html;
            index  index.html index.htm;
            try_files $uri $uri/ /index.html;
        }

        location /api {
            try_files $uri @proxy_api;
        }
        location /admin {
            try_files $uri @proxy_api;
        }

        location @proxy_api {
            proxy_set_header X-Forwarded-Proto https;
            proxy_set_header X-Url-Scheme $scheme;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header Host $http_host;
            proxy_redirect off;
            proxy_pass   http://backend;
        }

        location /django_static/ {
            # autoindex on;
            alias /usr/src/static/;
        }

        location /nginx_status {                                        
            stub_status;                                                
        }   
    }
YAML

  depends_on = [
    kubectl_manifest.app_namespace,
  ]
}


resource "kubectl_manifest" "backend_secret" {
  yaml_body = <<YAML
apiVersion: v1
kind: Secret
metadata:
  name: secretkey
  namespace: app
type: Opaque
data:
  SECRET_KEY: Y2xhc3NpZmllZA==
YAML

  depends_on = [
    kubectl_manifest.app_namespace,
  ]
}


resource "kubectl_manifest" "backend_deployment" {
  yaml_body = <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  namespace: app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
    spec:
      containers:
      - name: backend
        image: nurhun/django_rest_framework_movies_apis_w_react_frontend_backend:v0.1.0
        args:
        - -c
        - gunicorn moviesapi.wsgi --bind=0.0.0.0:8000 --reload --workers=2 --threads=2 --timeout=120 --log-level=Debug
        ports:
        - containerPort: 8000
        env:
          - name: SECRET_KEY
            valueFrom:
              secretKeyRef:
                name: secretkey
                key: SECRET_KEY
YAML

  depends_on = [
    kubectl_manifest.backend_secret,
  ]
}


resource "kubectl_manifest" "backend_service" {
  yaml_body = <<YAML
apiVersion: v1
kind: Service
metadata:
  name: backend
  namespace: app
spec:
  selector:
    app: backend
  ports:
  - port: 80
    targetPort: 8000
YAML

  depends_on = [
    kubectl_manifest.backend_deployment,
  ]
}


resource "kubectl_manifest" "main_frontend_deployment" {
  yaml_body = <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend-v1
  namespace: app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: frontend
      version: v1
  template:
    metadata:
      labels:
        app: frontend
        version: v1
      annotations:
        prometheus.io/scrape: 'true'
        prometheus.io/port: '9113'
    spec:
      containers:
        - name: frontend-v1
          image: nurhun/django_rest_framework_movies_apis_w_react_frontend_nginx:v0.1.0
          command:
            - "/bin/sh"
            - "-c"
            - | 
                sed -i 's|include /etc/nginx/conf\.d/\*\.conf;|include /tmp/nginx/conf.d/\*\.conf;|' /etc/nginx/nginx.conf
                sed -i 's/#gzip  on;/gzip  on;/' /etc/nginx/nginx.conf
                sed -i '/gzip  on;/a\    gzip_types text/plain text/xml text/css application/json application/javascript application/xml application/xml+rss text/javascript image/svg+xml;' /etc/nginx/nginx.conf
                nginx -g 'daemon off;'
          ports:
            - containerPort: 80
          env:
            - name: NGINX_ENVSUBST_OUTPUT_DIR
              value: "/tmp/nginx/conf.d/"
          volumeMounts:
            - name: nginx-config
              mountPath: /tmp/nginx/conf.d/default.conf
              subPath: default.conf
        - name: nginx-exporter
          image: 'nginx/nginx-prometheus-exporter:0.10.0'
          args:
            - '-nginx.scrape-uri=http://localhost/nginx_status'
          resources:
            limits:
              memory: 128Mi
              cpu: 500m
          ports:
            - name: http-metrics
              containerPort: 9113
      volumes:
        - name: nginx-config
          configMap:
            defaultMode: 420
            name: nginx-config
YAML

  depends_on = [
    kubectl_manifest.nginx_config,
    kubectl_manifest.backend_deployment,
  ]
}


resource "kubectl_manifest" "main_frontend_service" {
  yaml_body = <<YAML
apiVersion: v1
kind: Service
metadata:
  name: frontend-v1-main
  namespace: app
spec:
  selector:
    app: frontend
    version: v1
  ports:
  - port: 80
    targetPort: 80
    name: http
  - port: 9113
    targetPort: http-metrics
    name: http-metrics
YAML

  depends_on = [
    kubectl_manifest.main_frontend_deployment,
  ]
}


resource "kubectl_manifest" "main_frontend_ingress" {
  yaml_body = <<YAML
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: frontend-v1-main
  namespace: app
spec:
  ingressClassName: nginx
  rules:
    - host: "${module.ingress_loadbalancer_ip.stdout}.nip.io"
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: frontend-v1-main
                port:
                  number: 80
YAML

  depends_on = [
    kubectl_manifest.main_frontend_service,
  ]
}


resource "kubectl_manifest" "canary_frontend_deployment" {
  yaml_body = <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend-v2
  namespace: app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: frontend
      version: v2
  template:
    metadata:
      labels:
        app: frontend
        version: v2
      annotations:
        prometheus.io/scrape: 'true'
        prometheus.io/port: '9113'
    spec:
      containers:
        - name: frontend-v2
          image: nurhun/django_rest_framework_movies_apis_w_react_frontend_nginx:v0.2.0
          command:
            - "/bin/sh"
            - "-c"
            - | 
                sed -i 's|include /etc/nginx/conf\.d/\*\.conf;|include /tmp/nginx/conf.d/\*\.conf;|' /etc/nginx/nginx.conf
                sed -i 's/#gzip  on;/gzip  on;/' /etc/nginx/nginx.conf
                sed -i '/gzip  on;/a\    gzip_types text/plain text/xml text/css application/json application/javascript application/xml application/xml+rss text/javascript image/svg+xml;' /etc/nginx/nginx.conf
                nginx -g 'daemon off;'
          ports:
            - containerPort: 80
          env:
            - name: NGINX_ENVSUBST_OUTPUT_DIR
              value: "/tmp/nginx/conf.d/"
          volumeMounts:
            - name: nginx-config
              mountPath: /tmp/nginx/conf.d/default.conf
              subPath: default.conf
        - name: nginx-exporter
          image: 'nginx/nginx-prometheus-exporter:0.10.0'
          args:
            - '-nginx.scrape-uri=http://localhost/nginx_status'
          resources:
            limits:
              memory: 128Mi
              cpu: 500m
          ports:
            - name: http-metrics
              containerPort: 9113
      volumes:
        - name: nginx-config
          configMap:
            defaultMode: 420
            name: nginx-config
YAML

  depends_on = [
    kubectl_manifest.nginx_config,
    kubectl_manifest.backend_deployment,
  ]
}


resource "kubectl_manifest" "canary_frontend_service" {
  yaml_body = <<YAML
apiVersion: v1
kind: Service
metadata:
  name: frontend-v2-canary
  namespace: app
spec:
  selector:
    app: frontend
    version: v2
  ports:
  - port: 80
    targetPort: 80
    name: http
  - port: 9113
    targetPort: http-metrics
    name: http-metrics
YAML

  depends_on = [
    kubectl_manifest.canary_frontend_deployment,
  ]
}


resource "kubectl_manifest" "canary_frontend_ingress" {
  yaml_body = <<YAML
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: frontend-v2-canary
  namespace: app
  annotations:
    # Canary Deployment via Ingress Nginx Controller 
    nginx.ingress.kubernetes.io/canary: "true"
    nginx.ingress.kubernetes.io/canary-by-header: X-Canary
    nginx.ingress.kubernetes.io/canary-weight: "50"
spec:
  ingressClassName: nginx
  rules:
    - host: "${module.ingress_loadbalancer_ip.stdout}.nip.io"
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: frontend-v2-canary
                port:
                  number: 80
YAML

  depends_on = [
    kubectl_manifest.canary_frontend_service,
  ]
}


resource "kubectl_manifest" "main_frontend_PodMonitor" {
  yaml_body = <<YAML
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: main
  namespace: app
spec:
  # pod label selectors.
  selector:
    matchLabels:
      version: v1
  # Selector to select which namespaces the Endpoints objects are discovered from.
  namespaceSelector:
    matchNames:
    - app
  podMetricsEndpoints:
  - path: /metrics
    port: http-metrics
YAML

  depends_on = [
    kubectl_manifest.main_frontend_deployment,
  ]
}


resource "kubectl_manifest" "canary_frontend_PodMonitor" {
  yaml_body = <<YAML
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: canary
  namespace: app
spec:
  # pod label selectors.
  selector:
    matchLabels:
      version: v2
  # Selector to select which namespaces the Endpoints objects are discovered from.
  namespaceSelector:
    matchNames:
    - app
  podMetricsEndpoints:
  - path: /metrics
    port: http-metrics
YAML

  depends_on = [
    kubectl_manifest.canary_frontend_deployment,
  ]
}