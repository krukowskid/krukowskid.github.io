---
excerpt_text: "Learn to transition from AAD Pod Identities or install from scratch Azure Workload Identities, using tools like Terraform, Helm, and Helmfile."

title: "A Step-by-Step Guide to installing Azure Workload Identities on AKS"

header:
  teaser: /assets/posts/2023-06-04-A-Step-by-Step-Guide-to-installing-Azure-Workload-Identities-on-AKS/header.png

date: 2023-06-04

categories:
  - Blog

tags:
  - Azure
  - AKS
  - Managed Identity
  - Security
  - Helm
  - Terraform

toc: true
toc_sticky: true
---

![Header](/assets/posts/2023-06-04-A-Step-by-Step-Guide-to-installing-Azure-Workload-Identities-on-AKS/header.png)

# Introduction

Hello! In this guide, we will walk through the process of installing the new Workload Identities, which have replaced AAD Pod Identity. Whether you are transitioning from the outdated AAD Pod Identities or starting fresh with Workload Identity, this guide will provide you with step-by-step instructions. If you are migrating from pod identities, the steps outlined below should not affect the existing mechanism. Both pod identity and workload identity are controlled by labels and annotations, allowing you to install and migrate services in parallel. You can migrate services one-by-one by changing the labels and annotations accordingly. 

Remember to test each step in a separate test environment before applying them to your production environment.

# Update tools and dependencies

While updating tools and dependencies may not be required depending on your current versions, it is recommended to perform these updates before starting the installation process. Recent changes have been introduced, and updating everything ensures you have the latest versions in place. This helps to avoid any potential compatibility issues and ensures a smoother installation experience.

## azurerm Terraform provider
In my scenario, the initial step was updating the `azurerm` provider in my template. I updated my AKS-related template from `3.33.0` to `3.59.0` to ensure a smooth transition. The upgrade didn't introduce any changes for me, which was confirmed with the `terraform plan` command. 

```terraform
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.59.0"
    }
  }
}
```

## Azure CLI

If you want to use Azure CLI, make sure you have latest version installed. 
You can upgrade your Azure CLI by running `az upgrade` in terminal.

## Azure.Identity SDK
To ensure compatibility with Workload Identity, it's important to use the right version of the `Azure.Identity` SDK. In my case, since I'm using dotnet for my backend, I needed to update the package to version `1.9.0` to make `DefaultAzureCredential` work with Workload Identity. You can find more information about supported SDK versions [in the Azure AD Workload Identity doumentation.](https://azure.github.io/azure-workload-identity/docs/topics/language-specific-examples/azure-identity-sdk.html)

# Enabling OIDC and Workload Identities in AKS cluster

## Terraform
After updating the provider, you can add support for OIDC and Workload Identities to your AKS module in Terraform. Modify your `azurerm_kubernetes_cluster` resource as follows:

```terraform
resource "azurerm_kubernetes_cluster" "this" {
...
    oidc_issuer_enabled       = true
    workload_identity_enabled = true
...
}
```
to make the module more flexible and reusable across different projects, I have assigned variables to parameters in my AKS terraform module. This way I can decide if I want to enable it from parameters file instead of hardcoding it in the template.

Here's an example of how you can do this:
```terraform
variable "oidc_issuer_enabled" {
  type        = bool
  description = "Defines if OIDC issuer should be enabled on cluster"
  default     = true
}

variable "workload_identity_enabled" {
  type        = bool
  description = "Defines if workload identity should be enabled on cluster. This requires oidc_issuer_enabled set to true"
  default     = true
}

resource "azurerm_kubernetes_cluster" "this" {
...
    oidc_issuer_enabled               = var.oidc_issuer_enabled
    workload_identity_enabled         = var.workload_identity_enabled
...
}

output "aks_cluster" {
  value = {
    name                = azurerm_kubernetes_cluster.this.name
    oidc_issuer_url     = var.oidc_issuer_enabled ? azurerm_kubernetes_cluster.this.oidc_issuer_url : null
    ...
  }
  description = <<EOT
    AKS cluster details:
    * `name` - cluster name
    * `oidc_issuer_url` - cluster OIDC issuer url
    ...
  EOT
}
```
If you encounter a bug where the `oidc_issuer_url` isn't available immediately after enabling `oidc_issuer_enabled` just wait a moment, and apply template once again.

Setting `oidc_issuer_enabled` to `true` allows your cluster to issue internal tokens that will be subsequently swapped for Azure tokens. This can also be accomplished by running CLI command, but if you're utilizing Terraform for AKS, I recommend using the provider for this step.

Enabling `workload_identity_enabled` deploys the Workload Identity resources to your `kube-system` namespace. If you prefer more control over this deployment (like me), refrain from enabling it in Terraform or CLI, but instead deploy it from the provided Helm chart, which allows customization like namespace, tolerations, etc.

## Azure CLI

To enable OIDC issuer on cluster you need to update cluster with following flag `--enable-oidc-issuer`
```bash
az aks update -g <resource-group> -n <cluster-name> --enable-oidc-issuer
```
The `--enable-oidc-issuer` can be also used during cluster creation from CLI.
    
If you'd rather utilize CLI instead of Terraform or Helm, simply add `--enable-workload-identity` to the previous command.

```bash
az aks update -g <resource-group> -n <cluster-name> --enable-oidc-issuer --enable-workload-identity
```

In next steps we will need the OIDC issuer url of cluster to setup federation between managed identity resource.
```bash
az aks show --resource-group <resource_group> --name <cluster_name> --query "oidcIssuerProfile.issuerUrl" -otsv
```

Note that when using the CLI, the Workload Identity resources will be created in the `kube-system` namespace. If you want to customize the deployment, you can use the Helm chart provided.

## Helm chart

If you prefer using Helm, there is a [ready to use chart provided by Azure](https://artifacthub.io/packages/helm/azure-workload-identity/workload-identity-webhook). There are multiple ways to install it on your cluster - with helm, terraform etc. 
You need to enable oidc issuer on cluster with Terraform / Azure CLI in order to enable workload identity with Helm.

Example installation with helm install: 
```bash
repo add azure-workload-identity https://azure.github.io/azure-workload-identity/charts
helm repo update
helm install workload-identity-webhook azure-workload-identity/workload-identity-webhook \
   --namespace azure-workload-identity \
   --create-namespace \
   --set azureTenantID="<azure-tenant-id>"
```
The only required parameter is azureTenantID. You can find your tenant ID by following the steps outlined in the [Azure documentation.](https://learn.microsoft.com/en-us/azure/active-directory/fundamentals/active-directory-how-to-find-tenant)

# Federate Service Account

Now that we have prepared the cluster for Workload Identities, we need to configure our managed identities and Kubernetes deployments. By default, the Managed Identity will not accept a token generated by our cluster. To enable this, we need to establish a federation between the identity and Kubernetes service account.

## Terraform

To implement this federation, add an azurerm_federated_identity_credential resource with the appropriate values and link it to the previously created managed identity resource. Here's an example how I implemented it in my reusable module:
```terraform
resource "azurerm_user_assigned_identity" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
}

resource "azurerm_federated_identity_credential" "this" {
  count               = var.oidc.enabled ? 1 : 0
  name                = "${var.oidc.kubernetes_cluster_name}-ServiceAccount-${var.oidc.kubernetes_namespace}-${var.oidc.kubernetes_serviceaccount_name}"
  resource_group_name = var.resource_group_name
  audience            = var.oidc.audience
  issuer              = var.oidc.issuer_url
  parent_id           = azurerm_user_assigned_identity.this.id
  subject             = "system:serviceaccount:${var.oidc.kubernetes_namespace}:${var.oidc.kubernetes_serviceaccount_name}"
}

variable "oidc" {
  type = object({
    enabled                        = bool
    audience                       = optional(list(string), ["api://AzureADTokenExchange"])
    issuer_url                     = string
    kubernetes_namespace           = string
    kubernetes_serviceaccount_name = string
    kubernetes_cluster_name        = string
  })
  description = "Configure OIDC federation settings to establish a trusted token mechanism between the Kubernetes cluster and external systems."
  default = {
    enabled                        = false
    issuer_url                     = ""
    kubernetes_namespace           = ""
    kubernetes_serviceaccount_name = ""
    kubernetes_cluster_name        = ""
  }
}
```

## Azure CLI

To create federated credentials in your managed identity resource using the Azure CLI, run the following command:

```bash
az identity federated-credential create --name <federated-credential-name> --identity-name <user-assigned-mi-name> --resource-group <rg-name> --issuer <aks-oid-issuer-uri> --subject system:serviceaccount:<service-account-namespace>:<service-account-name>
```

To obtain the `--issuer` value, run the following command:

```bash
az aks show --resource-group <resource_group> --name <cluster_name> --query "oidcIssuerProfile.issuerUrl" -otsv
```

# Deploy application to the cluster

With the cluster and Azure Managed Identity ready for Workload Identities, we need to set up the Kubernetes Service Account and Deployment/Pod definitions. Configuring these values is a straightforward task, but automating the process could become complex depending on your current workflow. In my case, I simply pass the Managed Identity client id from the Terraform output to the Helmfile values in the GitHub Actions Workflow, but you can simply copy-paste it to your manifest if that works better for you.

## Service Account
In the service account definition, add the following annotation:

```yaml
azure.workload.identity/client-id: "<client-id-of-your-managed-identity>"
```

### Helm / Helmfile
For Helm or Helmfile deployments, modify your ServiceAccount template as follows:
{% raw %}
```yaml
{{- if .Values.serviceAccount.create -}}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ include "backend.serviceAccountName" . }}
  labels:
    {{- include "backend.labels" . | nindent 4 }}
  {{- with .Values.serviceAccount.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
automountServiceAccountToken: {{ .Values.serviceAccount.automountToken | default false }}
{{- end }}
```
{% endraw %}

To set the annotation in your template, pass the following values to your Helmfile deployment:

```yaml
serviceAccount:
  create: true
  annotations:
    azure.workload.identity/client-id: "<client-id-of-your-managed-identity>"
```

### Kubernetes manifest

If you are using plain Kubernetes manifests, use the following definition for your ServiceAccount:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: <service-account-name>
  namespace: <service-account-namespace>
  annotations:
    azure.workload.identity/client-id: "<client-id-of-your-managed-identity>"
```
## Deployment/Pod
Now that the Service Account is linked to the managed identity, you can utilize it in your Pod or Deployment definition.

To use the Service Account, specify it in the pod definition:

```yaml
serviceAccountName: "<service-account-name-with-provided-client-id>"
```

```yaml
# Pod definition with serviceAccountName specified
apiVersion: v1
kind: Pod
metadata:
  name: my-pod
spec:
  serviceAccountName: build-robot
```

Additionally, add the following label to instruct the webhook service to inject the Workload Identity configuration into your pod:

```yaml
azure.workload.identity/use: "true"
```

If you are migrating from pod identity, it's important to remove the `aadpodidentity` labels from your deployment at this stage to ensure that your deployment is using the new Workload Identity mechanism.

### Helm / Helmfile
To add the label using Helm or Helmfile, modify your template as follows:

{% raw %}
```yaml
azure.workload.identity/use: {{ (.Values.workloadIdentity).enabled | default false | quote }}
```
{% endraw %}

Pass the following values to your Helm/Helmfile parameters:

```yaml
workloadIdentity:
  enabled: true
```
If you are using for deployment a Helm chart created with `helm create` command, then to use service account you can pass he following values:
```yaml
serviceAccount:
  create: true
```

The additional braces allow the value to be null and fallback to "false", enabling you to switch services one-by-one. Without these braces, Helm will throw an error when resolving the value.

# Removing AAD Pod Identity

Before removing AAD Pod Identity, ensure that it is no longer in use by any services in your cluster. You can check the AAD Pod Identity logs with the following command:

```bash
kubectl logs -l "app.kubernetes.io/name=aad-pod-identity" -n aad-pod-identity --follow
```

If there are no indications that AAD Pod Identity is still in use, you can proceed with its removal. Start by removing the `AzureIdentityBinding` and `AzureIdentity` resources. The `aadpodidbinding` labels should be removed yet in previous steps. Once you have confirmed that everything is still functioning correctly, you can delete the AAD Pod Identity pods. The uninstallation process may vary depending on how you initially installed it. For example, if you used Helm, you can use the[helm uninstall command.](https://helm.sh/docs/helm/helm_uninstall/)

# Conclusion

With these steps, you can smoothly transition from AAD Pod Identities or install from scratch Azure Workload Identities in your AKS cluster. Remember to follow best practices and test changes in a separate environment before applying them to your production cluster.