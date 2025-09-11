---
excerpt: "Deploying Azure Private Endpoints with Terraform? DNS propagation lags can break your automation. Here's a cross-platform way to wait for DNS before moving on."
title: Handling DNS Propagation Delays in Terraform

image: /assets/posts/2025-09-10-Handling-DNS-Propagation-Delays-in-Terraform/header.webp

date: 2025-09-10

categories:
  - Blog

tags:
  - Terraform
  - Azure

related_posts:
  - _posts/2025-04-24-Solving-the-Terraform-Backend-Chicken-and-Egg-Problem.md
---

* toc
{:toc .large only} 

Azure Private Endpoints have a sneaky timing problem in Terraform. The endpoint might exist, the DNS zone appears updated, and Terraform thinks everything is done and moves on as soon as the resource exists - but your system may still resolve the old address or not resolve it at all! That tiny DNS propagation delay can silently break automation.

For example, when I deployed an Azure Key Vault with public access disabled, Terraform immediately tried to create a secret (`azurerm_key_vault_secret`) inside it, still resolving to the public address, so the request landed on the wrong endpoint and failed with a 403 Forbidden.

![Terraform fails due to DNS lag](/assets/posts/2025-09-10-Handling-DNS-Propagation-Delays-in-Terraform/dns-fail.gif)

Sure, re-running the apply command or pipeline worked... but that was just duct tape. I wanted something smarter. My search led me deep into the wilderness of AzureRM provider internals and local-exec provisioners - which, surprise surprise, turned out to be just a fancier kind of duct tape that suited my needs.

# Alternatives

Before I went all in on provisioners, I tested a couple of "cleaner" options.

## time_sleep

There is a time provider that lets you wait between steps.

```hcl
resource "time_sleep" "wait_for_dns" {
  create_duration = "120s"
}

resource "azurerm_key_vault_secret" "this" {
  name         = "example-secret"
  value        = "example-value"
  key_vault_id = azurerm_key_vault.this.id

  depends_on = [time_sleep.wait_for_dns]
}
```

This works if you always know how long DNS will take. The problem is... you don't. Sometimes it is 20 seconds, sometimes 3 minutes. Hardcoding timeouts felt flaky and slow, because you are always waiting for the maximum time.

## AzAPI with retry

You can also use the AzAPI provider, which has a configurable retry mechanism. You can configure it to retry on error messages related to public access being disabled. Unfortunately, this requires more effort to figure out the correct resource type and provider resource to test if the data plane can be accessed via private access and to retry on errors. 

During my testing it took a lot of effort even for a single resource, so it is not a generic approach. Still, it is probably the cleanest one, because you are using the native Terraform provider with the Azure API and I advise you to try this before going for other solutions.

### AzApi and Key Vault Secrets

There is a caveat with Key Vault, which Microsoft is aware of and considers fine: you can actually create or update a secret through the management plane, bypassing firewall rules and data-plane RBAC. So anyone with roles like Owner or Contributor can update a secret from the public internet, even on a Key Vault with public access disabled. Imagine someone changing the connection string for your application, redirecting user data to a remote database.

So, in order to create a secret in a public-disabled Key Vault, you only need this and this way you don't need to wait for private endpoint DNS to propagate... 🥺

```hcl
resource "azapi_resource" "create_secret" {
  type      = "Microsoft.KeyVault/vaults/secrets@2023-02-01"
  name      = "example-secret"
  parent_id = azurerm_key_vault.this.id
  body = {
    properties = {
      value = "example-value"
    }
  }
}
```

## Pipeline retry

Another trick is to catch error and retry the failing step in your CI/CD pipeline (Azure DevOps, GitHub Actions, etc). That is easy to do, but spreads the logic outside Terraform. I did not like the idea of having half the workaround in Terraform and half in the pipeline.

## Provider

You could also solve this with a custom Terraform provider which will be the cleanest and the most generic, cross-platform approach. A provider could natively handle DNS resolution in Golang, retry until the record points to the expected IP, and expose it as just another Terraform dependency. The trade-off is effort vs. payoff. 

For my use case, a self-contained module was the pragmatic sweet spot. But if you're building something reusable for your org or the community, a provider might be worth the investment. This provider might be a good starting point: [bendrucker/dns-validation](https://registry.terraform.io/providers/bendrucker/dns-validation/latest/docs)

# Design goals

Provisioners are often considered a "last resort" - they are imperative, fragile, and not really "Terraform." And all of that is true. Everything depends on how good your script is and how your system handles it, unlike with providers.

For example, this solution will fail on MacOS as there I didn't implement support for it and `getent` which is Linux command will probably fail.

Before writing scripts, I set some constraints to avoid common problems with local-exec provisioners:

- Must run on both Linux and Windows build agents/laptops.
- Reusable - should be a Terraform module, not copy-paste snippets.
- No extra dependencies - should work with commands already available in CI/CD environments regardless of distro and PowerShell version...
- Works everywhere - Azure, AWS, on-premises, etc.

# Solution

The idea is simple: wrap everything in a null_resource that runs a script, confirm that DNS resolves to the Private Endpoint IP, and only then let Terraform continue.

```hcl
resource "null_resource" "this" {
  triggers = var.triggers
  provisioner "local-exec" {
    interpreter = local.is_linux ? [] : ["PowerShell", "-Command", ""]
    command     = local.is_linux ? replace(local.linux_command, "\r\n", "\n") : local.windows_command
  }
}
``` 
- triggers are evaluated each apply to rerun the `null_resource` when inputs change
- The interpreter switches between Linux (plain shell), which is default behaviour so the array is empty and Windows (PowerShell).
- By isolating this in one place instead of using local-exec directly in azurerm resources, I could wrap it into a Terraform module that anyone can use.

## Detecting the OS

The first problem: Terraform does not expose the operating system directly. But there is a neat trick:

On Linux, paths look like /home/runner/...
On Windows, paths start with a drive letter like C:/...

So you can check if the root path starts with a drive letter. If it does not, you are on Linux:

```hcl
locals {
  is_linux = length(regexall("^[a-zA-Z]:", abspath(path.root))) == 0
}
```

This boolean decides which script to run.

## Linux logic

On Linux, I used `getent` because it's pretty universal across multiple distros. The script basically says:

- Resolve the hostname.
- If it matches the expected IP, confirm it multiple times in a row (important if you're hitting multiple DNS servers).
- If it does not match the expected IP, sleep a bit.
- Exit once it's stable or timeout is hit.

Here's the script:

```bash
linux_command = <<-EOT
  timeout_seconds=${var.timeout_seconds}
  sleep_seconds=${var.sleep_seconds}
  while [ $timeout_seconds -gt 0 ]; do
    ip=$(getent hosts "${local.dns_name}" | awk '{ print $1 }')
    timeout_seconds=$((timeout_seconds - sleep_seconds))
    if [ "$ip" = "${var.ip_address}" ]; then
      for attempt in $(seq 1 ${var.successful_attempts}); do
        ip=$(getent hosts "${local.dns_name}" | awk '{ print $1 }')
        if [ "$ip" != "${var.ip_address}" ]; then
          break
        fi
        if [ $attempt -eq ${var.successful_attempts} ]; then
          sleep $sleep_seconds
          exit 0
        fi
        sleep 1
      done
    fi
    sleep $sleep_seconds
  done
  exit 1
EOT
```

It's not bulletproof (with multiple DNS servers you can still hit a mix of responses), but it was good enough without installing extra tools to query each DNS server individually.

## Windows logic

On Windows, the main headache was DNS caching. By default, PowerShell will just happily resolve from cache, so you keep hitting stale results.

The trick was to use `Clear-DnsClientCache` before every lookup. Unlike `ipconfig /flushdns`, this doesn't require elevated rights.

```powershell
windows_command = <<-EOT
  $timeoutSeconds = ${var.timeout_seconds}
  $sleepSeconds = ${var.sleep_seconds}
  Do {
    Clear-DnsClientCache
    $ip = ((Resolve-DNSName -Name "${local.dns_name}" -DnsOnly) | Where-Object {$_.Type -eq "A"}).IPAddress
    [int]$timeoutSeconds = [int]$timeoutSeconds - [int]$sleepSeconds
    if ($ip -eq "${var.ip_address}") {
      for ($attempt = 1; $attempt -le ${var.successful_attempts}; $attempt++) {
        Clear-DnsClientCache
        $ip = ((Resolve-DNSName -Name "${local.dns_name}" -DnsOnly) | Where-Object {$_.Type -eq "A"}).IPAddress
        if ($ip -ne "${var.ip_address}") {
          break
        }
        if ($attempt -eq ${var.successful_attempts}) {
          Start-Sleep -Seconds $sleepSeconds
          exit 0
        }
        Start-Sleep -Seconds 1
      }
    }
    Start-Sleep -Seconds $sleepSeconds
  } Until (0 -gt $timeoutSeconds)
  exit 1
EOT
```

## Variables

To keep it flexible, I exposed the basics as variables:

- dns_name → the hostname to resolve.
- ip_address → the expected Private Endpoint IP.
- timeout_seconds → how long to wait.
- sleep_seconds → how long to wait between retries. 
- successful_attempts → how many consecutive good results before success.

That way I can tweak it per resource.

## Dealing with outputs from resources

Unfortunately when using outputs from resources, sometimes you will get a hostname, sometimes url with trailing slash and sometimes without.

To simplify usage of the module I have added additional regex to the dns name. It trims all unnecessary elements like protocols, slashes and ports, to leave only the hostname, which is required during DNS resolution, so I can pass hostname/uri without removing anything on my own.

```hcl
locals {
  dns_name = regex("^(?:https?://)?(?:[^@\\n]+@)?([^:/\\n]+)", trimspace(var.dns_name))[0]
}
```

After wrapping everything into a module, the usage looks like this

```hcl
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

data "azurerm_client_config" "current" {}

resource "random_string" "this" {
  length  = 8
  special = false
  upper   = false
}

resource "azurerm_resource_group" "this" {
  name     = "rg-demo-${random_string.this.result}"
  location = "polandcentral"
}

resource "azurerm_key_vault" "this" {
  name                          = "kv-demo-${random_string.this.result}"
  location                      = "polandcentral"
  resource_group_name           = azurerm_resource_group.this.name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  purge_protection_enabled      = false
  soft_delete_retention_days    = 7
  public_network_access_enabled = false
  rbac_authorization_enabled    = true

  network_acls {
    default_action = "Deny"
    bypass         = "None"
  }
}

resource "azurerm_private_endpoint" "this" {
  name                = "pe-demo-${random_string.this.result}"
  location            = "polandcentral"
  resource_group_name = "dns-demo-prd"

  subnet_id = var.subnet_id

  private_service_connection {
    name                           = "psc-demo-${random_string.this.result}"
    is_manual_connection           = false
    private_connection_resource_id = azurerm_key_vault.this.id
    subresource_names              = ["vault"]
  }

  private_dns_zone_group {
    name                 = "demo-dns-zone-group-${random_string.this.result}"
    private_dns_zone_ids = [var.private_dns_zone_id]
  }
}

module "wait_for_dns" {
  source = "../wait_for_dns"

  triggers = {
    ip = azurerm_private_endpoint.this.private_service_connection[0].private_ip_address
  }
  dns_name   = azurerm_key_vault.this.vault_uri
  ip_address = azurerm_private_endpoint.this.private_service_connection[0].private_ip_address
}

resource "azurerm_key_vault_secret" "this" {
  name         = "example-secret"
  value        = "example-value"
  key_vault_id = azurerm_key_vault.this.id

  depends_on = [module.wait_for_dns]
}
```

As you see I am passing `dns_name` which is the hostname to be resolved, `ip_address` which is target ip, and `triggers` which tells terraform when to trigger null_resource with provisioner again - in this case, when the IP address of the private endpoint changes.

After that, simply add `depends_on` with module reference to all depended resources

![dns success](/assets/posts/2025-09-10-Handling-DNS-Propagation-Delays-in-Terraform/dns-success.gif)

# DNS Is Not Enough

When creating a resource with a private endpoint using the AzureRM provider in Terraform, simply waiting for DNS to resolve to the private IP is not sufficient.

The AzureRM provider uses Go's default HTTP client, which caches connections in a pool keyed by the target address (domain name or IP). During resource creation, the client may initially resolve the resource FQDN to its public IP because the private endpoint is not yet ready. Later, when the provider attempts to create a secret or perform other operations, it may reuse an existing idle connection from the pool - still pointing to the public IP. This can result in 403 errors, even though DNS now correctly resolves to the private endpoint.

```powershell
PS C:\Users\piotr> Get-NetTCPConnection 

LocalAddress                        LocalPort RemoteAddress                       RemotePort State       AppliedSetting OwningProcess 
------------                        --------- -------------                       ---------- -----       -------------- -------------        
192.168.50.11                       52270     20.215.26.76                        443        Established Internet       35728         
192.168.50.11                       52269     20.215.26.76                        443        Established Internet       35728  

# 20.215.26.76 is Key Vault public address. This connection was open during Key Vault provisioning.
```

The core issue here is connection reuse, not DNS resolution. Idle connections in Go's HTTP client persist for 90 seconds by default (so if your DNS propagation takes less than 90 seconds, you will likely hit this issue) and do not automatically re-resolve the hostname. As a result, the provider continues using the old connection pointing to the public IP.

Depending on which resources and providers you are using, you may need to account for this by adjusting the module's wait time to allow Go to dispose of the old connections before proceeding, or detect if the connection still exists but there is no proper way to kill this connection.

Unfortunately, fixing this at the provider level would require a major change to the AzureRM provider. For now, updates are being implemented on a per-resource basis, as shown in this pull request: [PR #30352](https://github.com/hashicorp/terraform-provider-azurerm/pull/30352)

# Summary

Provisioners are duct tape, but sometimes duct tape is what keeps your pipeline moving. This cross-platform DNS-wait module saved me from flaky runs - and might save you too. Just don't forget to look for cleaner options before reaching for it.

Let me know if you encounter similar issues with DNS propagation delays. I'm considering making a public provider for this workflow.

You can find example code here: [terraform-example](https://github.com/krukowskid/krukowskid.github.io/tree/main/assets/posts/2025-09-10-Handling-DNS-Propagation-Delays-in-Terraform/terraform-example)