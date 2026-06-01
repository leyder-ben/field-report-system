# Field Report System

**Serverless field operations platform — AWS Lambda, API Gateway, DynamoDB, SNS**

![Architecture](project_a_architecture.svg)

> **Status: In Progress** — Infrastructure phase

---

## The Problem

I spent several years working as a field technician for a commercial water well contractor. Every job ended the same way: paper. Pump installation reports, time and material sheets, flow test data — all written by hand on forms that went into a filing cabinet. Monday mornings, a supervisor reconciled every paper sheet against a separate mobile app before anything could go to payroll. Office staff manually re-typed field reports into digital records. Looking up historical data meant pulling boxes.

The cost is real: supervisor time, data entry time, transcription errors, and a records system that makes anything older than last week slow to find. The problem isn't unique to one company — it's the standard operating model across the trades industry.

This project replaces that chain with a serverless AWS platform. A field technician fills out a mobile web form on their phone, submits it, and the office has a structured digital record and an email notification within seconds. No re-typing. No paper reconciliation. No Monday morning bottleneck.

This is **Project A** of a three-part system:

| Project | Repo | What It Does |
|---|---|---|
| **A — Field Report System** | this repo | Serverless submission platform — the data entry point |
| **B — Field Ops Platform** | [field-ops-platform](https://github.com/leyder-ben/field-ops-platform) | EKS GitOps platform running both services in production |
| **C — Field Report Pipeline** | [field-report-pipeline](https://github.com/leyder-ben/field-report-pipeline) | AI-powered pipeline for ingesting paper forms and archival records |

All three projects share a single DynamoDB table and SNS topic. A supervisor sees every field report in one place regardless of whether it was submitted digitally through this system or extracted from a paper form by Project C.

---

## Architecture

| Tier | Service | Role |
|---|---|---|
| Field | Mobile Web Form (S3 static) | Field tech submits report from phone |
| API | API Gateway — POST /reports | Receives HTTPS request, invokes Lambda |
| Processing | Lambda — process_report | Validates, enriches, writes record, notifies office |
| Storage | DynamoDB — field-reports | Persists every report record |
| Notification | SNS | Emails office on every submission |
| AI (optional) | Bedrock — Claude 3 Haiku | Generates plain-English summary of report |
| Observability | CloudWatch | Logs, alarms, dashboard |
| Secrets | Secrets Manager | Nothing sensitive in code or environment variables |
| Identity | IAM | Least-privilege roles for Lambda and CI/CD |
| IaC | Terraform | Every resource provisioned as code |
| CI/CD | GitHub Actions | Deploy Lambda on push to main |

---

## How It Works

1. Field tech opens the mobile web form on their phone — hosted on S3, no app install required
2. Fills out the form: job site, report type, equipment, observations, optional photo
3. Hits submit — HTTPS POST fires to API Gateway
4. Lambda validates the payload, generates a UUID and ISO timestamp, writes the record to DynamoDB
5. Lambda publishes to SNS — office receives an email notification with report details
6. Optionally, Lambda calls Bedrock to generate a plain-English summary appended to the record and included in the notification email

---

## Stack

- **Runtime:** Python 3.12
- **Infrastructure:** Terraform
- **CI/CD:** GitHub Actions with OIDC — no long-lived AWS credentials in GitHub
- **AWS Services:** Lambda, API Gateway, DynamoDB, SNS, S3, Secrets Manager, CloudWatch, Bedrock, IAM

---

## Repository Structure

```
field-report-system/
├── lambda/
│   └── process_report/
│       ├── handler.py          # Lambda function
│       ├── requirements.txt    # Python dependencies
│       └── test_event.json     # Mock API Gateway event for local testing
├── ui/
│   └── index.html              # Mobile web form — single file, S3 hosted
├── infra/                      # Terraform — all AWS resources
│   ├── main.tf                 # Provider config, remote state backend
│   ├── variables.tf
│   ├── outputs.tf
│   ├── dynamodb.tf             # field-reports table
│   ├── sns.tf                  # Notification topic
│   ├── s3.tf                   # Photos bucket, UI static site
│   ├── lambda.tf               # Lambda function and trigger
│   ├── api_gateway.tf          # REST API
│   ├── iam.tf                  # Lambda role, GitHub Actions OIDC deploy role
│   ├── secrets.tf              # Secrets Manager placeholders
│   └── cloudwatch.tf           # Alarms and dashboard
├── .github/
│   └── workflows/
│       └── deploy.yml          # CI/CD pipeline
├── .gitignore
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
| source | String | `form` — identifies Project A submissions |
| tech_name | String | Field technician name |
| job_site | String | Site name or address |
| report_type | String | pump_install / pump_pull / flow_test / cleaning / other |
| equipment | String | Make, model, serial if provided |
| notes | String | Free text observations |
| photo_key | String | S3 key for photo attachment — nullable |
| summary | String | Bedrock-generated plain-English summary — nullable |

This table is shared with Projects B and C. The `source` attribute distinguishes entry points.

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

# Deploy Lambda manually (CI/CD handles this after setup)
cd ../lambda/process_report
zip -r /tmp/process_report.zip .
aws lambda update-function-code \
  --function-name field-report-process \
  --zip-file fileb:///tmp/process_report.zip \
  --region us-east-1
```

CI/CD via GitHub Actions deploys automatically on push to `main`. The workflow uses OIDC to authenticate to AWS — no access keys stored in GitHub secrets.

---

## Troubleshooting

*Real issues encountered and resolved during the build — documented here because these are the kinds of problems that don't show up in tutorials.*

*Entries will be added as the build progresses.*

---

## How This Connects to Projects B and C

**Project B** takes this Lambda API, containerizes it, and runs it on EKS alongside a Supervisor Dashboard. The dashboard reads from the same `field-reports` DynamoDB table and shows submissions in real time.

**Project C** is the paper-first path. A field tech who isn't ready to switch to digital fills out the same paper form they've always used, snaps a photo, and uploads it. Project C's AI pipeline extracts the structured data and writes it to the same DynamoDB table using the same schema — the supervisor sees it in the same dashboard.

One database. One notification system. Two submission paths. That's the system.

---

## About This Project

Built as part of a portfolio demonstrating AWS cloud engineering skills — serverless architecture, infrastructure as code, CI/CD automation, and AI integration. The problem domain comes from firsthand experience working as a field technician in the water well contracting industry.

All test data uses fictional companies and personnel. No real customer or operational data is used anywhere in this repository.
