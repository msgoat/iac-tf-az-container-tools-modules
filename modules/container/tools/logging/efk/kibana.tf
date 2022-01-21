locals {
  # render helm chart values since direct passing of values does not work in all cases
  kibana_values = <<EOT
elasticsearchHosts: "http://elasticsearch-master:9200"

replicas: 1

# Extra environment variables to append to this nodeGroup
# This will be appended to the current 'env:' key. You can use any of the kubernetes env
# syntax here
extraEnvs:
  - name: "NODE_OPTIONS"
    value: "--max-old-space-size=1800"
#  - name: MY_ENVIRONMENT_VAR
#    value: the_value_goes_here

# Allows you to load environment variables from kubernetes secret or config map
envFrom: []
# - secretRef:
#     name: env-secret
# - configMapRef:
#     name: config-map

# A list of secrets and their paths to mount inside the pod
# This is useful for mounting certificates for security and for mounting
# the X-Pack license
secretMounts: []
#  - name: kibana-keystore
#    secretName: kibana-keystore
#    path: /usr/share/kibana/data/kibana.keystore
#    subPath: kibana.keystore # optional

hostAliases: []
#- ip: "127.0.0.1"
#  hostnames:
#  - "foo.local"
#  - "bar.local"

image: "docker.elastic.co/kibana/kibana"
imageTag: "7.15.0"
imagePullPolicy: "IfNotPresent"

# additionals labels
labels: {}

podAnnotations:
  {}
# iam.amazonaws.com/role: es-cluster

resources:
  requests:
    cpu: "1000m"
    memory: "2Gi"
  limits:
    cpu: "1000m"
    memory: "2Gi"

protocol: http

serverHost: "0.0.0.0"

healthCheckPath: /app/kibana

# Allows you to add any config files in /usr/share/kibana/config/
# such as kibana.yml
kibanaConfig:
  kibana.yml: |
    server.basePath: /kibana
    server.publicBaseUrl: https://${var.ingress_host_name}/kibana

# If Pod Security Policy in use it may be required to specify security context as well as service account

podSecurityContext:
  fsGroup: 1000

securityContext:
  capabilities:
    drop:
      - ALL
  # readOnlyRootFilesystem: true
  runAsNonRoot: true
  runAsUser: 1000

serviceAccount: ""

# This is the PriorityClass settings as defined in
# https://kubernetes.io/docs/concepts/configuration/pod-priority-preemption/#priorityclass
priorityClassName: ""

httpPort: 5601

extraVolumes:
  []
  # - name: extras
#   emptyDir: {}

extraVolumeMounts:
  []
  # - name: extras
  #   mountPath: /usr/share/extras
  #   readOnly: true
#
extraContainers: ""
# - name: dummy-init
#   image: busybox
#   command: ['echo', 'hey']

extraInitContainers: ""
# - name: dummy-init
#   image: busybox
#   command: ['echo', 'hey']

updateStrategy:
  type: "Recreate"

service:
  type: ClusterIP
  loadBalancerIP: ""
  port: 5601
  nodePort: ""
  labels: {}
  annotations:
    {}
    # cloud.google.com/load-balancer-type: "Internal"
    # service.beta.kubernetes.io/aws-load-balancer-internal: 0.0.0.0/0
    # service.beta.kubernetes.io/azure-load-balancer-internal: "true"
    # service.beta.kubernetes.io/openstack-internal-load-balancer: "true"
  # service.beta.kubernetes.io/cce-load-balancer-internal-vpc: "true"
  loadBalancerSourceRanges:
    []
  # 0.0.0.0/0
  httpPortName: http

ingress:
  enabled: true
  annotations:
    kubernetes.io/ingress.class: nginx
    nginx.ingress.kubernetes.io/rewrite-target: /$2
  hosts:
    - host: "kibana.cluster.local"
      paths:
        - path: /kibana(/|$)(.*)

readinessProbe:
  failureThreshold: 3
  initialDelaySeconds: 10
  periodSeconds: 10
  successThreshold: 3
  timeoutSeconds: 5

imagePullSecrets: []
nodeSelector: {}

%{ if var.node_group_workload_class != "" ~}
# It's OK to be deployed to the tools pool, too
tolerations:
  - key: "group.msg.cloud.kubernetes/workload"
    operator: "Equal"
    value: ${var.node_group_workload_class}
    effect: "NoSchedule"
%{ endif ~}

%{ if var.node_group_workload_class != "" ~}
affinity:
  # Encourages deployment to the tools pool
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: "group.msg.cloud.kubernetes/workload"
              operator: In
              values:
                - ${var.node_group_workload_class}
%{ endif ~}

nameOverride: ""
fullnameOverride: ""

lifecycle:
  {}
  # preStop:
  #   exec:
  #     command: ["/bin/sh", "-c", "echo Hello from the postStart handler > /usr/share/message"]
  # postStart:
  #   exec:
#     command: ["/bin/sh", "-c", "echo Hello from the postStart handler > /usr/share/message"]

# Deprecated - use only with versions < 6.6
elasticsearchURL: "" # "http://elasticsearch-master:9200"
EOT
}
resource helm_release kibana {
  chart = "kibana"
  version = "7.15.0"
  repository = "https://helm.elastic.co"
  name = "kibana"
  dependency_update = true
  atomic = false
  cleanup_on_fail = false
  namespace = var.kubernetes_namespace_name
  values = [ local.kibana_values ]
  set {
    name = "elasticsearchHosts"
    value = "http://${module.elasticsearch.elasticsearch_service_name}:${module.elasticsearch.elasticsearch_service_port}"
  }
  set {
    name = "ingress.hosts[0].host"
    value = "${var.ingress_host_name}"
  }
}