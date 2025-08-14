---
excerpt: "This blog post discusses how to integrate ExternalDNS with Azure DNS using workload identity. The guide covers the installation and configuration of ExternalDNS on Azure Kubernetes Service (AKS) using nginx ingress, Helm chart + Helmfile, Azure DNS, and workload identities. It also provides troubleshooting tips and highlights the benefits of using ExternalDNS for DNS management."

title: "ExternalDNS integration with Azure DNS using workload identity"

image: /assets/posts/2024-02-08-ExternalDNS-integration-with-Azure-DNS-using-workload-identity/header.webp

date: 2024-02-08

categories:
  - Blog

tags:
  - Terraform
  - Azure
  - Security
  - Managed Identity
  - AKS
  - Bicep

---

* toc
{:toc .large only} 

# Introduction

Managing DNS records manually is error-prone and just tedious. When deploying internet-facing apps to your Kubernetes cluster, setting domain names on ingress is a must. Why not take advantage of already defined ingress rules and enable your cluster to update the designated DNS zone using the workload identity mechanism and ExternalDNS controller?

In this guide, I'll demonstrate the integration on Azure Kubernetes Service (AKS) with nginx ingress, Helm chart + Helmfile, Azure DNS, and workload identities. However, you can set up ExternalDNS not only on AKS but also on any Kubernetes cluster with various supported DNS providers.

# Prerequisites

While ExternalDNS supports many authentication options, I strongly recommend using workload identities to authenticate from the cluster to Azure DNS resources. If you're not using workload identities in your cluster yet, or you are using the deprecated AAD pod identity mechanism, follow [this article.](./A-Step-by-Step-Guide-to-installing-Azure-Workload-Identities-on-AKS)

This approach ties down permissions only to ExternalDNS pods, reducing the possibility of leaked secrets and potential serious problems if you lose control over your DNS zone. Additionally, ensure you have ingress installed on your cluster.

# Create Azure DNS zone, identity and grant permissions

Before proceeding to install ExternalDNS on your cluster, set up Azure DNS zone, create a managed identity, and grant this identity the `DNS Zone Contributor` role to allow updating DNS records. This can be achieved in various ways, such as using Terraform, Bicep, or Azure CLI. Alternatively, this can be done from the portal. However, I challenge you to maintain all your configurations within the git repository.

## Terraform 

The following Terraform snippets outlines the necessary resources to create and manage Azure DNS zones and identities. and assigns the necessary roles and permissions.

### Variables file

```terraform
variable "project_name" {
  type        = string
  description = "Project name"
}

variable "resources_suffix" {
  type        = string
  default     = "common"
  description = "suffix that will be added to created resources"
}

variable "environment" {
  type        = string
  description = "Name of the environment"
}

variable "primary_location" {
  type = object({
    name      = optional(string, "westeurope")
    shortcode = optional(string, "weu")
  })
  description = "The Azure location where resources will be created"
}

variable "dns_zone_name" {
  type        = string
  description = "dns zone name like example.com"
}

variable "oidc" {
  type = object({
    audience                       = optional(list(string), ["api://AzureADTokenExchange"])
    issuer_url                     = string
    kubernetes_namespace           = optional(string, "external-dns")
    kubernetes_serviceaccount_name = optional(string, "external-dns")
    kubernetes_cluster_name        = string
  })
  description = "Configure OIDC federation settings to establish a trusted token mechanism between the Kubernetes cluster and external systems."
}
```

### Create DNS zone
```terraform
resource "azurecaf_name" "this" {
  resource_types = [
    "azurerm_resource_group"
  ]
  name        = var.primaryLocation.shortcode
  prefixes    = [var.project_name, substr(var.environment, 0, 3)]
  suffixes    = [var.resources_suffix]
  clean_input = true
}

resource "azurerm_resource_group" "this" {
  name     = format("%s-%02s", azurecaf_name.this.results["azurerm_resource_group"], 1)
  location = var.primary_location.name
}

resource "azurerm_dns_zone" "this" {
  name                = var.zone_name
  resource_group_name = azurerm_resource_group.this.name
}
```

### Create managed identity for ExternalDNS service account
```terraform
resource "azurecaf_name" "externaldns" {
  resource_types = [
    "azurerm_user_assigned_identity"
  ]
  name        = var.primaryLocation.shortcode
  prefixes    = [var.project_name, substr(var.environment, 0, 3)]
  suffixes    = [var.resources_suffix, "externaldns-01"]
  clean_input = true
}

resource "azurerm_user_assigned_identity" "this" {
  name                = azurecaf_name.externaldns.results["azurerm_user_assigned_identity"]
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
}

resource "azurerm_federated_identity_credential" "this" {
  name                = "${var.kubernetes_cluster.name}-ServiceAccount-${var.oidc.kubernetes_namespace}-${var.oidc.kubernetes_serviceaccount_name}"
  resource_group_name = azurerm_resource_group.this.name
  audience            = var.oidc.audience
  issuer              = var.oidc.issuer_url
  parent_id           = azurerm_user_assigned_identity.this.id
  subject             = "system:serviceaccount:${var.oidc.kubernetes_namespace}:${var.oidc.kubernetes_serviceaccount_name}"
}
```

### Grant permissions
```terraform
resource "azurerm_role_assignment" "dns_zone_contributor" {
  principal_id                     = azurerm_user_assigned_identity.this.principal_id
  role_definition_name             = "DNS Zone Contributor"
  scope                            = azurerm_dns_zone.this.id
  skip_service_principal_aad_check = true
}
```

## Bicep

Sample template - resource group context

### Parameters
```terraform
param zoneName string
param aksClusterName string
param env string
param issuerUrl string
param managedIdentityName string 

param externalDnsNamespace string = 'external-dns'
param externalDnsServiceAccount string = 'external-dns'
```

### Create DNS zone
```terraform
resource dnsZone 'Microsoft.Network/dnsZones@2018-05-01' = {
  name: zoneName
  location: 'global'
}
```

### Create managed identity for ExternalDNS service account
```terraform
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: managedIdentityName
  location: resourceGroup().location
}

resource federatedCredentials 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  name: '${aksClusterName}-serviceaccount-${externalDnsNamespace}:${externalDnsServiceAccount}'
  properties: {
    audiences: [
      'api://AzureADTokenExchange'
    ]
    issuer: issuerUrl
    subject: 'system:serviceaccount:${externalDnsNamespace}:${externalDnsServiceAccount}'
  }
  parent: managedIdentity
}

```

### Grant permissions
```terraform
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2023-04-01' = {
  name: '${managedIdentityName}-dnsZoneContributor'
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', 'befefa01-2a29-4197-83a8-272ff33ce314')
    principalType: 'ServicePrincipal'
    principalId: managedIdentity.properties.principalId  
  }
}
```

## Azure CLI

Line breaks are for PowerShell if you are using different shell, replace ` with \

### Set variables 
```powershell
$rgName = "dns-rg"
$location = "westeurope"
$identityName = "externaldns-identity"
$dnsZoneName="dev.cloudchronicles.blog"
$aksClusterName = "aks-cluster"
$aksRgName = "aks-rg"
```

### Create DNS zone
```powershell
az group create --name $rgName `
                --location $location

az network dns zone create --resource-group $rgName `
                           --name $dnsZoneName
```

### Create managed identity
```powershell                         
az identity create --resource-group $rgName `
                   --name $identityName

$identityClientId = az identity show --resource-group $rgName `
                                     --name $identityName `
                                     --query "clientId" `
                                     --output tsv
```

### Grant DNS Zone Contributor to identity
```powershell
$dnsId = az network dns zone show --name $dnsZoneName `
                                  --resource-group $rgName `
                                  --query "id" `
                                  --output tsv

$dnsRgId = az group show --name $rgName `
                         --query "id" `
                         --output tsv

az role assignment create --role "DNS Zone Contributor" `
                          --assignee $identityClientId `
                          --scope $dnsId
```

### Create federation between service account and identity
```powershell
$oidcIssuerUrl = az aks show --name $aksClusterName `
                             --resource-group $aksRgName `
                             --query "oidcIssuerProfile.issuerUrl" `
                             --output tsv

az identity federated-credential create --name $identityName `
                                        --identity-name $identityName `
                                        --resource-group $rgName `
                                        --issuer $oidcIssuerUrl `
                                        --subject "system:serviceaccount:external-dns:external-dns"
```

# Install ExternalDNS on you cluster

Two Helm charts are provided for your convenience, one published by Bitnami and another by Kubernetes Sigs. My personal preference is the Bitnami chart due to its popularity, though the choice ultimately depends on your specific requirements. 

Setting resource limits for ExternalDNS pods is optional, but highly recommended for optimal performance and resource management on your cluster. The suggested values can serve as a helpful starting point based on my experience.

Although most of the configuration is generic, there are specific entries tailored for an Azure DNS scenario, particularly with workload identity:

Specify the DNS provider for creating DNS records.
```yaml
provider: azure
```

Configure Azure DNS, ensuring that `tenantId`, `subscriptionId`, and `resourceGroup` name point to the correct values for the DNS zone resource location.
```yaml
azure:
  useWorkloadIdentityExtension: true
  tenantId: < azure tenant id >
  subscriptionId: < subscription id with dns zone resource >
  resourceGroup: < resource group name with dns zone resource >
```

Configure pod labels and service account annotations for workload identity.
```yaml
podLabels:
  azure.workload.identity/use: "true"

serviceAccount:
  annotations: 
    azure.workload.identity/client-id: < the clientId of managed identity with DNS zone permissions >
```

Azure DNS does not support `*` in the middle of DNS entries like AWS Route53 or GCP DNS. ExternalDNS, by default, attempts to create `a-*` entries for wildcard ingress rules, resulting in errors. 

```bash
time="2022-08-01T13:10:44Z" level=info msg="Updating TXT record named 'a-*.example' to '\"heritage=external-dns,external-dns/owner=default,external-dns/resource=ingress/xxx/yyy\"' for Azure DNS zone 'example.com'."
time="2022-08-01T13:10:44Z" level=error msg="Failed to update TXT record named 'a-*.example' to '\"heritage=external-dns,external-dns/owner=default,external-dns/resource=ingress/xxx/yyy\"' for DNS zone 'example.com': dns.RecordSetsClient#CreateOrUpdate: Failure responding to request: StatusCode=400 -- Original Error: autorest/azure: Service returned an error. Status=400 Code=\"BadRequest\" Message=\"The domain name 'a-*.example.example.com' is invalid. The provided record set relative name 'a-*.example' is invalid.\""
```

To address this, override `*` with a specific value, such as `wildcard`, using the `txt-wildcard-replacement` argument during deployment.
```yaml
extraArgs:
  txt-wildcard-replacement: "wildcard"
```

## Helm 
{% raw %}
```powershell
helm repo add bitnami https://charts.bitnami.com/bitnami

helm install external-dns bitnami/external-dns `
  --version 6.32.0 `
  --namespace=external-dns `
  --set provider=azure `
  --set policy=sync `
  --set azure.useWorkloadIdentityExtension=true `
  --set azure.resourceGroup=rg-name-with-dns-zone-resource ` # the resource group name where DNS zone is located
  --set azure.subscriptionId=c32d5ab5-478d-47ud-bc61-230d5511a0f0 `
  --set azure.tenantId=ald2e401-0911-47f6-8e20-13819f4bd107 `
  --set extraArgs.txt-wildcard-replacement=wildcard `
  --set serviceAccount.annotations."azure\.workload\.identity/client-id"=7d878f79-e2c7-41ee-a592-57ac74f14096 `
  --set podLabels."azure\.workload\.identity/use"=true `
  --set txtOwnerId=external-dns `
  --set logLevel=info `
  --set domainFilters[0]=dev.cloudchronicles.blog `
  --set domainFilters[1]=dev.next.domain ` # if you want to add more than one domain
  --set resources.requests.cpu=10m `
  --set resources.requests.memory=32Mi `
  --set resources.limits.cpu=50m `
  --set resources.limits.memory=64Mi
```
{% endraw %}
## Helmfile

To avoid redundancy and potential errors in configuration, I use two values files: one for general settings shared across all environments `values.yaml`, and another for environment-specific configurations `values.env.yaml`. However, you can merge these files into a single `values.yaml` and eliminate environment-specific files if desired.

*helmfile.yaml*
{% raw %}
```yaml
environments:
  dev:
  prd:

repositories:
  - name: bitnami
    url: https://charts.bitnami.com/bitnami

releases:
  - name: external-dns
    namespace: external-dns
    chart: bitnami/external-dns
    version: 6.32.0
    values:
    - values.yaml
    - values.{{ .Environment.Name }}.yaml
```
{% endraw %}
*values.yaml*
```yaml
provider: azure

policy: sync

azure:
  useWorkloadIdentityExtension: true
  tenantId: < azure tenant id >

txtOwnerId: external-dns

extraArgs:
  txt-wildcard-replacement: "wildcard"

podLabels:
  azure.workload.identity/use: "true"

resources:
  requests:
    cpu: 10m
    memory: 32Mi
  limits:
    cpu: 50m
    memory: 64Mi
```

*values.dev.yaml*
```yaml
azure:
  resourceGroup: < resource group name with dns zone resource >
  subscriptionId: < subscription id with dns zone resource >
logLevel: info
domainFilters:
  - dev.cloudchronicles.blog
  - dev.next.domain #if you want to add more than one

serviceAccount:
  annotations: 
    azure.workload.identity/client-id: < the clientId of managed identity with DNS zone permissions >
```

To apply above helmfile configuration, run:
```powershell
helmfile --environment dev --file "helmfile.yaml" sync
```

## Check status

There is no GUI for ExternalDNS. If you don't believe helm/helmfile status that deployment was successful, then you can run following command:
```bash
kubectl get  pods -n external-dns -l app.kubernetes.io/name=external-dns 
# adjust namespace name and/or pod label name if you selected another name or namespace

NAME                          READY   STATUS    RESTARTS   AGE
external-dns-c764ddc4-j8lhb   1/1     Running   0          8d
```
...or if you are using AKS, then you can check it in portal.

![ExternalDNS deployed on aks](/assets/posts/2024-02-08-ExternalDNS-integration-with-Azure-DNS-using-workload-identity/externaldns-deployed-on-aks.webp)

# Adding ingress rules

ExternalDNS will now monitor all ingress rules and try to create records for rules matching domains provided in `domainFilters`. With the `policy: sync`, if you modify or delete an ingress rule, it will update accordingly. If you want to change this behavior, for example, to only modify a record if there is a replacement value, set the ExternalDNS policy to `upsert`.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: frontend
  labels:
    app.kubernetes.io/name: frontend
    app.kubernetes.io/instance: frontend
  annotations:
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
      - "dev.cloudchronicles.blog"
      - "*.dev.cloudchronicles.blog"
      secretName: wildcard-dev-cloudchronicles-blog
  rules:
    - host: "dev.cloudchronicles.blog"
      http:
        paths:
          - path: /
            pathType: ImplementationSpecific
            backend:
              service:
                name: frontend
                port:
                  number: 80
```

Above configuration is enough for ExternalDNS. Ingress domain name matches domain specified in configuration, so controller will create new records for the domain.

![Records created by ExternalDNS](/assets/posts/2024-02-08-ExternalDNS-integration-with-Azure-DNS-using-workload-identity/external-dns-records.webp)

As you can see, ExternalDNS created TXT records for each A record. Thanks to that, it knows which records are under its control.
```
TXT "heritage=external-dns,external-dns/owner=external-dns,external-dns/resource=ingress/frontend-namespace/frontend"
```

# Manually managing the rules

ExternalDNS creates TXT records to know which records it can manage. If you want to manually modify a record created by ExternalDNS, simply remove the associated TXT record and update existing record. 

You can also create a new record that won't be overridden by ExternalDNS, even if someone creates an ingress rule for such name. 

If you delete an existing A record created by ExternalDNS, the controller will recreate it within a few seconds.

# Troubleshooting problems

In case you encounter any issues with updating your DNS records, check the logs, which are very descriptive.
```bash
kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns
# adjust namespace name and/or pod label name if you selected another name or namespace
```

It's also worth mentioning that ExternalDNS has a large community, so you should quickly find answers to your problems on Stack Overflow or receive replies to your issues in the [GitHub repository.](https://github.com/kubernetes-sigs/external-dns).

# Conclusion
Using ExternalDNS is a great option for those who want to simplify DNS management. No more complex scripts and orchestrating changes between the DNS provider and the Kubernetes cluster.
