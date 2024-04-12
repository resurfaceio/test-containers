# resurfaceio-helm-resurface

Resurface makes it easy to capture and analyze API calls with your own <a href="https://resurface.io">security data lake</a>.

## Components

- **StatefulSets**: Resurface database coordinator pod and worker replicas with persistent storage. Your very own Resurface instance.
- **Service**: Coordinator. Exposes the API Explorer frontend for your Resurface instance.
- **Service**: Worker. Exposes the fluke microservice used to import API calls into your Resurface instance.
- **Ingress**: Requires HAProxy ingress controller. Enabled by default.
- **TLS Secret**: (Optional) TLS certificate and key. Used for Ingress TLS termination. A TLS cert and key combination can be autoissued by the cert-manager utility, or it can be provided by the user. Disabled by default.
- **Issuer**: (Optional) Issues TLS certificate from Let's Encrypt. Requires Cert-manager utility. Disabled by default.
- **DaemonSet**: (Optional) Packet-sniffer-based logger. Captures API calls made to your application pods over the wire, parses them and sends them to your Resurface pod. A service account, cluster role, and cluster role binding are also deployed with this daemon set. Disabled by default.
- **Deployments**: (Optional) Data stream consumer applications. Captures API calls made to the Azure API Management and AWS API Gateway services. The API calls are published as events to an Azure Event Hubs/AWS Kinesis Data Streams instance, the applications consume these events, parses them and sends them to your Resurface pod. Opaque secrets containing sensitive data (such as AWS credentials) may be created alongside these deployments. Disabled by default.
- **CronJob**: (Optional) AWS VPC Traffic Mirror session maker. Creates traffic mirror sessions given different traffic sources (ECS tasks, EC2 instances, and/or Auto-Scaling Groups). When enabled, it updates the list of VNIs used by the sniffer to detect and capture incoming mirrored traffic for all active mirror sessions. It also restarts the DaemonSet accordingly.

Other components:

- **ServiceAccounts**: All DB workloads use the `resurface-sa` service account by default. All Sniffer-related workloads use the `resurface-sniffer-sa` service account.
- **ClusterRole**: Adds reading capabilities for the Sniffer pods to list pods and services internally. Adds writing capabilities to edit the VNIs ConfigMap when VPC mirroring is enabled.
- **ClusterRoleBinding**: Binds the ClusterRole to the `resurface-sniffer-sa` ServiceAccount.
- **Secrets**: Used to manage low-level Trino configuration values.
- **ConfigMaps**: Used to manage low-level Trino settings.

## Dependencies

- [HAProxy Ingress Controller](https://www.haproxy.com/documentation/kubernetes/latest/installation/community/)
- [Cert-manager utility](https://cert-manager.io/docs/installation/helm/) (when TLS auto-issuing enabled)
- [MinIO Object Storage](https://min.io/docs/minio/kubernetes/upstream/) (when Iceberg storage is enabled)

## Values

The **ingress** values section is where the configuration for the Ingress resource can be found. The following fields can be found nested in this section:

- **ingress.enabled**: boolean. The Ingress resource can be disabled by setting this value to `false`. In that case, the services can still be exposed, albeit without SSL/TLS termination. See **custom.service** section. Defaults to `true`.

- The **ingress.importer** nested section corresponds to the endpoint used by each Resurface worker node to import API calls into your Resurface database.
  - **ingress.importer.expose**: boolean. The importer endpoint can be disabled by setting this value to `false`. In that case, the endpoint will only be reachable through the worker importer service and not the ingress resource. Defaults to `true`.
  - **ingress.importer.path**: string. The ingress resource will route all calls made to this path to the worker importer service. Defaults to `"/fluke"`. Required only if **ingress.importer.expose** is set to `true`.

- The **ingress.minio** nested section refers to routing access to the MinIO web console through the available Ingress Controller (see the Iceberg integration section below)
  - **ingress.minio.expose**: boolean. If both the MinIO subchart has been deployed and the Iceberg integration is enabled, the MinIO web console can be accessed through port `9001` by setting this value to `true`. Defaults to `false`.

- The **ingress.tls** nested section corresponds to the TLS termination configuration for the Ingress resource.
  - **ingress.tls.enabled**: boolean. The TLS termination feature can be enabled by setting this value to `true`. Defaults to `false`.
  - **ingress.tls.host**: string. Host included in the TLS certificate. DNS records must be updated accordingly. Required only if **ingress.tls.enabled** is set to `true`.
  - **ingress.tls.autoissue**: this nested subsection corresponds to the configuration needed to auto-issue a TLS certificate using the cert-manager utility. The auto-issuing process is mutually exclusive with respect to the BYOC (bring-your-own-certificate) process.
    - **ingress.tls.autoissue.enabled**: boolean. The TLS certificate automatic issuing and renewal process can be disabled by setting this value to `false`. Defaults to `true`.
    - **ingress.tls.autoissue.staging**: boolean. The TLS certificate automatic issuing and renewal process uses the "Let's Encrypt" ACME as CA. Let's Encrypt provides both a [staging environment](https://letsencrypt.org/docs/staging-environment/) and a [rate-limited production environment](https://letsencrypt.org/docs/rate-limits/) for the certificate issuing process. By setting this value to `true` cert-manager uses the former, and by setting it to `false` it then uses the latter. Defaults to `true`.
    - **ingress.tls.autoissue.email**: string. Let's Encrypt will send notices only if a certificate is about to expire and the renewal process has failed. Required only if **ingress.tls.autoissue.enabled** is set to `true`.
  - **ingress.tls.byoc**: this nested subsection corresponds to the bring-your-own-certificate configuration. This process is mutually exclusive with respect to the auto-issuing process. A user must supply the name of a Kubernetes TLS Secret that already exists in the same namespace.
    - **ingress.tls.byoc.secretname**: string. Name of an already existing Kubernetes TLS Secret to be used by the Ingress resource. Required only if **ingress.tls.enabled** is set to `true` and **ingress.tls.autoissue.enabled** is set to `false`.

```yaml
ingress:
  enabled: true
  tls:
    enabled: true
    host: thisisanexample.com
    autoissue:
      staging: false
      email: admin@thisisanexample.com
```

Authentication can be configured in the **auth** section.

- **auth.enabled**: boolean. If set to `true`, an authentication header will be required for any DB transaction. Auth will work only when TLS is enabled. At least one authentication method must be enabled when auth is enabled. Defaults to `false`.

- The **auth.basic** subsection corresponds to basic authentication. When basic auth is enabled, a secret containing an encrypted list of allowed credentials will be mounted in the file system, and a valid username and password combination will be required at the login page of the API Explorer.
  - **auth.basic.enabled**: If set to `true`, basic authentication will be enabled. Defaults to `false`.
  - **auth.basic.credentials**: Sequence of credentials allowed. Both a **username** and **password** are required for each item. At least one credential must be passed when **auth.basic.enabled** is set to `true`.

- The **auth.jwt** subsection refers to authentication using JSON Web Tokens. When JWT auth is enabled, only requests with a valid bearer token header will be served.
  - **auth.jwt.enabled**: If set to `true`, JWT authentication will be enabled. Defaults to `false`.
  - **auth.jwt.jwksurl**: String. The URL pointing to a JWKS service, a PEM or HMAC file that can be used to validate the JWT signature of each token.

- The **auth.oauth2**: subsection corresponds to authentication provided by an external OAuth 2.0 identity provider. When OAuth2 auth is enabled, users will be redirected to the external provider Log In page, and redirected back to the API Explorer once authenticated. All the corresponding endpoints for an external OAuth 2.0 Authorization Code service must be configured, as well as a Client ID and Client Secret provided by this third party.
  - **auth.oauth2.enabled**: If set to `true`, OAuth 2.0 will be enabled. Defaults to `false`.
  - **auth.oauth2.issuer**: String. The issuer URL for the external OAuth 2.0 service. All tokens issued by the service must have this in the `iss` field. Required only if **auth.aouth2.enabled** is set to `true`.
  - **auth.oauth2.authurl**: String. The service authorization URL. The browser will be redirected to this URL when accessing the API Explorer for the first time. Required only if **auth.aouth2.enabled** is set to `true`.
  - **auth.oauth2.tokenurl**: String. The URL of the endpoint on the authorization server to exchange the authorization code for an access token. Required only if **auth.aouth2.enabled** is set to `true`.
  - **auth.oauth2.jwksurl**: String. The URL of the JSON Web Key Set (JWKS) endpoint on the authorization server. It must point to the set of keys containing the public key to verify any JSON Web Token (JWT) from the authorization server. Required only if **auth.aouth2.enabled** is set to `true`.
  - **auth.oauth2.userinfourl**: String.  If supplied then this URL is used to validate the OAuth access token and retrieve any associated claims. Required only if the authorization server issues opaque tokens.
  - **auth.oauth2.clientid**: String. Client identifier provided by the external OAuth 2.0 service.
  - **auth.oauth2.clientsecret**: String. Client secret provided by the external OAuth2.0 service.

```yaml
auth:
  enabled: true
  basic:
    enabled: true
    credentials:
      - username: admin
        password: irtRUqUp7fkfL
      - username: msmith
        password: qPBceDWjPJFYKfX7QAXfmy1b33tBE
  jwt:
    enabled: true
    jwksurl: https://cluster.example.net/.well-known/jwks.json
  oauth2:
    enabled: true
    issuer: https://accounts.google.com
    authurl: https://accounts.google.com/o/oauth2/v2/auth
    tokenurl: https://oauth2.googleapis.com/token
    jwksurl: https://www.googleapis.com/oauth2/v3/certs
    userinfourl: https://openidconnect.googleapis.com/v1/userinfo
    clientid: sampleid123.apps.googleusercontent.com
    clientsecret: samplesecret456
```

The **provider** value is a string equal to either `azure`, `aws`, or `gcp`. It is used as an alias to request persistent volumes specific to each provider. See the **custom.storage** section.

```yaml
provider: azure
```

The **units** values is a string equal to either `binary` or `metric`. It is used to set the convention used for data units when configuring a release of this chart. When set to `binary`, powers to two (kiB, MiB, GiB, TiB) are used. When set to `metric`, powers of ten (kB, MB, GB, TB) are used. Defaults to `binary`.

The **multinode** section is where the configuration to set multiple database nodes can be found.

- **multinode.enabled**: boolean. If set to `true` worker nodes are enabled. Otherwise, the single-node configuration is used. Defaults to `false`
- **multinode.workers**: integer. Number of stateful worker nodes to deploy. Resources mus t be available in the cluster in order to succesfully scale accordingly. The total number of nodes in the database will be **multinode.workers** + 1, since the coordinator node itself always acts as a worker node.

```yaml
multinode:
  enabled: true
  workers: 3
```

Iceberg integration can be configured in the **iceberg** section. In this mode, data will automatically be pushed to a given object storage server using the Apache Iceberg table format. This can increase storage capacity at least 10x with next to no performance impact. The configured object storage can be an external service such as AWS S3, or it can be hosted in the same Kubernetes cluster using MinIO. A valid license must be provided in order to enable an Iceberg integration succesfully. At the moment, downgrades from an iceberg deployment to a non-iceberg deployment are not supported.

- **iceberg.enabled**: boolean. If set to `true`, data will automatically be replicated to the configured object storage, including all data already captured. Defaults to `false`.

- The **iceberg.s3** subsection corresponds to the configuration for the AWS S3 object storage service.
  - **iceberg.s3.enabled**: If set to `true`, AWS S3 object storage will be used to store Iceberg data and metadata files. It is important to note that MinIO and AWS S3 iceberg deployments are mutually exclusive. Defaults to `false`.
  - **iceberg.s3.bucketname**: string. Unique name for the S3 bucket where data will be written to.
  - **iceberg.s3.aws**: nested subsection where the configuration for the AWS account that owns the S3 bucket can be found.
  - **iceberg.s3.aws.region**: string. AWS region where S3 bucket was created in. Required only if **iceberg.s3.enabled** is set to `true`.
  - **iceberg.s3.aws.accesskey**: string. AWS Credentials. It is **not** recommended to pass the AWS credentials as helm values, and instead create a kubernetes secret object manually named **resurface-s3-creds** with the corresponding key-value pairs. Required only if **iceberg.s3.enabled** is set to `true` and the **resurface-s3-creds** secret does not exist.
  - **iceberg.s3.aws.secretkey**: string. AWS Credentials. It is **not** recommended to pass AWS credentials as helm values, and instead create a kubernetes secret object manually named **resurface-s3-creds** with the corresponding key-value pairs. Required only if **iceberg.s3.enabled** is set to `true` and the **resurface-s3-creds** secret does not exist.

- The **iceberg.config** subsection contains configuration specific to Iceberg.
  - **iceberg.config.format**: string. File format used for Iceberg data file storage. It can be either `'PARQUET'` or `'ORC'` format. Defaults to `'PARQUET'`.
  - **iceberg.config.codec**: string. Codec used for compression of Iceberg data files. It can be either `'ZSTD'`, `'LZ4'`, `'SNAPPY'`, or `'GZIP'`. Defaults to `'ZSTD'`.
  - **iceberg.config.millis**: integer. Sleep between Iceberg polling cycles, in milliseconds. Defaults to `20000`.
  - **iceberg.size.max**: integer. Maximum configurable size in GiB/GB (see **units**) for Iceberg storage (data & index). Should be equal to **minio.persistence.size** when **minio.enabled** is set to `true`. Defaults to `100`.
  - **iceberg.size.reserved**: integer. Reserved space size in GiB/GB (see **units**) for Iceberg storage (metadata & logs). Must be less than **iceberg.size.max**. Defaults to `20`.

The **minio** section corresponds to values passed to the `minio-official/minio` subchart. For more detailed information on all the values that can be set for this chart, please visit: https://artifacthub.io/packages/helm/minio-official/minio
  - **minio.enabled**: If set to `true`, MinIO subchart will be deployed. It is important to note that MinIO and AWS S3 iceberg deployments are mutually exclusive. Defaults to `false`.
  - **minio.rootUser**: string. Required if **minio.enabled** is set to `true`.
  - **minio.rootPassword**: string. Required if **minio.enabled** is set to `true`.
  - **minio.mode**: string. MinIO [deployment topology](https://min.io/docs/minio/linux/operations/installation.html#install-and-deploy-minio). It can be either `standalone` or `distributed`. Defaults to `standalone`.
  - **minio.replicas**: integer. Number of MinIO instances. Defaults to `4`.
  - **minio.persistence.size**: string. Persistent volume size for each MinIO instance. Defaults to `100Gi`.
  - **minio.resources.requests.memory**: string. Volatile memory request for each MinIO instance. Defaults to `16Gi`.
  - **minio.buckets**: Sequence of buckets to create after server has been initialized. For each bucket, a **name** must be specified. Defaults to a single item with `name` equal to `iceberg.resurface`.
  - **minio.service**: Kubernetes service that exposes MinIO API.
    - **minio.service.type**: string. Defaults to `ClusterIP`.
    - **minio.service.port**: integer. Defaults to `9000`.
  - **minio.consoleService**: Kubernetes service that exposes MinIO web console.
    - **minio.consoleService.type**: string. Defaults to `ClusterIP`.
    - **minio.consoleService.port**: integer. Defaults to `9001`.

External integrations can be configured in the **integrations** section.

- The **integrations.axway** subsection corresponds to the Axway integration.
  - **integrations.axway.enabled**: If set to `true`, Axway polling will be enabled. Defaults to `false`.
  - **integrations.axway.clientID**: string. Name of Axway service account. Required only if **integrations.axway.secretName** is not set.
  - **integrations.axway.clientSecret**: string. Password for Axway service account. Required only if **integrations.axway.secretName** is not set.
  - **integrations.axway.orgID**: string. Axway tenant identifier. Required only if **integrations.axway.secretName** is not set.
  - **integrations.axway.secretName**: string. Name of an already existing Kubernetes Secret containing the three required fields (clientID, clientSecret, and OrgID). Required only if at least one of the **integrations.axway.clientID**, **integrations.axway.clientID**, or **integrations.axway.clientID** values is missing.

The **custom** section holds the values for fields that can be overridden in any default configuration. None of its fields are required. The following fields can be found nested in this section:

- The **custom.service** subsection is where the configuration for both the internal service resources can be found.
  - **custom.service.apiexplorer**: nested subsection that refers to the Resurface frontend service.
    - **custom.service.apiexplorer.port**: integer. Port exposed by the coordinator service. Defaults to `7700`
    - **custom.service.apiexplorer.type**: string. Service type for the coordinator service. Defaults to `LoadBalancer` when `ingress.enabled` is set to `false`. It defaults to a headless service otherwise.
  - **custom.service.flukeserver**: nested subsection for the Resurface importer service.
    - **custom.service.flukeserver.port**: integer. Port exposed by the worker service. Defaults to `7701`
    - **custom.service.flukeserver.type**: string. Service type for the worker service. Defaults to `ClusterIP`

- The **custom.resources** subsection is where the container configuration requirements can be found.
  - **custom.resources.cpu**: integer. Minimum required vCPU to run a Resurface container. It isn't recommended to set this value lower than `3`.
  - **custom.resources.memory**: integer. Minimum required memory in GiB/GB (see **units**) to run a Resurface container. It should be greater than the sum of both **custom.config.dbsize** and **custom.config.dbheap** values.

- The **custom.config** subsection contains configuration specific to Resurface.
  - **custom.config.dbsize**: integer. Available memory in GiB/GB (see **units**) to be used by the Resurface database.
  - **custom.config.dbheap**: integer. Available memory in GiB/GB (see **units**) to be used by the JVM running the application. It isn't recommended to set this value below `3`.
  - **custom.config.dbslabs**: integer. Used by the Resurface database to define a level of parallelism for queries.
  - **custom.config.shardsize**: integer|string. As an integer, this value represents the size in GiB/GB (see **units**) of each batch of API calls written to disk. It can also receive a string comprised of a value and the corresponding data unit prefix for different orders of magnitude (e.g. `'500m'`, `'2000k'`, `'3g'`). Defaults to `'500m'`
  - **custom.config.pollingcycle**: string. Sleep cycle for alert polling thread. Allowed values are `'default'` (use configured cycle delay), `'off'` (no polling), `'fast'` (60-second delay), `'nonstop'` (zero cycle delay). Defaults to `'default'`
  - **custom.config.tz**: string. Used to specify a local timezone instead of the UTC timezone containers run with by default.
  - **custom.config.version**: string. Overrides the default Resurface image tag for a given chart version.

- The **custom.storage** subsection refers to the persistent storage configuration. Persistent volume implementation is specific to each cloud provider.
  - **custom.storage.size**: integer. Size in GiB/GB (see **units**) of the persistent volume that should be provisioned for each Resurface node. It should match the **custom.config.dbsize** value.
  - **custom.storage.classname**: string. Name of the storage class to be used when requesting a new persistent volume claim. Each cloud provider can offer more than one `StorageClassName`. By setting `provider`, the storage class name is set to the one offered as default for each provider. This value overrides that default class name. The chosen **custom.storage.classname** should be offered by the cloud provider, otherwise persistence is not guaranteed.

```yaml
custom:
  service:
    apiexplorer:
      port: 80
    flukeserver:
      port: 7701
      type: NodePort
  resources:
    memory: 12
  storage:
    classname: managed-csi-premium
```

The **sniffer** section is where the configuration values for the optional network packet sniffer can be found.

- **sniffer.enabled**: boolean. The sniffer can be deployed by setting this value to `true`. Defaults to `false`.

- **sniffer.services**: Sequence of services to log from. For each service, both a **namespace** and service **name** can be specified. If only namespace is specified for a given service, it will be ignored unless namespace-only discovery is enabled. In addition, an array of integer **ports** can be passed for each service. These ports refer to the target ports for each container, not service ports. See example below.

- **sniffer.pods**: Sequence of specific pods to log from. For each pod, both **namespace** and pod **name** are required. In addition, an array of integer container **ports** can also be passed for each pod. See example below.

- **sniffer.labels**: Sequence of specific label selectors used to select a set of pods. A **keyvalues** sequence of strings corresponding to all key-value pairs that make up the selector label in the form `"key=value"` must be provided for each item. The **namespace** is optional. See example below.

- The **sniffer.discovery** subsection contains the configuration for service discovery. When **sniffer.services** is empty and **sniffer.discovery.enabled** is set to `true`, global service discovery is enabled. When **sniffer.discovery.enabled** is set to `true` and **sniffer.services** contains at least one service specifying only its namespace, namespace-only discovery is enabled for that namespace. Note: It is suggested to explicitly skip services that expose pods acting as Ingress Controllers, as traffic will still be logged from upstream pods.
  - **sniffer.discovery.enabled**: boolean. Defaults to `false`.
  - **sniffer.discovery.skip**: nested subsection that refers to specific namespaces or services to skip when discovery is performed.
    - **sniffer.discovery.skip.ns**: []string. Array containing the names of the namespaces to be skipped.
    - **sniffer.discovery.skip.svc**: []string. Array containing the names of the services to be skipped.

- The **sniffer.logger** nested section contains the configuration specific to the Resurface logger used by the sniffer to send API calls to the corresponding importer endpoint.
  - **sniffer.logger.enabled**: boolean. The internal logger can be temporarily disabled by setting this value to `false`.
  - **sniffer.logger.rules**: string. The internal logger operates under a certain [set of rules](http://resurface.io/logging-rules) that determines which data is logged. These rules can be passed to the logger as a single-line or a multiline string.

- **sniffer.ignore**: []string. Array containing the names of specific network interfaces to ignore for all nodes. Defaults to `[ "lo", "cbr0" ]`

- The **sniffer.vpcmirror** subsection refers to capturing traffic from AWS VPC mirroring sessions. A traffic mirroring session can be set up from one ENI (attached to a given EC2 instance), to another ENI attached to any of the EC2 instances that work as Kubernetes nodes for a given EKS cluster. Traffic passing through the first ENI will be mirrored onto the second one, where the network packet sniffer can capture the data from and send it to your Resurface instance.
  - **sniffer.vcpmirror.enabled**: boolean. The sniffer will be configured to capture mirrored traffic by setting this option to `true`. Defaults to `false`.
  - **sniffer.vcpmirror.vnis**: []integer. Array containing the Virtual Network Identifiers from each VPC mirroring session.
  - **sniffer.vcpmirror.ports**: []integer. Array containing the port numbers exposed by the applications running in the EC2 instances that act as traffic mirror sources. At least one port number is required.
  - The **sniffer.vpcmirror.autosetup** nested subsection contains the configuration for an automatic job to make AWS VPC Traffic Mirror sessions. Given one or more traffic sources (ECS tasks, EC2 instances, and/or Auto-Scaling Groups), it creates traffic mirror sessions for each (if supported), updates the list of VNIs used by the sniffer for all active mirror sessions, and it restarts the DaemonSet accordingly.  The AWS VPC traffic mirror session creator/updater job will work only when  **provider** is set to `"aws"` and **sniffer.vpcmirror.enabled** is set to `true`.
    - **sniffer.vpcmirror.autosetup.enabled**: boolean. The traffic mirror session creator script will run periodically as a job when set to `true`. Defaults to `false`.
    - **sniffer.vpcmirror.autosetup.schedule**: string. Cron schedule expression to define the frequency at which to run the traffic mirror session creator job. Defaults to `"0 * * * *"`, which can be read as "every hour at minute 0".
    - The traffic **sniffer.vpcmirror.autosetup.source** can be any one or more of the following:
      - **sniffer.vpcmirror.autosetup.source.ecs.clusters**: Comma-separated sequence of names of ECS clusters with EC2 and/or FARGATE-based containerized workloads to capture traffic from. Must be in the same region as mirror target EKS cluster.
      - **sniffer.vpcmirror.autosetup.source.ecs.launchtype**: string. Filters ECS tasks by launch type. It can be "EC2", "FARGATE", "EXTERNAL", or "all". Optional. Defaults to "EC2".
      NOTE: AWS uses EC2 instances with available resources to deploy FARGATE workloads. Sometimes the underlying EC2 instances will not support VPC traffic mirroring. For more info, please visit: https://docs.aws.amazon.com/vpc/latest/mirroring/traffic-mirroring-limits.html
      - **sniffer.vpcmirror.autosetup.source.ec2.instances**: []string. Comma-separatted sequence of IDs of EC2 instances to capture traffic from. Optional. 
      - **sniffer.vpcmirror.autosetup.source.ec2.autoscaling**: []string. Comma-separatted sequence of IDs of Auto-Scaling groups to capture traffic from. Optional.
    - The traffic **sniffer.vpcmirror.autosetup.target** nested values refer to the configuration for the AWS VPC traffic mirror target:
      - **sniffer.vpcmirror.autosetup.target.eks.cluster**: string. Name of the EKS cluster where Resurface is running. Required if **sniffer.vpcmirror.autosetup.enabled** is set to `true` and **sniffer.vpcmirror.autosetup.target.eks.id** is not set. 
      - **sniffer.vpcmirror.autosetup.target.eks.nodegroup**: string. Name of the nodegroup where Resurface is running. Filters out all nodes from other EKS nodegroups not intended for traffic mirroring. Optional.
      - **sniffer.vpcmirror.autosetup.target.id**: string. Traffic Mirror Target ID. Traffic mirror target creation is skipped when set to an already existing traffic mirror target. Required only if **sniffer.vpcmirror.autosetup.target.eks.cluster** is not set.
      - **sniffer.vpcmirror.autosetup.target.sg**: string. Security group attached to the ENI of a target EKS node. Used to create security group rules to allow mirrored traffic across source and target. Required only if **sniffer.vpcmirror.autosetup.target.eks.cluster** is not set.
      - **sniffer.vpcmirror.autosetup.filter.id**: string. Traffic Mirror Filter ID. Traffic mirror filter creation is skipped when set to an already existing traffic mirror target. Optional.

<!--      - **sniffer.vpcmirror.autosetup.source.ecs.tasks**: []string. Comma-separated sequence of IDs of ECS tasks to capture traffic from. Filters out all other ECS tasks not intended for traffic mirroring. Optional.-->


- **sniffer.port**: (deprecated) integer. Container port exposed by the application to capture packets from. Defaults to `80`. Required only if **sniffer.enabled** is `true` and no other option is enabled.
- **sniffer.device**: (deprecated) string. Name of the network interface to attach the sniffer to. Defaults to the Kubernetes custom bridge interface `cbr0`.

NOTE: When no services, pods, or labels are specified and discovery is disabled, the sniffer behavior falls back to logging from a specific network device on a specific port. This is not compatible with all Kubernetes environments and should be avoided by specifiying at least one service, pod or label, or enabling service discovery.

```yaml
sniffer:
  enabled: true
  discovery:
    enabled: false
    skip:
      ns: [ "kube-system" ]
      svc: [ "kubernetes" ]
  services:
  - namespace: mynamespace
    name: myservice
    ports: [ 8000, 3000 ]
  - namespace: anotherone
    name: anothersvc
  - namespace: thisoneworksfordiscoveryonly
  pods:
  - namespace: mynamespace
    name: mypod-12345A
    ports: [ 8080 ]
  - namespace: mynamespace
    name: mypod-12345B
  labels:
  - namespace: mynamespace
    keyvalues: [ "key1=value1","key2=value2","key4=value4" ]
  - keyvalues: [ "key3=value3", "key5=value5" ]
  logger:
    enabled: true
    rules: |
      include debug
      skip_compression
```

The **consumer** section contains the configuration for data stream consumer applications that capture API calls from currently supported API Gateways: Azure API Management, and AWS API Gateway. The containerized applications act as subscribers to platform-specific message bus services (Azure Event Hubs and AWS Kinesis Data Streams, respectively) that must be configured beforehand. More info on how to configure each application: [azure-eh](https://github.com/resurfaceio/azure-eh) and [aws-kds](https://github.com/resurfaceio/aws-kds).

- The **consumer.azure** subsection holds the values to configure and enable the `azure-eh` application.
  - **consumer.azure.enabled**: boolean. Defaults to `false`. Required only if **consumer.azure.enabled** is set to `true`.
  - **consumer.azure.ehname**: string. Defaults to `apimlogs`. Name of the Event Hubs instance streaming API calls published as log events by an Azure APIM instance.
  - **consumer.azure.storagecontainername**: string. Name of the Storage container associated with the required Azure Storage account. Required only if **consumer.azure.enabled** is set to `true`.
  - **consumer.azure.ehconnstring**: string. Connection string for the Event Hubs instance. It is **not** recommended to pass connection strings as helm values, and instead create a kubernetes secret object manually named **resurface-azure-cstrings** with the corresponding key-value pairs. Required only if **consumer.azure.enabled** is set to `true` and the **resurface-azure-cstrings** secret does not exist.
  - **consumer.azure.storageconnstring**: string. Connection string for the required Azure Storage account. It is **not** recommended to pass connection strings as helm values, and instead create a kubernetes secret object manually named **resurface-azure-cstrings** with the corresponding key-value pairs. Required only if **consumer.azure.enabled** is set to `true` and the **resurface-azure-cstrings** secret does not exist.

- The **consumer.aws** subsection holds the values to configure and enable the `aws-kds` application.
  - **consumer.aws.enabled**: boolean. Defaults to `false`.
  - **consumer.aws.kdsname**: string. Name of the Kinesis Data Streams instance streaming API calls published as CloudWatch log events by an AWS API gateway. Required only if **consumer.aws.enabled** is set to `true`.
  - **consumer.aws.region**: string. Region where the Kinesis Data Stream is deployed. Required only if **consumer.aws.enabled** is set to `true`.
  - **consumer.aws.accesskeyid**: string. AWS Credentials. It is **not** recommended to pass the AWS credentials as helm values, and instead create a kubernetes secret object manually named **resurface-aws-creds** with the corresponding key-value pairs. Required only if **consumer.aws.enabled** is set to `true` and the **resurface-aws-creds** secret does not exist.
  - **consumer.aws.accesskeysecret**: string. AWS Credentials. It is **not** recommended to pass AWS credentials as helm values, and instead create a kubernetes secret object manually named **resurface-aws-creds** with the corresponding key-value pairs. Required only if **consumer.aws.enabled** is set to `true` and the **resurface-aws-creds** secret does not exist.

- The **consumer.logger** nested section contains the configuration specific to the Resurface logger used by the consumer applications to send API calls to the corresponding importer endpoint.
  - **consumer.logger.enabled**: boolean. The internal logger can be temporarily disabled by setting this value to `false`.
  - **consumer.logger.rules**: string. The internal logger operates under a certain [set of rules](http://resurface.io/logging-rules) that determines which data is logged. These rules can be passed to the logger as a single-line or a multiline string.


```yaml
consumer:
  azure:
    enabled: true
    ehname: apimlogs
    storagecontainername: containerabcdef
  aws:
    enabled: false
    kdsname: resurfaceio-kds-123456789
    region: us-west-2
  logger:
    enabled: true
    rules: |
      include debug
```
