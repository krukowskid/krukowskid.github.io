---
excerpt_text: "Enhance your CI/CD pipelines with passwordless authentication using Workload Identity Federation in GitHub Actions and Azure DevOps. Eliminate credential management and boost security for efficient deployments."
excerpt: "Enhance your CI/CD pipelines with passwordless authentication using Workload Identity Federation in GitHub Actions and Azure DevOps. Eliminate credential management and boost security for efficient deployments."

title: "Passwordless Authentication for GitHub Actions and Azure DevOps"

header:
  teaser: /assets/posts/2023-12-05-Passwordless-Authentication-for-GitHub-Actions-and-Azure-DevOps/header.png

date: 2023-12-05

categories:
  - Blog

tags:
  - Azure DevOps
  - CICD
  - Terraform
  - Azure
  - GitHub Actions
  - Azure Pipelines
  - Security

toc: true
toc_sticky: true
---

![Header](/assets/posts/2023-12-05-Passwordless-Authentication-for-GitHub-Actions-and-Azure-DevOps/header.png)

# Introduction

In recent weeks, I've had the pleasure of speaking at conferences and community events, sharing insights into cool things related to GitHub in Azure development. One of the most frequently asked questions was about passwordless authentication for CI/CD pipelines. In response, I've decided to create a comprehensive guide on federated credentials for both Azure DevOps and GitHub Actions.

## Why you should use passwordless authentication

Setting up password-based authentication is straightforward, managing and securing secrets is not. Are you rotating passwords when team members leave? Are you doing it regularly? Are you confident that no one is storing passwords in plain text?

While various tools can help manage secrets, it's practically impossible to track and manage every secret effectively. Fortunately, there's a simple solution: get rid of all passwords!

## How it works

The mechanism  that will allow you to connect without certificate or password is OpenID Connect (OIDC). OIDC is an authentication protocol based on the OAuth2 protocol (which is used for authorization). While those terms may go together in many cases they are not the same but connected. While OAuth2 is focused on authorization, OIDC is build on top of OAuth2 standard and focused on authentication, so OIDC role is to prove your, or your resource identity.

![oidc flow](/assets/posts/2023-12-05-Passwordless-Authentication-for-GitHub-Actions-and-Azure-DevOps/oidc.gif)
*Source: https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation*

1. The external workload (GitHub Actions workflow/Azure DevOps pipeline) requests a token from the external IdP (such as GitHub/Azure Devops).
2. The external IdP issues a token to the external workload.
3. The external workload (the login action in a GitHub workflow/step using service connection, for example) sends the token to Microsoft identity platform and requests an access token.
4. Microsoft identity platform checks the trust relationship on the user-assigned managed identity or app registration and validates the external token against the OpenID Connect (OIDC) issuer URL on the external IdP.
5. When the checks are satisfied, Microsoft identity platform issues an access token to the external workload.
6. The external workload accesses Microsoft Entra protected resources using the access token from Microsoft identity platform. A GitHub Actions workflow/Azure DevOps pipeline, for example, uses the access token to publish a web app to Azure App Service.

In simpler terms, you're informing your Azure App Registration or Managed Identity that tokens from the specified source are trustworthy. Think of it like an identity card from your country. When you present it in a foreign country, they'll verify your identity because your country's (external identity provider) is trusted in this country.

# Configuration

To enable passwordless authentication for your CICD pipelines in Azure DevOps or GitHub Actions, you can choose between app registration and managed identity. Both methods provide similar functionality, but there are some key differences that could influence your choice.

## App Registration vs Managed Identity

**App Registration**
* Managed at the tenant level
* Requires privileges to create Applications in Azure Active Directory, and Owner role on selected Azure scope
* Limited to 20 federated credentials per application
* Can be used to interact with a broader range of services - you can assign scopes from Graph Api
* Default token lifetime is 60 - 90 minutes

**Minimum permissions needed to create service connection with app registration:**
- Azure DevOps
  - `Creator`- service connection
- Azure
  - `Application Developer` - Entra role
  <br>or
  - `Application.ReadWrite.OwnedBy` - GraphApi scope

**Managed Identity**
* Managed at the resource group level
* Can be managed with contributor permission on the resource group
* Limited to 20 federated credentials per identity
* Federated credentials are not yet available in all regions - [documentation](https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation-considerations?WT.mc_id=AZ-MVP-5003237#unsupported-regions-user-assigned-managed-identities)
* Can be used to interact only with Azure resources
* Default token lifetime is 24 hours

**Minimum permissions needed to create service connection with managed identity:**
- Azure DevOps
  - `Creator` - service connection
- Azure
  - `Contributor` - on resource group

Generally, app registration is better suited for scenarios where you need to interact with a wide range of services, while managed identity is a good choice if you want to delegate management to project teams or tie its lifecycle to project lifecycle. 

If you're unsure about the number of connections you need, start with one Azure DevOps connection and one managed identity/app registration per environment, with permission scoped only to environment resources - preferably a separate subscription per environment, but separate resource groups will work as well.

## Azure DevOps

Azure DevOps support for workload identity was recently added, and the ease of configuration is outstanding. However, using the token in your scripts is a bit challenging due to a lack of comprehensive information in blogs and documentation yet. 

Enabling workload identity in your pipelines is a straightforward and safe task, but it's not yet supported by all marketplace tasks, so your scripts and steps may require minor adjustments if you're currently using secrets or certificates.

### Automatic configuration - App registration

The automatic configuration option is the simplest and recommended approach. It streamlines the setup by automatically creating an app registration and configuring federation for you.

1. **Create a Service Connection:** Navigate to Project `Settings` > `Service Connections` and select `New service connection`. Choose `Azure Resource Manager` and select `Workload Identity federation (automatic)`.

2. **Provide Connection Details:** Enter a connection name and the scope where permissions should be assigned (you need to be an **Owner** on the selected scope).

3. **Save and Verify:** Save the connection. A new app registration will be created in your tenant, and federation will be configured to your Azure DevOps connection.

![automatic workload identity configuration](/assets/posts/2023-12-05-Passwordless-Authentication-for-GitHub-Actions-and-Azure-DevOps/automatic-creation.gif)

Once the app registration is created, you're ready to utilize passwordless identity. For more complex scenarios or strict requirements, you may need to adjust permissions for the app registration to grant or restrict access.

### Manual configuration - Managed Identity / App registration

If you prefer to create connection manually or you want to use managed identities, you can follow the manual configuration process. This involves creating the managed identity/app registration and configuring federation yourself.

1. **Create a Service Connection:** 
In Azure DevOps, navigate to `Project Settings` > `Service Connections` and select `New service connection`. Choose Azure Resource Manager and select `Workload Identity federation (manual)`. After providing the service connection name, go the step 2 to create Azure principal and get its client id.
![Create a service connection](/assets/posts/2023-12-05-Passwordless-Authentication-for-GitHub-Actions-and-Azure-DevOps/new-connection-manual.gif)

2. **Create a Managed Identity / App Registration:** Create new Managed Identity in a resource group or create a new app registration in Azure Entra ID. 

3. **Configure Federation:** After creating principal, create new federated credentials.
![Create managed identity](/assets/posts/2023-12-05-Passwordless-Authentication-for-GitHub-Actions-and-Azure-DevOps/managed-identity-federated-credentials.gif)
*Managed&nbsp;identity*<br><br>
![Create managed identity](/assets/posts/2023-12-05-Passwordless-Authentication-for-GitHub-Actions-and-Azure-DevOps/app-registration-federated-credentials.gif)
*Appregistration*<br><br>
Select **Other**
<br>
![add](/assets/posts/2023-12-05-Passwordless-Authentication-for-GitHub-Actions-and-Azure-DevOps/add-federated.gif)
<br><br>
Enter the Azure DevOps service connection's `Issuer URL` and 
`Subject identifier` from the first step. 
![credentials details](/assets/posts/2023-12-05-Passwordless-Authentication-for-GitHub-Actions-and-Azure-DevOps/credentials-details.gif)
<br><br>
The **Issuer URL** value is always `https://vstoken.dev.azure.com/<azure-devops-organization-id>` and **Subject identifier** format is `sc://<azure-devops-organization-name>/<project-name>/<service-connection-name>`. 

4. **Update Service Connection with principal data:** After creating a principal, and configuring federation go back to Azure DevOps new Service Connection wizard (step 1) and provide created principal **client id** and **tenant id**.<br>
![add](/assets/posts/2023-12-05-Passwordless-Authentication-for-GitHub-Actions-and-Azure-DevOps/principal-client-id.gif)
Now you can click `Save and verify` and start using your passwordless connection!

{% capture notice %}
**_NOTE:_** You will find client id in app registration/managed identity overview tab, and tenant id in Entra ID tenant overview tab.
{% endcapture %}
<div class="notice">{{ notice | markdownify }}</div>

### Terraform configuration - Managed Identity / App registration

This section outlines the Terraform configuration for passwordless authentication

#### Using app registration
```terraform
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.83.0"
    }
    azuredevops = {
      source = "microsoft/azuredevops"
      version = "=0.10.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "=2.46.0"
    }
  }
}

provider "azurerm" {
  features {}
}

provider "azuread" {
  tenant_id = "00000000-0000-0000-0000-000000000000"
}

resource "azuread_application_registration" "this" {
  display_name = "example-app"
}

resource "azuredevops_project" "this" {
  name               = "Example Project"
  visibility         = "private"
  version_control    = "Git"
  work_item_template = "Agile"
  description        = "Managed by Terraform"
}

resource "azuredevops_serviceendpoint_azurerm" "this" {
  project_id                             = azuredevops_project.this.id
  service_endpoint_name                  = "service-connection-name"
  description                            = "Managed by Terraform"
  service_endpoint_authentication_scheme = "WorkloadIdentityFederation"
  credentials {
    serviceprincipalid = azuread_application_registration.this.client_id
  }
  azurerm_spn_tenantid      = "00000000-0000-0000-0000-000000000000"
  azurerm_subscription_id   = "00000000-0000-0000-0000-000000000000"
  azurerm_subscription_name = "Example Subscription Name"
}

resource "azuread_application_federated_identity_credential" "this" {
  application_id = azuread_application_registration.this.id
  display_name   = "example-federated-credential"
  description    = "managed by terraform"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = azuredevops_serviceendpoint_azurerm.this.workload_identity_federation_issuer
  subject        = azuredevops_serviceendpoint_azurerm.this.workload_identity_federation_subject
}
```

#### Using managed identity

```terraform
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.83.0"
    }
    azuredevops = {
      source = "microsoft/azuredevops"
      version = "=0.10.0"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "this" {
  name     = "example-rg"
  location = "West Europe"
}

resource "azurerm_user_assigned_identity" "this" {
  location            = azurerm_resource_group.this.location
  name                = "example-identity"
  resource_group_name = "azurerm_resource_group.this.name"
}

resource "azuredevops_project" "this" {
  name               = "Example Project"
  visibility         = "private"
  version_control    = "Git"
  work_item_template = "Agile"
  description        = "Managed by Terraform"
}

resource "azuredevops_serviceendpoint_azurerm" "this" {
  project_id                             = azuredevops_project.this.id
  service_endpoint_name                  = "service-connection-name"
  description                            = "Managed by Terraform"
  service_endpoint_authentication_scheme = "WorkloadIdentityFederation"
  credentials {
    serviceprincipalid = azurerm_user_assigned_identity.this.client_id
  }
  azurerm_spn_tenantid      = "00000000-0000-0000-0000-000000000000"
  azurerm_subscription_id   = "00000000-0000-0000-0000-000000000000"
  azurerm_subscription_name = "Example Subscription Name"
}

resource "azurerm_federated_identity_credential" "this" {
  name                = "example-federated-credential"
  resource_group_name = azurerm_resource_group.this.name
  parent_id           = azurerm_user_assigned_identity.example.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azuredevops_serviceendpoint_azurerm.this.workload_identity_federation_issuer
  subject             = azuredevops_serviceendpoint_azurerm.this.workload_identity_federation_subject
}
```

### Exisiting connections

Many of you likely have numerous service connections configured within your projects. You may be wondering about the effort involved in transitioning to passwordless connections. The team behind this feature's implementation has done an incredible job, enabling a seamless "one-click" migration of your existing service connections to federated credentials. This even includes a rollback option in case of any post-switch errors. It's truly remarkable!

#### Convert

![convert connection](/assets/posts/2023-12-05-Passwordless-Authentication-for-GitHub-Actions-and-Azure-DevOps/convert.gif)

#### Revert changes

![rollback connection](/assets/posts/2023-12-05-Passwordless-Authentication-for-GitHub-Actions-and-Azure-DevOps/revert.gif)

### How to use it with Terraform
#### CLI

If you're not using the Terraform task from the marketplace, you'll need to make some modifications to your pipelines to utilize the new variables. You can set variables globally or within each step, but ensure you expose the token variable `idToken` and set its value as `ARM_OIDC_TOKEN` value. Additionally, set the `ARM_USE_OIDC` variable to `true` and avoid setting variables like `ARM_CLIENT_SECRET`, because it will conflict with OIDC.

{% raw %}
```yaml
- task: AzureCLI@2
  name: set_variables
  displayName: set terraform credentials
  inputs:
    azureSubscription: '${{ parameters.azureSubscription }}'
    addSpnToEnvironment: true
    scriptType: pscore
    scriptLocation: inlineScript
    inlineScript: |
      Write-Host "##vso[task.setvariable variable=ARM_USE_OIDC]true"
      Write-Host "##vso[task.setvariable variable=ARM_OIDC_TOKEN]$env:idToken"
      Write-Host "##vso[task.setvariable variable=ARM_CLIENT_ID]$env:servicePrincipalId"
      Write-Host "##vso[task.setvariable variable=ARM_SUBSCRIPTION_ID]$(az account show --query id -o tsv)"
      Write-Host "##vso[task.setvariable variable=ARM_TENANT_ID]$env:tenantId"

      Write-Host "##vso[task.setvariable variable=ARM_USE_AZUREAD]true"
```
{% endraw %}

#### Terraform Task
If you're using the Terraform task, ensure you're using the latest version, `TerraformTaskV4@4`. This task has been updated to support Azure DevOps workload identity, eliminating the need for additional variable configuration.

{% raw %}
```yaml
- task: TerraformTaskV4@4
  displayName: Terraform Init
  inputs:
    provider: 'azurerm'
    command: 'init'
    workingDirectory: '$(workingDirectory)'
    backendServiceArm: '${{ variables.serviceConnection }}'
    backendAzureRmResourceGroupName: 'rg-with-storage-account'
    backendAzureRmStorageAccountName: 'storagename'
    backendAzureRmContainerName: 'containername'
    backendAzureRmKey: 'terraform.tfstate'
  env:
    ARM_USE_AZUREAD: true 

- task: TerraformTaskV4@4
  displayName: Terraform Apply
  inputs:
    provider: 'azurerm'
    command: 'apply'
    workingDirectory: '$(workingDirectory)'
    commandOptions: '-auto-approve'
    environmentServiceNameAzureRM: '${{ variables.serviceConnection }}'
  env:
    ARM_USE_AZUREAD: true
```
{% endraw %}

## GitHub Actions

OpenID Connect (OIDC) integration has been available for GitHub Actions for some time, offering a simplified configuration process on the Azure side. A ready-to-use template is provided for configuring credentials to federate a GitHub repository. This allows you to easily integrate your GitHub Actions workflows with Azure resources without the hassle of manually managing credentials.

### Service principal

#### Manual configuration

1. **Create a Managed Identity / App Registration:** Create new Managed Identity in a resource group or create a new app registration in Azure Entra ID. 

2. **Configure Federation:** Click Add Credential
![Create managed identity](/assets/posts/2023-12-05-Passwordless-Authentication-for-GitHub-Actions-and-Azure-DevOps/managed-identity-federated-credentials.gif)
*Managed&nbsp;identity*<br><br>
![Create managed identity](/assets/posts/2023-12-05-Passwordless-Authentication-for-GitHub-Actions-and-Azure-DevOps/app-registration-federated-credentials.gif)
*App registration*

3. **Configure Federation:** Select Github Actions deploying Azure resources
![federated scenario](/assets/posts/2023-12-05-Passwordless-Authentication-for-GitHub-Actions-and-Azure-DevOps/github-federation.gif)

3. **Configure Federation:** Enter mandatory fields
- **Organization/Account Name**: Specify the name of the GitHub organization or personal account that owns the repository you want to federate.
- **Repository Name**: Identify the repository you want to federate. Remember that federation is configured per repository, so you may encounter the 20-credential limit when using multiple repositories.
- **Entity:** This parameter determines which entity within the repository will have the permissions to obtain an Azure token. You can choose from GitHub Environment, Branch, Pull Request, or Tag, providing flexibility in securing your permissions.
![github federation settings](/assets/posts/2023-12-05-Passwordless-Authentication-for-GitHub-Actions-and-Azure-DevOps/github-federation-settings.gif)

#### Terraform configuration

This section outlines the Terraform configuration for passwordless authentication. After creating 

##### Managed identity

```terraform
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.83.0"
    }
    github = {
      source  = "integrations/github"
      version = "=5.42.0"
    }
  }
}

data "github_repository" "repo" {
  full_name = "my-org/repo"
}

data "azurerm_subscription" "current" {
}

resource "azurerm_user_assigned_identity" "this" {
  location            = azurerm_resource_group.this.location
  name                = "example-identity"
  resource_group_name = "azurerm_resource_group.this.name"
}

resource "azurerm_federated_identity_credential" "this" {
  name                = "example-federated-credential"
  resource_group_name = azurerm_resource_group.example.name
  parent_id           = azurerm_user_assigned_identity.this.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = "https://token.actions.githubusercontent.com"
  subject             = "repo:my-organization/my-repo:environment:production"
}

resource "github_repository_environment" "production" {
  repository       = data.github_repository.repo.name
  environment      = "production"
}

resource "github_actions_environment_variable" "azure_client_id" {
  repository       = data.github_repository.repo.name
  environment      = github_repository_environment.production.environment
  variable_name    = "AZURE_CLIENT_ID"
  value            = azurerm_user_assigned_identity.this.client_id
}

resource "github_actions_environment_variable" "azure_tenant_id" {
  repository       = data.github_repository.repo.name
  environment      = github_repository_environment.production.environment
  variable_name    = "AZURE_TENANT_ID"
  value            = azurerm_user_assigned_identity.this.tenant_id
}

resource "github_actions_environment_variable" "azure_subscription_id" {
  repository       = data.github_repository.repo.name
  environment      = github_repository_environment.production.environment
  variable_name    = "AZURE_SUBSCRIPTION_ID"
  value            = azurerm_subscription.current.id
}
```

##### App registration

```terraform
terraform {
  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "=2.46.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.83.0"
    }
    github = {
      source  = "integrations/github"
      version = "=5.42.0"
    }
  }
}

data "github_repository" "repo" {
  full_name = "my-org/repo"
}

data "azurerm_subscription" "current" {
}

resource "azuread_application_registration" "this" {
  display_name = "example"
}

resource "azuread_application_federated_identity_credential" "this" {
  application_id = azuread_application_registration.this.id
  display_name   = "example-federated-credential"
  description    = "managed by terraform"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:my-organization/my-repo:environment:prod"
}

resource "github_repository_environment" "production" {
  repository       = data.github_repository.repo.name
  environment      = "production"
}

resource "github_actions_environment_variable" "azure_client_id" {
  repository       = data.github_repository.repo.name
  environment      = github_repository_environment.production.environment
  variable_name    = "AZURE_CLIENT_ID"
  value            = azuread_application_registration.this.client_id
}

resource "github_actions_environment_variable" "azure_tenant_id" {
  repository       = data.github_repository.repo.name
  environment      = github_repository_environment.production.environment
  variable_name    = "AZURE_TENANT_ID"
  value            = azurerm_subscription.current.tenant_id
}

resource "github_actions_environment_variable" "azure_subscription_id" {
  repository       = data.github_repository.repo.name
  environment      = github_repository_environment.production.environment
  variable_name    = "AZURE_SUBSCRIPTION_ID"
  value            = azurerm_subscription.current.id
}
```

### GitHub Actions workflow

Once you've configured the app registration or managed identity with federated credentials on the Azure side, the next step is to set up the federation on the GitHub repository side. This involves defining the necessary permissions and adding a login step to your GitHub Actions workflow.

In your workflow's permissions section, include the following:

```yaml
permissions:
  id-token: write
  contents: read
```
The `id-token` permission is set to `none` by default, but it needs to be set to `write` to allow the workflow to obtain an OIDC token. Additionally, the `contents: read` permission is required to checkout the repository. While `read` is the default value for `contents` permissions, specifying any permission scopes will set all unspecified scopes to none. For more detailed information on workflow permissions, refer to the official documentation: [https://docs.github.com/en/actions/using-jobs/assigning-permissions-to-jobs](https://docs.github.com/en/actions/using-jobs/assigning-permissions-to-jobs)

After defining the permissions, add a login step to your workflow or modify existing one.
{% raw %}
```yaml
- name: 'Azure login'
  uses: azure/login@v1.5.0
  with:
    client-id: ${{ vars.AZURE_CLIENT_ID }}
    tenant-id: ${{ vars.AZURE_TENANT_ID }}
    subscription-id: ${{ vars.AZURE_SUBSCRIPTION_ID }}         
```
{% endraw %}

This step will perform authentication with Azure and establish credentials that can be utilized in subsequent steps. In the absence of a provided secret, the step will attempt to authenticate without a password using the federation configured on the app/identity with the specified `client-id`. The `subscription-id` parameter identifies the subscription you want to authenticate to in case the service principal is associated with multiple subscriptions. This step essentially replicates the command sequence `az login` followed by `az account set --subscription "subscription-id"` in your command line.

Deploying your application to Azure Web App, Storage Account, connecting to Key Vault etc. now eliminates the need to provide credentials or a publish profile like the one shown below. Simply ensure your principal has the necessary permissions to connect to and deploy the package

{% raw %}
```yaml
- name: 'Azure login'
  uses: azure/login@v1.5.0
  with:
    client-id: ${{ vars.AZURE_CLIENT_ID }}
    tenant-id: ${{ vars.AZURE_TENANT_ID }}
    subscription-id: ${{ vars.AZURE_SUBSCRIPTION_ID }}       
    
- name: Deploy to Azure Web App
  uses: azure/webapps-deploy@v2
  with:
    app-name: 'web-app-name'
    package: .  
```
{% endraw %}

### How to use it with Terraform

Leveraging the passwordless login capability to execute Terraform templates requires only adding the previously mentioned workflow permissions to expose the token. The AzureRM provider will automatically detect variables set by the GitHub runtime, making it necessary to set only `ARM_USE_OIDC` to `true` along with `ARM_CLIENT_ID`, `ARM_SUBSCRIPTION_ID`, and `ARM_TENANT_ID` to inform Terraform about the principal and subscription to be used. These values can be stored in repository secrets or variables, preferably in environment scope for ease of reuse. Alternatively, they can be provided directly within the workflow.

To set these values in a single step, resulting in their export to `GITHUB_ENV` and availability for subsequent steps, use the following code:

{% raw %}
```yaml
- name: set-variables
  shell: 'pwsh'
  run: |
    @("ARM_CLIENT_ID=${{ vars.AZURE_CLIENT_ID }}",
      "ARM_SUBSCRIPTION_ID=${{ vars.AZURE_SUBSCRIPTION_ID }} ",
      "ARM_TENANT_ID=${{ vars.AZURE_TENANT_ID }}",
      "ARM_USE_OIDC=true",
      "ARM_USE_AZUREAD=true") | Out-File -FilePath $env:GITHUB_ENV -Append

- name: Terraform-init
  shell: 'pwsh'
  run: |
    terraform init ...

- name: Terraform-plan
  shell: 'pwsh'
  run: |
    terraform plan ...
```
{% endraw %}

Alternatively, you can set these values directly within each step that requires them, as shown in the following example:

{% raw %}
```yaml
- name: Terraform-init
  shell: 'pwsh'
  env:
    ARM_CLIENT_ID: ${{ vars.AZURE_CLIENT_ID }}
    ARM_SUBSCRIPTION_ID: ${{ vars.AZURE_SUBSCRIPTION_ID }}
    ARM_TENANT_ID: ${{ vars.AZURE_TENANT_ID }}
    ARM_USE_OIDC: true
    ARM_USE_AZUREAD: true
  run: |
    terraform init ...

- name: Terraform-plan
  shell: 'pwsh'
  env:
    ARM_CLIENT_ID: ${{ vars.azureClientId }}
    ARM_SUBSCRIPTION_ID: ${{ vars.azureSubscriptionId }}
    ARM_TENANT_ID: ${{ vars.azureTenantId }}
    ARM_USE_OIDC: true
    ARM_USE_AZUREAD: true
  run: |
    terraform plan ...
```
{% endraw %}

While this approach provides more granular control over the environment variables, it can make the workflow less readable and maintainable. It's generally recommended to define environment variables in a single step and export them to `GITHUB_ENV` for easier access throughout the workflow.

## Passwordless connection to `azurerm` backend

In both scenarios you can easily spot `ARM_USE_AZUREAD` variable set to `true`. This is recommended way to connect to AzureRM backend (if you use one). Without this parameter, you will be using your passwordless identity to retrieve storage access key and connect with it to state file, but with that option you can set your identity `Storage blob data contributor` role on storage account with state file and completly disable local authentication (Access Keys) on storage account to leverage fully passwordless experience!

![disable storage access keys](/assets/posts/2023-12-05-Passwordless-Authentication-for-GitHub-Actions-and-Azure-DevOps/disable-storage-key.gif)

# Conclusion

Workload identity has revolutionized the way we authenticate with Azure resources, eliminating the need for managing credentials and enhancing overall security. By leveraging workload identity in Azure DevOps and GitHub Actions, you can streamline your deployments and CI/CD pipelines while maintaining robust security measures.
