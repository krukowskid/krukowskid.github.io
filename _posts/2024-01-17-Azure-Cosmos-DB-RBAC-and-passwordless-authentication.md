---
excerpt: "This guide offers a step-by-step walkthrough on enhancing Azure Cosmos DB for NoSQL with RBAC and passwordless authentication. It covers the benefits of managed identity, explores permission management levels, and provides instructions on creating and assigning custom roles with Terraform. Additionally, it explains how to disable access tokens and access data using Entra ID. This content is suitable for technical audiences aiming to improve security and efficiency in their Azure Cosmos DB operations."

title: "Azure Cosmos DB RBAC and passwordless authentication"

image: /assets/posts/2024-01-17-Azure-Cosmos-DB-RBAC-and-passwordless-authentication/header.webp

date: 2024-01-17

categories:
  - Blog

tags:
  - Terraform
  - Azure
  - Security
  - Managed Identity
  - CosmosDb

---

* toc
{:toc .large only} 

# Introduction

I know you've been rocking the managed identity approach for your CI/CD pipelines, storage accounts, and maybe even SQL servers. But when it comes to Azure Cosmos DB for NoSQL, transitioning away from access keys might seem a tad tricky. Don't worry, I'm here to guide you through this process like we're chatting over coffee.

Azure Cosmos DB for NoSQL does utilize its own RBAC mechanism on the data plane. However, it lacks a graphical interface for managing permissions. While this might feel a bit strange at first, it's not a big deal. By using Terraform, we'll be able to easily enable passwordless connections in Cosmos DB.

# The Advantages of using RBAC and Entra ID identities

If the following points resonate with you, then switching to RBAC and passwordless authentication for your database connections is definitely the right move:
- You prefer a token-based authentication mechanism over a shared secret, like the primary key.
- You want to use Microsoft Entra identities to authenticate your requests.
- You need a finely-tuned permission model to strictly limit the database operations your identities can perform.
- You want to define your access control policies as "roles" that can be assigned to multiple identities.

# Understanding Access Control Types in Cosmos DB for NoSQL

Cosmos DB supports three permission management levels - account, resource, and data. All of them can be managed with Entra ID identity. However, with access keys and resource tokens, you can only access resources and data, which can be further limited to data only by setting `disableKeyBasedMetadataWriteAccess` in ARM/Bicep to `true` or `access_key_metadata_writes_enabled` to `false` in Terraform. Access keys can also be entirely disabled, as explained in the [Disabling Access Tokens](#disabling-access-tokens) section.

## Account Management

Account management operations are exclusively handled by Entra ID identities (Accounts and principals). These operations include:
- Replication settings,
- Regenerating/obtaining access keys,
- Configuring networking,
- Setting up account consistency level.

Essentially, these operations pertain to Azure resources that can be managed through the Azure Resource Manager.

## Resource management

Resource management can be handled by both Entra ID identities and keys/resource tokens. These operations include:  
- Creating databases within an account,
- Creating containers within databases,
- Setting container/database RU capacity,
- Updating indexing policies,
- Creating users and assigning permissions.

## Data operations

Data operations can be managed by keys/resource tokens and Entra ID identities, but only in CosmosDB for NoSQL. At the moment, other APIs don't support Entra identities for data plane operations.

Data operations include:
- Running queries,
- Performing CRUD operations,
- Managing and running stored procedures and triggers.

# Cosmos DB for NoSQL role-based access control (RBAC)

At the control plane (account and resource level), you're managing Azure resources and everything manageable by the Azure Resource Manager. Hence, in the context of Cosmos, you can control who can create accounts, databases, list access keys, etc., and on the data plane, you can control who can read the data within a container or update a document. Unfortunately, the Azure IAM feature available within the Azure portal doesn't allow you to set data plane-level permissions.

| Type | Actions | Entra ID identity support | Keys and resource tokens support |
|---|---|---|---|
| Account Management | • Control global replication<br />• Setup virtual network integration, firewall and cores <br />• Regenerate master keys<br />• Access to monitoring and metric<br />• Set account consistency | ✅ | ❌ |
| Resource management | • Create databases and containers<br />• Update indexing policies<br />• Set containers` throughput (RUs) | ✅ | ✅ |
| Data operations | • Perform CRUD operations<br />• Run queries<br />• Manage and run stored procedures, UDF and triggers | ✅* | ✅ |

**Only in Cosmos DB for NoSQL*

You might be wondering how to grant access. Typically, access is granted using the 'DocumentDB Account Contributor' or 'Cosmos DB Account Reader' roles. This method, however, only grants access to access keys. If someone steals the key, it can be exploited until it's rotated. On the bright side, you can completely disable access keys and implement a more secure approach.

## Roles

Cosmos DB for NoSQL includes two preconfigured roles - reader and contributor, which will cover most common scenarios.

| ID | Name | Included actions |
|---|---|---|
| 00000000-0000-0000-0000-000000000001 | Cosmos DB Built-in Data Reader | `Microsoft.DocumentDB/databaseAccounts/readMetadata`<br />`Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/items/read`<br />`Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/executeQuery`<br />`Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/readChangeFeed` |
| 00000000-0000-0000-0000-000000000002 | Cosmos DB Built-in Data Contributor | `Microsoft.DocumentDB/databaseAccounts/readMetadata`<br />`Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/*`<br />`Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/items/*` |

You can also create custom roles from the available actions to better suit your needs and follow the least privilege principle. However, when using RBAC with identities, we are unable to limit operations to certain partition keys.

Available actions: 

| Name | Corresponding database operation(s) |
|---|---|
| `Microsoft.DocumentDB/databaseAccounts/readMetadata` | Read account metadata. |
| `Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/items/create` | Create a new item. |
| `Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/items/read` | Read an individual item by its ID and partition key (point-read). |
| `Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/items/replace` | Replace an existing item. |
| `Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/items/upsert` | "Upsert" an item. This operation creates an item if it doesn't already exist, or to replace the item if it does exist. |
| `Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/items/delete` | Delete an item. |
| `Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/executeQuery` | Execute a SQL query. |
| `Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/readChangeFeed` | Read from the container's change feed. Execute SQL queries using the SDKs. |
| `Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/executeStoredProcedure` | Execute a stored procedure. |
| `Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/manageConflicts` | Manage conflicts for multi-write region accounts (list and delete items from the conflict feed). |

*source: https://learn.microsoft.com/en-us/azure/cosmos-db/how-to-setup-rbac*

### Creating a Custom Role Definition with Terraform  

```terraform
resource "azurerm_cosmosdb_sql_role_definition" "this" {
  name                = "CustomReaderRole"
  resource_group_name = azurerm_resource_group.this.name
  account_name        = azurerm_cosmosdb_account.this.name
  type                = "CustomRole"
  assignable_scopes   = [azurerm_cosmosdb_account.this.id]

  permissions {
    data_actions = ["Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/items/read",
                    "Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/executeQuery",
                    "Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/readChangeFeed",
                    "Microsoft.DocumentDB/databaseAccounts/readMetadata"]
  }
}
```

`Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/executeQuery` and `Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/readChangeFeed` are added along with `items/read` because those two are required when executing queries through the SDKs. The `Microsoft.DocumentDB/databaseAccounts/readMetadata` action is recommended but not required. It allows read metadata and child-objects limited to assigned scope

Wildcards can also be used on containers and items levels when creating roles:    
- ``Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/*``
- ``Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/items/*``

The ``assignable_scopes`` controls where the role can be assigned. For example, you can use this syntax ``"${azurerm_cosmosdb_account.example.id}/dbs/databasename"`` to limit the assignable scope to a single database within the CosmosDb account. Allowed scopes are `Account`, `Database`, and `Container`.

## Assignments

RBAC roles, unlike resource tokens permissions, are reusable. This means that you need to create the role once for the CosmosDb account, and then you can assign it to multiple users at the Account, Database, or Container level.

### Assigning a Role Definition with Terraform

```terraform
resource "azurerm_cosmosdb_sql_role_assignment" "this" {
  resource_group_name = azurerm_resource_group.this.name
  account_name        = azurerm_cosmosdb_account.this.name
  role_definition_id  = azurerm_cosmosdb_sql_role_definition.this.id
  principal_id        = data.azurerm_client_config.current.object_id
  scope               = azurerm_cosmosdb_account.this.id
}
```

The assigned scope is applicable to all child objects. So, if you assign permissions at the database level, it will be applicable to all containers within that database. Similarly, if you assign it at the account level, it will be applicable to all databases and containers.

# Disabling Access Tokens

Once you've transitioned from connection strings in your application and moved all users to RBAC permissions from access keys, it's time to entirely disable access keys!

nfortunately, options here are somewhat limited. You can't disable access keys from the Azure Portal. The only options are - Azure Resource Manager, Bicep, Azure Policy, Terraform or the `az resource update` command in the az cli.

## Azure Resource Manager

Set ``"disableLocalAuth": true`` under properties when creating or updating Cosmos DB account.

```json
"resources": [
    {
        "type": "Microsoft.DocumentDB/databaseAccounts",
        "properties": {
            "disableLocalAuth": true,
            // ...
        },
        // ...
    },
    // ...
 ]
```

## Bicep

Set `disableLocalAuth: true` under properties when creating or updating Cosmos DB account.

```terraform
 resource symbolicName 'Microsoft.DocumentDB/databaseAccounts@2023-04-15' = {
  // ...
  kind: 'GlobalDocumentDB'
  properties: {
    // ...
    disableLocalAuth: true
    // ...
  }
}
```

## Terraform

Set ``local_authentication_disabled`` to `true` in ``azurerm_cosmosdb_account`` resource definition.

```terraform
resource "azurerm_cosmosdb_account" "this" {
  name                = "cosmosdbaccount"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  local_authentication_disabled = true
}
```

## Azure CLI

Unfortunately this cannot be done using `az cosmosdb` command.

```powershell
$cosmosdb = az cosmosdb show  --name "<cosmos-db-account-name>" `
                              --resource-group "<resource-group-name>" `
                                | ConvertFrom-Json

az resource update  --ids $cosmosdb.id `
                    --set properties.disableLocalAuth=true ` 
                    --latest-include-preview
```

## Azure Policy

There is a [built-in Azure Policy named "Configure Cosmos DB database accounts to disable local authentication"](https://portal.azure.com/#view/Microsoft_Azure_Policy/PolicyDetailBlade/definitionId/%2Fproviders%2FMicrosoft.Authorization%2FpolicyDefinitions%2Fdc2d41d1-4ab1-4666-a3e1-3d51c43e0049). It might be helpful to ensure compliance at scale and simplify management if you are not using Bicep or Terraform.

# Accessing your Data with Entra ID

Transitioning to a passwordless connection simplifies local development. However, when it comes to accessing data through means other than SDKs, there are a few additional considerations to keep in mind.

## API

When constructing the REST API authorization header, set the type parameter to Microsoft Entra ID and the hash signature (sig) to the OAuth token as shown in the following example:

`type=aad&ver=1.0&sig=<token-from-oauth>`

## Data Explorer

The data explorer in the Azure portal does not yet support Azure Cosmos DB role-based access control. So, you still will be able to see databases and containers in the explorer. However, to use your Microsoft Entra identity to access your data, you need to use the standalone data explorer portal: [https://cosmos.azure.com/](https://cosmos.azure.com/)

There's a caveat. You need to explicitly add `?feature.enableAadDataPlane=true` query parameter to the URL -> [https://cosmos.azure.com?feature.enableAadDataPlane=true](https://cosmos.azure.com?feature.enableAadDataPlane=true) 
   
With this query parameter, the following logic is used:  
   
1. A request to fetch the account's primary key is attempted on behalf of the identity signed in.
2. If this request succeeds, the primary key is used to access the account's data. 
3. If the identity signed in isn't allowed to fetch the account's primary key, this identity is directly used to authenticate data access. In this mode, the identity must be assigned with proper role definitions to ensure data access.

# Working Terraform Example

```terraform
resource "azurerm_cosmosdb_account" "this" {
  name                = "cosmosdbaccount"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  consistency_policy {
    consistency_level = "Strong"
  }

  geo_location {
    location          = azurerm_resource_group.this.location
    failover_priority = 0
  }
}

resource "azurerm_cosmosdb_sql_role_assignment" "built_in_reader" {
  resource_group_name = azurerm_resource_group.this.name
  account_name        = azurerm_cosmosdb_account.this.name
  role_definition_id  = "00000000-0000-0000-0000-000000000001" // built-in reader role
  principal_id        = data.azurerm_client_config.current.object_id
  scope               = azurerm_cosmosdb_account.this.id // account scope
}

resource "azurerm_cosmosdb_sql_role_definition" "custom_reader" {
  name                = "customreader"
  resource_group_name = azurerm_resource_group.this.name
  account_name        = azurerm_cosmosdb_account.this.name
  type                = "CustomRole"
  assignable_scopes   = [azurerm_cosmosdb_account.this.id]

  permissions {
    data_actions = ["Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/items/read"]
  }
}

resource "azurerm_cosmosdb_sql_role_assignment" "custom_reader" {
  resource_group_name = azurerm_resource_group.this.name
  account_name        = azurerm_cosmosdb_account.this.name
  role_definition_id  = azurerm_cosmosdb_sql_role_definition.custom_reader.id
  principal_id        = data.azurerm_client_config.current.object_id
  scope               = azurerm_cosmosdb_account.this.id // account scope
}
```

# Conclusion

Transitioning to RBAC and passwordless authentication in Azure Cosmos DB for NoSQL may seem complex at first, but with the right approach, it becomes a manageable task. Remember, the goal is to move away from shared secrets and towards token-based authentication mechanisms that provide fine-grained control over permissions. While the journey involves several steps, from understanding the different permission management levels to creating and assigning custom roles with Terraform, it's well worth the effort. By disabling access tokens, you're making your database more secure against potential threats.

With this guide, I hope you're now equipped with the knowledge to make your Azure Cosmos DB more secure and efficient. As always, if you run into any issues or have any questions, don't hesitate to reach out.
