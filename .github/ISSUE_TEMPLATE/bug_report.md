---
name: Bug report
about: Something not working as expected
title: ""
labels: bug
assignees: ""
---

## What happened

<!-- 1–2 sentences. What did you expect, what did you see instead? -->

## Module / provider versions

- Module version: (e.g. `v0.1.0`)
- Terraform / OpenTofu: (output of `terraform version` or `tofu version`)
- aws provider: (from `.terraform.lock.hcl`)

## Relevant configuration

Which module: the root module (organization) / `modules/identity-center`

<details><summary>module block</summary>

```hcl
# paste the module block here; redact account IDs and emails as needed
```

</details>

## `terraform plan` / `apply` output

<details><summary>output</summary>

```
# redact account IDs and emails as needed
```

</details>

## For imports only

If importing an existing organization or account shows a change, include the changed
attribute lines from the plan and the matching output of
`aws organizations list-roots` / `list-aws-service-access-for-organization`.
