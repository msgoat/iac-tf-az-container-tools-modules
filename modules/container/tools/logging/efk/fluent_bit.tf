locals {
  # render helm chart values since direct passing of values does not work in all cases
  fluent_bit_values = <<EOT
# Default values for fluent-bit.

# kind -- DaemonSet or Deployment
kind: DaemonSet

image:
  repository: fluent/fluent-bit
  pullPolicy: IfNotPresent
  # tag:

testFramework:
  image:
    repository: busybox
    pullPolicy: Always
    tag: latest

imagePullSecrets: []
nameOverride: ""
fullnameOverride: ""

serviceAccount:
  create: true
  annotations: {}
  name:

rbac:
  create: true

podSecurityPolicy:
  create: false
  annotations: {}

podSecurityContext:
  {}
# fsGroup: 2000
dnsConfig: {}
  # nameservers:
  #   - 1.2.3.4
  # searches:
  #   - ns1.svc.cluster-domain.example
  #   - my.dns.search.suffix
  # options:
#   - name: ndots
#     value: "2"
#   - name: edns0
securityContext: {}
#  capabilities:
#    drop:
#    - ALL
#  readOnlyRootFilesystem: false
#  runAsNonRoot: true
#  runAsUser: 1000

service:
  type: ClusterIP
  port: 2020
  labels:
    {}
  annotations:
    {}
    # prometheus.io/path: "/api/v1/metrics/prometheus"
    # prometheus.io/port: "2020"
  # prometheus.io/scrape: "true"

serviceMonitor:
  enabled: false
  # namespace: monitoring
  # interval: 10s
  # scrapeTimeout: 10s
  # selector:
  #  prometheus: my-prometheus

prometheusRule:
  enabled: false
  # namespace: ""
  # additionnalLabels: {}
  # rules:
  # - alert: NoOutputBytesProcessed
  #   expr: rate(fluentbit_output_proc_bytes_total[5m]) == 0
  #   annotations:
  #     message: |
  #       Fluent Bit instance {{ $labels.instance }}'s output plugin {{ $labels.name }} has not processed any
  #       bytes for at least 15 minutes.
  #     summary: No Output Bytes Processed
  #   for: 15m
  #   labels:
  #     severity: critical

dashboards:
  enabled: false

livenessProbe:
  httpGet:
    path: /
    port: http

readinessProbe:
  httpGet:
    path: /
    port: http

resources:
  limits:
    memory: 500Mi
  requests:
    cpu: 200m
    memory: 100Mi

%{ if var.node_group_workload_class != "" ~}
# It's OK to be deployed to the tools pool, too
tolerations:
  - key: "group.msg.cloud.kubernetes/workload"
    operator: "Equal"
    value: ${var.node_group_workload_class}
    effect: "NoSchedule"
%{ endif ~}

affinity: {}

podAnnotations: {}

podLabels: {}

networkPolicy:
  enabled: false

## https://docs.fluentbit.io/manual/administration/configuring-fluent-bit/configuration-file
config:
  service: |
    [SERVICE]
        Flush 1
        Daemon Off
        Log_Level info
        Parsers_File parsers.conf
        Parsers_File custom_parsers.conf
        HTTP_Server On
        HTTP_Listen 0.0.0.0
        HTTP_Port {{ .Values.service.port }}
        Health_Check On

  ## https://docs.fluentbit.io/manual/pipeline/inputs
  inputs: |
    [INPUT]
        Name                tail
        Tag                 kube.*
        Exclude_Path        /var/log/containers/cloudwatch-agent*, /var/log/containers/fluent-bit*, /var/log/containers/aws-node*, /var/log/containers/kube-proxy*
        Path                /var/log/containers/*.log
        Docker_Mode         On
        Docker_Mode_Flush   5
        Parser              docker
        Mem_Buf_Limit       50MB
        Refresh_Interval    10
        Rotate_Wait         30
        Read_from_Head      True
        Skip_Long_Lines     On
        DB                  /var/fluent-bit/state/tail-containers-state.db
        DB.Sync             Normal

  ## https://docs.fluentbit.io/manual/pipeline/filters
  filters: |
    [FILTER]
        Name kubernetes
        Match kube.*
        Merge_Log On
        Keep_Log Off
        K8S-Logging.Parser On
        K8S-Logging.Exclude On
        Labels On
        Annotations Off

    # Lift nested kubernetes metadata to root without changing the field names
    # Retag everything coming from internal kubernetes namespaces with k8s
    [FILTER]
        Name         rewrite_tag
        Match        kube.*
        Rule         $kubernetes['namespace_name'] ^(kube) k8s false
    [FILTER]
        Name         rewrite_tag
        Match        kube.*
        Rule         $kubernetes['namespace_name'] ^(azure) k8s false
    [FILTER]
        Name         rewrite_tag
        Match        kube.*
        Rule         $kubernetes['namespace_name'] ^(gatekeeper) k8s false

    # Retag everything coming from system tool stack namespaces with sys
    [FILTER]
        Name         rewrite_tag
        Match        kube.*
        Rule         $kubernetes['namespace_name'] ^(ingress) sys false
    [FILTER]
        Name         rewrite_tag
        Match        kube.*
        Rule         $kubernetes['namespace_name'] ^(monitoring) sys false
    [FILTER]
        Name         rewrite_tag
        Match        kube.*
        Rule         $kubernetes['namespace_name'] ^(logging) sys false
    [FILTER]
        Name         rewrite_tag
        Match        kube.*
        Rule         $kubernetes['namespace_name'] ^(tracing) sys false
    [FILTER]
        Name         rewrite_tag
        Match        kube.*
        Rule         $kubernetes['namespace_name'] ^(postgres) sys false
    [FILTER]
        Name         rewrite_tag
        Match        kube.*
        Rule         $kubernetes['namespace_name'] ^(iam) sys false

    # Retag everything coming from tool chain namespaces with tools
    [FILTER]
        Name         rewrite_tag
        Match        kube.*
        Rule         $kubernetes['namespace_name'] ^(tool) tools false

    # Retag everything coming from application namespaces with apps
    [FILTER]
        Name         rewrite_tag
        Match        kube.*
        Rule         $kubernetes['namespace_name'] ^(cxp) apps false

    # Retag everything coming from application namespaces with apps
    [FILTER]
        Name         rewrite_tag
        Match        kube.*
        Rule         $kubernetes['namespace_name'] ^(cloudtrain) apps false

  ## https://docs.fluentbit.io/manual/pipeline/outputs
  outputs: |
    # send all k8s tags to k8s index
    [OUTPUT]
        Name            es
        Match           k8s
        Host            ${module.elasticsearch.elasticsearch_service_name}
        Port            ${module.elasticsearch.elasticsearch_service_port}
        Logstash_Format On
        Retry_Limit     False
        Type            flb_type
        Time_Key        @flb-timestamp
        Replace_Dots    On
        Logstash_Prefix ${data.azurerm_kubernetes_cluster.cluster.name}-k8s

    # send all sys tags to sys index
    [OUTPUT]
        Name            es
        Match           sys
        Host            ${module.elasticsearch.elasticsearch_service_name}
        Port            ${module.elasticsearch.elasticsearch_service_port}
        Logstash_Format On
        Retry_Limit     False
        Type            flb_type
        Time_Key        @flb-timestamp
        Replace_Dots    On
        Logstash_Prefix ${data.azurerm_kubernetes_cluster.cluster.name}-sys

    # send all tools tags to tools index
    [OUTPUT]
        Name            es
        Match           tools
        Host            ${module.elasticsearch.elasticsearch_service_name}
        Port            ${module.elasticsearch.elasticsearch_service_port}
        Logstash_Format On
        Retry_Limit     False
        Type            flb_type
        Time_Key        @flb-timestamp
        Replace_Dots    On
        Logstash_Prefix ${data.azurerm_kubernetes_cluster.cluster.name}-tools

    # send all apps tags to apps index
    [OUTPUT]
        Name            es
        Match           apps
        Host            ${module.elasticsearch.elasticsearch_service_name}
        Port            ${module.elasticsearch.elasticsearch_service_port}
        Logstash_Format On
        Retry_Limit     False
        Type            flb_type
        Time_Key        @flb-timestamp
        Replace_Dots    On
        Logstash_Prefix ${data.azurerm_kubernetes_cluster.cluster.name}-apps

  ## https://docs.fluentbit.io/manual/pipeline/parsers
  customParsers: |
    [PARSER]
        Name docker_no_time
        Format json
        Time_Keep Off
        Time_Key time
        Time_Format %Y-%m-%dT%H:%M:%S.%L

# The config volume is mounted by default, either to the existingConfigMap value, or the default of "fluent-bit.fullname"
volumeMounts:
  - name: config
    mountPath: /fluent-bit/etc/fluent-bit.conf
    subPath: fluent-bit.conf
  - name: config
    mountPath: /fluent-bit/etc/custom_parsers.conf
    subPath: custom_parsers.conf

daemonSetVolumes:
  - name: fluentbitstate
    hostPath:
      path: /var/fluent-bit/state
  - name: varlog
    hostPath:
      path: /var/log
  - name: varlibdockercontainers
    hostPath:
      path: /var/lib/docker/containers
  - name: etcmachineid
    hostPath:
      path: /etc/machine-id
      type: File

daemonSetVolumeMounts:
  - name: fluentbitstate
    mountPath: /var/fluent-bit/state
  - name: varlog
    mountPath: /var/log
    readOnly: true
  - name: varlibdockercontainers
    mountPath: /var/lib/docker/containers
    readOnly: true
  - name: etcmachineid
    mountPath: /etc/machine-id
    readOnly: true

args: []

command: []
EOT
}
resource helm_release fluent_bit {
  chart = "fluent-bit"
  version = "0.19.6"
  name = "fluent-bit"
  dependency_update = true
  atomic = true
  cleanup_on_fail = true
  create_namespace = true
  namespace = var.kubernetes_namespace_name
  repository = "https://fluent.github.io/helm-charts"
  values = [ local.fluent_bit_values ]
}