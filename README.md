# Field Report System

**Serverless field operations platform — AWS Lambda, API Gateway, DynamoDB, SNS**

![Architecture](project_a_architecture.svg)

---

## The Problem

I spent several years working as a field technician for a commercial water well contractor. Every job ended the same way: paper. Pump installation reports, time and material sheets, flow test data — all written by hand on forms that went into a filing cabinet. Monday mornings, a supervisor reconciled every paper sheet against a separate mobile app before anything could go to payroll. Office staff manually re-typed field reports into digital records. Looking up historical data meant pulling boxes.

The cost is real: supervisor time, data entry time, transcription errors, and a records system that makes anything older than last week slow to find. The problem isn't unique to one company — it's the standard operating model across the trades industry.

This project replaces that chain with a serverless AWS platform. A field technician fills out a mobile web form on their phone, submits it, and the office has a structured digital record and an email notification within seconds — including an AI-generated plain-English summary of what was done. No re-typing. No paper reconciliation. No Monday morning bottleneck.

This is **Project A** of a three-part system:

| Project | Repo | What It Does |
|---|---|---|
| **A — Field Report System** | this repo | Serverless submission platform — the forward-facing data entry point |
| **B — Field Ops Platform** | [field-ops-platform](https://github.com/leyder-ben/field-ops-platform) | EKS GitOps platform running both services in production |
| **C — Field Report Pipeline** | [field-report-pipeline](https://github.com/leyder-ben/field-report-pipeline) | AI-powered pipeline for ingesting paper forms and archival records |

All three projects share a single DynamoDB table and SNS topic. A supervisor sees every field report in one place regardless of whether it was submitted through this system or extracted from a scanned paper form by Project C.

---

## Architecture

![Architecture Diagram](project_a_architecture.svg)

| Tier | Service | Role |
|---|---|---|
| Field | Mobile Web Form (S3 static site) | Field tech submits report from phone — no app install |
| API | API Gateway REST — POST /reports | Receives HTTPS request, validates payload, invokes Lambda |
| Processing | Lambda — process_report (Python 3.12) | Validates, generates UUID + timestamp, writes record, publishes notification |
| AI | Bedrock — Claude Haiku 4.5 | Generates plain-English summary appended to record and notification |
| Storage | DynamoDB — field-reports | Persists every report; shared table with Projects B and C |
| Photo Storage | S3 — photos bucket | Private; accessed via presigned URLs only |
| Notification | SNS | Emails office on every submission |
| Observability | CloudWatch | Logs, error alarms, duration alarms, dashboard |
| Secrets | Secrets Manager | Config values off environment variables |
| Identity | IAM | Least-privilege roles for Lambda and CI/CD |
| IaC | Terraform | Every resource provisioned as code — nothing created by hand |
| CI/CD | GitHub Actions + OIDC | Deploys Lambda and UI on push to main — no stored AWS credentials |

---

## How It Works

**Submission flow:**

1. Field tech opens the form on their phone — hosted on S3, works in any mobile browser
2. Fills out required fields (tech name, job site, report type) plus optional equipment notes, freeform notes, and a photo
3. If a photo is attached, the form fetches a presigned PUT URL from the API, uploads the photo directly to S3, and stores the resulting key — the photo never passes through Lambda
4. Form POSTs a JSON payload to API Gateway
5. Lambda validates required fields, generates a UUID and ISO 8601 timestamp, and writes the record to DynamoDB
6. Lambda calls Bedrock (Claude Haiku 4.5) to generate a 2-3 sentence plain-English summary from the report fields — this happens asynchronously after the DynamoDB write, so a Bedrock failure never loses a submitted report
7. Summary is appended to the DynamoDB record via `update_item`
8. Lambda publishes to SNS — office receives an email with the full report details and the AI summary

**Key decisions:**

- **Serverless over a persistent API server.** Field report volume is bursty — heavy on Monday morning, quiet midweek. Lambda scales to zero between submissions. There's nothing to babysit.
- **Presigned URLs for photo upload.** Photos go directly from the phone to S3 without routing through Lambda. Keeps Lambda fast and avoids the 6MB API Gateway payload limit.
- **Bedrock call is non-blocking and failure-tolerant.** The `try/except` around the Bedrock call means a model availability issue or a slow cold start doesn't fail the form submission. The report is saved regardless; the summary is a nice-to-have.
- **OIDC for CI/CD.** GitHub Actions authenticates to AWS via an OIDC identity provider — no long-lived access keys in GitHub secrets. The deploy role is scoped to exactly what the pipeline needs: update Lambda code and sync the UI bucket.
- **Single HTML file, no dependencies.** The mobile form is a self-contained HTML/CSS/JS file. No build step, no framework, no CDN calls. Deploys with `s3 sync`.

---

## Repository Structure

```
field-report-system/
├── lambda/
│   └── process_report/
│       ├── handler.py          # Lambda function
│       └── requirements.txt    # No external deps — boto3 is in the runtime
├── ui/
│   └── index.html              # Mobile web form — single file, no dependencies
├── infra/                      # Terraform — all AWS resources
│   ├── main.tf                 # Provider config
│   ├── variables.tf
│   ├── outputs.tf
│   ├── dynamodb.tf             # field-reports table (shared with Projects B and C)
│   ├── sns.tf                  # Notification topic (shared with Projects B and C)
│   ├── s3.tf                   # Photos bucket (private), UI static site (public)
│   ├── lambda.tf               # Lambda function, CloudWatch log group
│   ├── api_gateway.tf          # REST API, CORS, request validation
│   ├── iam.tf                  # Lambda exec role, GitHub Actions OIDC deploy role
│   ├── secrets.tf              # Secrets Manager placeholders
│   └── cloudwatch.tf           # Error alarms, duration alarm, dashboard
├── .github/
│   └── workflows/
│       └── deploy.yml          # CI/CD — triggers on lambda/**, ui/**, .github/** changes
├── CLAUDE.md
└── README.md
```

---

## DynamoDB Schema

**Table:** `field-reports`
**Partition key:** `report_id` (String — UUID)
**Sort key:** `submitted_at` (String — ISO 8601)

| Attribute | Type | Notes |
|---|---|---|
| report_id | String (PK) | UUID generated by Lambda |
| submitted_at | String (SK) | ISO 8601 timestamp |
| source | String | `form` — distinguishes Project A submissions from Project C uploads |
| tech_name | String | Field technician name |
| job_site | String | Site name or address |
| report_type | String | `t_and_m`, `pump_install_vt`, `pump_install_sc`, `pump_install_submersible`, `pump_install_horizontal`, `fire_pump_test`, `well_cleaning`, `pumping_test`, `observation_well`, `timesheet` |
| equipment | String | Make, model, serial — optional |
| notes | String | Free text observations — optional |
| photo_key | String | S3 key for photo attachment — nullable |
| summary | String | Bedrock-generated plain-English summary — nullable |

This table is shared with Projects B and C. The `source` attribute distinguishes entry points: `form` (this project) and `upload` (Project C).

---

## Build and Deploy

**Prerequisites:** AWS CLI configured, Terraform installed, Python 3.12

```bash
# Clone the repo
git clone git@github.com:leyder-ben/field-report-system.git
cd field-report-system

# Provision infrastructure
cd infra
terraform init
terraform plan
terraform apply
```

Terraform provisions everything: DynamoDB, SNS, S3 buckets, Lambda, API Gateway, IAM roles, CloudWatch alarms, and the dashboard. The Lambda zip is built from `lambda/process_report/` at apply time via an `archive_file` data source.

After `terraform apply`, upload the UI:

```bash
aws s3 sync ui/ s3://<ui-bucket-name>/ --delete
```

The UI bucket name is in the Terraform outputs as `ui_bucket_website_url`.

**CI/CD** handles deploys automatically from there. Pushing to `main` triggers the GitHub Actions workflow, which packages the Lambda, deploys it, syncs the UI bucket, and runs a smoke test. The workflow only fires on changes to `lambda/`, `ui/`, or `.github/workflows/` — doc-only commits don't trigger a deploy.

The workflow authenticates to AWS via OIDC. No access keys are stored anywhere. The IAM deploy role is scoped to `lambda:UpdateFunctionCode`, `lambda:GetFunction`, `lambda:GetFunctionConfiguration`, `lambda:PublishVersion`, and S3 sync on the UI bucket.

---

## Troubleshooting

*Real issues encountered during the build. These are the kinds of problems that don't show up in tutorials.*

**DynamoDB tag value rejected — `ValidationException`**
Tag values containing em dashes or commas fail silently at plan time but blow up at apply. The error message says "invalid characters" but doesn't tell you which ones. Keep DynamoDB tag values plain ASCII — no punctuation beyond spaces.

**GitHub OIDC provider already exists — `EntityAlreadyExists`**
If you have other projects on the same AWS account that already set up the GitHub OIDC provider, Terraform will fail trying to create a second one. Only one exists per account. Fix: `terraform import aws_iam_openid_connect_provider.github <existing-arn>`.

**S3 bucket policy rejected — `AccessDenied: BlockPublicPolicy`**
Race condition between the public access block resource and the bucket policy resource. Terraform applied the policy before AWS fully propagated the `block_public_acls = false` settings. Fix: add `depends_on = [aws_s3_bucket_public_access_block.ui]` to the bucket policy resource to force ordering.

**API Gateway integration response — `NotFoundException`**
The OPTIONS mock integration response tried to create before the mock integration was registered. Fix: explicit `depends_on` on the integration response resource pointing at both the integration and the method response. API Gateway has propagation delays Terraform's implicit dependency graph doesn't catch.

**CloudWatch dashboard — `InvalidParameterInput: Should have required property 'region'`**
Every widget's `properties` block requires an explicit `region` field. Terraform doesn't infer it from the provider. Add `region = var.aws_region` to every widget.

**Bedrock `ValidationException` — on-demand throughput not supported**
AWS now requires cross-region inference profile IDs instead of bare model IDs for on-demand Bedrock calls. `anthropic.claude-haiku-...` → `us.anthropic.claude-haiku-...`. The `us.` prefix selects the US cross-region inference profile.

**Bedrock `ResourceNotFoundException` — model marked as legacy**
Claude 3 Haiku and Claude 3.5 Haiku are both marked legacy on this AWS account and blocked for invocation. Their inference profiles show `ACTIVE` but invocations fail anyway. Upgraded to Claude Haiku 4.5 (`us.anthropic.claude-haiku-4-5-20251001-v1:0`), which is fully active. Before specifying any Bedrock model, run `aws bedrock list-foundation-models --by-provider Anthropic` and confirm `status: ACTIVE`.

**GitHub Actions `wait function-updated` — `AccessDeniedException`**
`aws lambda wait function-updated` polls `GetFunctionConfiguration` internally, which is a separate permission from `GetFunction`. The deploy role had `GetFunction` but not `GetFunctionConfiguration`. Added `lambda:GetFunctionConfiguration` to the IAM deploy policy.

---

## How This Connects to Projects B and C

**Project B** takes this Lambda API, containerizes it, and runs it on EKS alongside a Supervisor Dashboard. The dashboard reads from the same `field-reports` DynamoDB table and shows submissions in real time — every record from every source, filterable by tech, site, and report type.

**Project C** is the paper-first path. A field tech who isn't ready to switch to digital fills out the same paper form they've always used, snaps a photo, and uploads it. Project C's AI pipeline classifies the document, extracts the structured data, and writes it to the same DynamoDB table using the same schema. The supervisor sees it in the same dashboard alongside digital submissions from this system.

One database. One notification channel. Two submission paths — one for the tech who's ready to go digital today, one for the company that needs a migration path instead of an ultimatum.

---

## About This Project

Built as part of a portfolio demonstrating AWS cloud engineering — serverless architecture, infrastructure as code, CI/CD automation, and practical AI integration. The problem domain comes from firsthand experience in the water well contracting industry.

All test data uses fictional companies and personnel. No real customer or operational data appears anywhere in this repository.

Test data and demo artifacts use a fictional water well contractor — Wolverine Water, Inc. (Millbrook, Indiana) — and two fictional customers:

- Harlan County Rural Water District — municipal water district, tax exempt, File No. 447
- Stover Industrial Park — commercial facility, Kokomo, Indiana, File No. 831
- Birch Creek Township Water Authority — municipal water authority, tax exempt, File No. 612
- Dresser Aggregates, Inc. — aggregate plant, Mentone, Indiana, File No. 204

All synthetic job files, form images, and archival records in this repository are built from these identities. No real customer, employee, or operational data appears anywhere in this repository.
