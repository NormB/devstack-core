## Description

<!-- Provide a clear and concise description of your changes -->

## Type of Change

<!-- Mark the relevant option with an 'x' -->

- [ ] Bug fix (non-breaking change that fixes an issue)
- [ ] New feature (non-breaking change that adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to not work as expected)
- [ ] Documentation update
- [ ] Performance improvement
- [ ] Refactoring (no functional changes)
- [ ] Configuration change
- [ ] Dependency update
- [ ] Other (please describe):

## Related Issues

<!-- Link to related issues using #issue_number -->

Fixes # (issue)
Related to # (issue)

## Changes Made

<!-- Provide a detailed list of changes made in this PR -->

-
-
-

## Motivation and Context

<!-- Why is this change required? What problem does it solve? -->


## Testing Performed

<!-- Describe the testing you've done to verify your changes -->

### Test Environment
- OS:
- Colima version:
- Docker version:

### Test Cases
<!-- Mark completed tests with an 'x' -->

- [ ] Clean installation test (`./devstack.sh clean && ./devstack.sh start`)
- [ ] All services start successfully
- [ ] Health checks pass (`./devstack.sh health`)
- [ ] Vault initialization works
- [ ] Vault bootstrap works
- [ ] Tested affected services individually
- [ ] Verified no regressions in existing functionality
- [ ] Tested error scenarios
- [ ] Integration tests pass (if applicable)

### Test Results

<!-- Paste relevant test outputs, logs, or screenshots -->

```
# Paste test results here
```

## Service Impact

<!-- Which services are affected by this change? Mark with 'x' -->

- [ ] PostgreSQL
- [ ] PgBouncer
- [ ] MySQL
- [ ] Redis Cluster
- [ ] RabbitMQ
- [ ] MongoDB
- [ ] Forgejo (Git Server)
- [ ] HashiCorp Vault
- [ ] Prometheus
- [ ] Grafana
- [ ] Loki
- [ ] Reference API (FastAPI)
- [ ] Colima VM configuration
- [ ] Management script
- [ ] Docker Compose configuration
- [ ] Documentation only
- [ ] Other (specify):

## Breaking Changes

<!-- Does this PR introduce breaking changes? If yes, describe them and provide migration instructions -->

- [ ] This PR introduces breaking changes

**If yes, describe the breaking changes and migration path:**


## Documentation

<!-- Mark completed documentation tasks with an 'x' -->

- [ ] Updated README.md (if needed)
- [ ] Updated CHANGELOG.md
- [ ] Added/updated code comments for complex logic
- [ ] Added/updated configuration file comments
- [ ] Updated CONTRIBUTING.md (if workflow changed)
- [ ] No documentation changes needed

## Checklist

<!-- Ensure all items are completed before requesting review -->

- [ ] My code follows the project's coding standards
- [ ] I have performed a self-review of my code
- [ ] I have commented my code, particularly in hard-to-understand areas
- [ ] I have made corresponding changes to the documentation
- [ ] My changes generate no new warnings or errors
- [ ] I have added tests that prove my fix is effective or that my feature works
- [ ] New and existing tests pass locally with my changes
- [ ] Any dependent changes have been merged and published
- [ ] I have checked my code and corrected any misspellings
- [ ] I have updated the CHANGELOG.md
- [ ] I have sanitized any sensitive information from the PR

## Screenshots / Logs

<!-- If applicable, add screenshots or relevant logs to help explain your changes -->


## Additional Notes

<!-- Any additional information reviewers should know -->


## Reviewer Guidance

<!-- Help reviewers understand how to review this PR -->

**Focus Areas:**
<!-- What should reviewers pay special attention to? -->


**Testing Recommendations:**
<!-- How should reviewers test these changes? -->


---

<!--
For Reviewers:
- Verify all checklist items are completed
- Test the changes in a clean environment
- Check for security implications
- Verify documentation is accurate and complete
- Ensure backwards compatibility (or migration path exists)
-->
