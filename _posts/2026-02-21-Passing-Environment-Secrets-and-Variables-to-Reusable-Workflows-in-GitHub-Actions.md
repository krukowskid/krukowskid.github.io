---
excerpt: "GitHub explicitly blocks environment secrets from being passed to reusable workflows - here's how to work around it while keeping your workflow truly generic."

title: Passing Environment Secrets and Variables to Reusable Workflows in GitHub Actions

image: /assets/posts/2026-02-21-Passing-Environment-Secrets-and-Variables-to-Reusable-Workflows-in-GitHub-Actions/header.webp

date: 2026-02-21

categories:
  - Blog

tags:
  - GitHub Actions
  - CICD
  - Security
  - Terraform

related_posts:
  - _posts/2025-04-24-Solving-the-Terraform-Backend-Chicken-and-Egg-Problem.md
  - _posts/2025-03-20-GitHub-Cross-Organization-Repository-Access.md
---

* toc
{:toc .large only}

# Introduction

When building reusable GitHub Actions workflows, sooner or later you'll want to use environment-specific secrets. You set up your environments in GitHub, store secrets there, and expect them to be available when the workflow runs for the correct environment. Sounds straightforward, but in reality it's not always that simple. If your reusable workflow is designed to pull a secret with the same name, then you are fine.

But what if you want to build a truly generic reusable workflow that can be called from multiple environments without hardcoding any secret names or values?

GitHub documentation:

> *"Environment secrets cannot be passed from the caller workflow as on.workflow_call does not support the environment keyword. If you include environment in the reusable workflow at the job level, the environment secret will be used, and not the secret passed from the caller workflow."*

# The Problem

The typical instinct is to configure the environment in the caller workflow, at the job level that calls the reusable workflow:

{% raw %}
```yaml
jobs:
  deploy:
    environment: dev
    uses: ./.github/workflows/reusable.yaml
    secrets: 
      TF_VAR_secret: ${{ secrets.ENVIRONMENT_SECRET }}  

```
{% endraw %}

GitHub explicitly does not support `environment` on a job that uses reusable workflow.

{% raw %}
```yaml
jobs:
  deploy:
    uses: ./.github/workflows/reusable.yaml
    inputs:
      environment: dev
    secrets: 
      TF_VAR_secret: ${{ secrets.ENVIRONMENT_SECRET }}  

```
{% endraw %}

This won't work either because even if you pass the environment name as an input, the secret will be evaluated in the caller workflow context where the environment is not set, so it won't load the environment secrets at all. {% raw %}`${{ secrets.ENVIRONMENT_SECRET }}`{% endraw %} will end-up empty or retrieved from the wrong scope (e.g. repository or organization secrets instead of environment secrets).

The environment in a reusable workflow is defined at the job level. We can pass it as an input to the reusable workflow and read environment secrets there, but we can't set it from the caller workflow.

# The Solution

Pass the environment name as a workflow input and set the `environment` at the job level **inside the reusable workflow** and use `secrets: inherit` tp allow secrets from the caller workflow to be passed through to the reusable workflow. By default only secrets explicitly passed in the `secrets` section are available in the reusable workflow, `secrets: inherit` allows all secrets from the caller to be available in the reusable workflow, including environment secrets once the environment is set at the job level.


{% raw %}
```yaml
# caller-workflow.yaml
jobs:
  deploy-dev:
    uses: ./.github/workflows/reusable-workflow.yaml
    secrets: inherit
    with:
      environment: dev
```
{% endraw %}

{% raw %}
```yaml
# reusable-workflow.yaml
on:
  workflow_call:
    inputs:
      environment:
        description: 'Environment name'
        required: true
        type: string

env:
  SUPER_SECRET: ${{ secrets.environment_secret }}
# This will work because the environment is set at the job level, so secrets from that environment will be available in the reusable workflow context, but you can't parameterize the secret name. To make it fully generic, you can use the pattern described later in the article.

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: ${{ inputs.environment }}  
    steps:
      - run: echo "Running for ${{ inputs.environment }}"
```
{% endraw %}

With this setup, the reusable workflow job runs with the `dev` environment context and all secrets defined for that environment are available - without hardcoding any environment name in the reusable workflow itself. The environment secrets are available because the reusable workflow sets `environment` at the job level and `secrets: inherit` that allows secrets from the caller workflow to be passed through, including environment secrets once the environment is set.

## Handling Dynamic Secret Names

Setting the environment correctly and allowing all secrets from the caller workflow to be passed through solves the context problem, but there's a second challenge: what if you don't know the secret names ahead of time?

This comes up for example with Terraform reusable workflows where the variables needed differ between templates - `database_password`, `api_key`, etc. Terraform automatically picks these up as input variables when they exist as environment variables with the `TF_VAR_` prefix. The problem is that you don't want to reference {% raw %}`${{ secrets.TF_VAR_database_password }}`{% endraw %} in a generic reusable workflow - you'd have to save every possible secret name in reusable workflow. That's not reusable, but passing it from the caller workflow is not possible because of limitations described above.

The solution is to use GitHub script to dynamically read all secrets available in the current environment context at runtime, filter for those that start with `TF_VAR_` (or any other logic you choose), and export them as environment variables for subsequent steps. This way, any secret following the `TF_VAR_` naming convention will automatically be picked up by Terraform without hardcoding their names.

{% raw %}
```yaml
- name: Export TF_VAR secrets
  uses: actions/github-script@v8.0.0
  env:
    ALL_SECRETS: ${{ toJSON(secrets) }}
  with:
    script: |
      const secrets = JSON.parse(process.env.ALL_SECRETS);
      for (const [key, value] of Object.entries(secrets)) {
        if (key.startsWith('TF_VAR_')) {
          const exportKey = `TF_VAR_${key.slice('TF_VAR_'.length).toLowerCase()}`;
          core.exportVariable(exportKey, value);
          core.info(`Exported: ${key} as ${exportKey}`);
        }
      }
```
{% endraw %}

This script could be changed to get a list of secrets from an input to filter only specific secrets in case you are not using it for Terraform variables or want to export only a subset of secrets. 

{% raw %}
```yaml
on:
  workflow_call:
    inputs:
      secrets_to_export:
        description: 'Comma-separated list of secrets to export'
        required: false
        type: string

- name: Export secrets from inputs
  uses: actions/github-script@v8.0.0
  env:
    ALL_SECRETS: ${{ toJSON(secrets) }}
    SECRETS_TO_EXPORT: ${{ inputs.secrets_to_export }}
  with:
    script: |
      const secrets = JSON.parse(process.env.ALL_SECRETS);
      const secretsToExport = process.env.SECRETS_TO_EXPORT ? process.env.SECRETS_TO_EXPORT.split(',') : Object.keys(secrets);
      for (const key of secretsToExport) {
        if (secrets[key]) {
          core.exportVariable(key, secrets[key]);
          core.info(`Exported: ${key}`);
        } else {
          core.warning(`Secret ${key} not found in the current context`);
        }
      }
```
{% endraw %}

Let me break down what's happening here.

## Why pass secrets through `env`?

You might wonder why `toJSON(secrets)` is passed via `env` instead of directly in the `script` block. `secrets` is an object so we need to convert it to a string first and then parse it back to an object in the script. This is a common pattern to pass complex data structures to GitHub script. 

## The key name transformation

GitHub Secrets names are case-insensitive and always stored uppercase by convention. Terraform's `TF_VAR_` lookup is case-sensitive - it requires the part after the prefix to match the exact variable name defined in Terraform template which by convention is in lowercase. 

The transformation handles this:

```javascript
const exportKey = `TF_VAR_${key.slice('TF_VAR_'.length).toLowerCase()}`;
```

This strips the `TF_VAR_` prefix, lowercases the remainder, then re-attaches the prefix. So `TF_VAR_DATABASE_PASSWORD` becomes `TF_VAR_database_password`, which Terraform will correctly map to `var.database_password`.

## Exporting to subsequent steps

`core.exportVariable(key, value)` is the GitHub Actions toolkit equivalent of writing to {% raw %}`$GITHUB_ENV`{% endraw %}. It sets an environment variable that persists for all subsequent steps in the job - not just the current step. This means every step after this one (your `terraform plan`, `terraform apply`, etc.) will automatically have the correct `TF_VAR_*` environment variables set without any additional configuration.

`core.info(...)` logs the key name (never the value, but the value would be redacted anyway) so you can verify in the run log which secrets were picked up, without leaking anything.

## What about environment variables?
The same pattern can be used to export GitHub configuration variables as well. Instead of referencing `secrets`, you can reference `vars` directly to access all configuration variables available in the current context. You can then filter and export them as needed for your workflow.

# Full Example

Caller workflow deploying to dev first, then production sequentially:

{% raw %}
```yaml
# .github/workflows/cicd.yaml
jobs:
  apply-dev:
    uses: ./.github/workflows/terraform-reusable.yaml
    secrets: inherit
    with:
      environment: dev

  apply-prd:
    uses: ./.github/workflows/terraform-reusable.yaml
    needs: apply-dev
    secrets: inherit
    with:
      environment: prd
```
{% endraw %}

Reusable workflow with the dynamic secrets export as the first step, before Terraform runs:

{% raw %}
```yaml
# .github/workflows/reusable.yaml
on:
  workflow_call:
    inputs:
      environment:
        required: true
        type: string

jobs:
  terraform:
    runs-on: ubuntu-latest
    environment: ${{ inputs.environment }}

    steps:
      - name: Export TF_VAR secrets
        uses: actions/github-script@v8.0.0
        env:
          ALL_SECRETS: ${{ toJSON(secrets) }}
        with:
          script: |
            const secrets = JSON.parse(process.env.ALL_SECRETS);
            for (const [key, value] of Object.entries(secrets)) {
              if (key.startsWith('TF_VAR_')) {
                const exportKey = `TF_VAR_${key.slice('TF_VAR_'.length).toLowerCase()}`;
                core.exportVariable(exportKey, value);
                core.info(`Exported: ${key} as ${exportKey}`);
              }
            }

      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3

      - name: Run Terraform
        run: terraform init && terraform apply -auto-approve
```
{% endraw %}

Good luck!
