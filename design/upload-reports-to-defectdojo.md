# DefectDojo Report Upload Template

The `upload-reports-to-defectdojo.yml` template automates the ingestion of security scan results into a DefectDojo instance for centralized vulnerability management.

## Purpose

- **Centralization**: Aggregates findings from TFLint, KICS, Terrascan, and Checkov.
- **Historical Tracking**: Monitors security trends over time in a single dashboard.
- **De-duplication**: DefectDojo handles overlapping findings from multiple scanners.

## Key Variables

| Variable | Description | Source |
|----------|-------------|--------|
| `DEFECTDOJO_URL` | The API endpoint of your DefectDojo instance. | CI/CD Variables |
| `DEFECTDOJO_API_KEY` | API Key for authentication. | CICD Variables |
| `DEFECTDOJO_ENGAGEMENT_ID` | The specific engagement id in DefectDojo. | CI/CD Variables |

## Workflow

1. **Security Scan**: Security jobs in `iac-security.yml` produce JSON/SARIF artifacts.
2. **Upload to Defectdojo**: The task `upload` runs after the security stage.

## Impact

By integrating with DefectDojo, users can manage their infrastructure security like a professional enterprise, keeping track of "false positives" and "risk acceptance" without cluttering GitLab CI logs.
