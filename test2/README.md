In this test we're looking to understand if when toggling Public Network Access from Enabled -> Disabled removes the Static Website configuration from the Data Plane API.

This would allow us to conditionally skip the Static Website call in the Read function.

For this scenario, can we test:

1. Provision a Storage Account using {StorageAccountType} and {ReplicationMode}, with Public Network Access Enabled and a Static Website configuration
2. Disable Public Network Access
3. Wait a bit (30s?)
4. Enable Public Network Access
5. Query the Data Plane endpoint to retrieve the Static Website configuration, output whether it's documented or not.
