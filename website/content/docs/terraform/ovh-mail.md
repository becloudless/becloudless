+++
title = "OVH Mail"
weight = 10
description = "OVH mail DNS module — inputs, outputs, usage"
+++

Manages OVH-hosted email DNS records and MX configuration required for the self-hosted Mailu stack.

Module path: `terraform/modules/ovh-mail/`

## Purpose

This module provisions:

- MX, SPF, DKIM, and DMARC DNS records on an OVH-managed domain
- Any OVH email account redirections (if used alongside Mailu for external relay)

## Prerequisites

- OVH account with API credentials (`OVH_ENDPOINT`, `OVH_APPLICATION_KEY`, `OVH_APPLICATION_SECRET`, `OVH_CONSUMER_KEY`)
- A domain managed by OVH DNS

## Usage

```hcl
module "ovh_mail" {
  source = "./modules/ovh-mail"

  domain      = "example.com"
  mx_target   = "mail.example.com"
  dkim_record = "v=DKIM1; k=rsa; p=..."
}
```

## Inputs

| Name | Type | Description |
|---|---|---|
| `domain` | `string` | The OVH-managed domain name |
| `mx_target` | `string` | Hostname of the Mailu ingress |
| `dkim_record` | `string` | DKIM public key record value |

## Outputs

| Name | Description |
|---|---|
| `mx_record` | The created MX record FQDN |

## Apply

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

Credentials are read from environment variables. Do not commit them to the repository.

