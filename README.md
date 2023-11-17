# Requirement

## First Test (with a Private Endpoint)

1. Provisions a Storage Account using {StorageAccountType} and {ReplicationMode}, with Public Network Access Enabled and a Static Website configuration
2. Provision a Private Link Endpoint.
3. Provisions a Virtual Machine connected to the Private Link.
4. Add a Storage Container and a Blob (HTML file), so that the Static Website can serve a file.
5. Add a Private Link Configuration to this Storage Account
6. Disable Public Network Access for the Storage Account
7. Connect to the Virtual Machine and:
    - Query the Storage Account's Data Plane API (using the Private
    Link) - output if that works/not.
    - Try accessing the Static Website - output if that works/not.
8. Enable Public Network Access, repeat the validation in step 7
9. Disable Public Network Access, repeat the validation in Step 7
10. Tear everything down and note the results

## Second Test (without a Private Endpoint)

In this test we're looking to understand if when toggling Public Network Access from Enabled -> Disabled removes the Static Website configuration from the Data Plane API.

This would allow us to conditionally skip the Static Website call in the Read function.

For this scenario, can we test:

1. Provision a Storage Account using {StorageAccountType} and {ReplicationMode}, with Public Network Access Enabled and a Static Website configuration
2. Disable Public Network Access
3. Wait a bit (30s?)
4. Enable Public Network Access
5. Query the Data Plane endpoint to retrieve the Static Website configuration, output whether it's documented or not.

# How-to

There are two main modules used for below purposes:

- `setup`: This is used to setup the storage accounts of different kind-tier-repl combinations. All the valid combinations are listed in the local variable: `sa_list`, with explaining why some of them are not included by comments. The `sa_list` is affected by the input variable `prefix`, which also affects the other resources, especially the resource group that contain all these resources.

    Besides the `prefix`, there are also below vars:

    - `storage_account_public_access_enabled`: controls whether the `publicNetworkAccess` is enabled (used to control public access within a test scenario)
    - `enable_pe`: controls whether PE (and its related resourcs) is provisioned (used to control whether we are testing for the 1st/2nd scenario)

    Note that we deliberately to use `azapi` provider to create the storage account and the container in order to keep the API interactions in mgmt plane only.

    On successful `apply`, this module outputs the `prefix` and `sa_list`, which are then expected to be directly copied to the tfvar file for the next TF module (see below)

- `check`: This is a module used to check different asserts around the storage account, container, and the static web site. It takes the `prefix` and `sa_list` variables (output from `setup` module), then it check each of the storage account in the `sa_list` via a nested module `check_module`. We used the `check` block of terraform to assert things, which avoids the whole process to be stop due to any failure.

Overall, you'll do the following:

- Modify the `setup/terraform.tfvars` to set the `prefix` for a new test
- `terraform apply` the `setup` module, by setting `storage_account_public_access_enabled` to be `true` (and optionally set `enable_pe` to `true` or `false`, based on the test scenario)
- Copy the output of above run to the `check/terraform.tfvars`
- `terraform apply` the `check` module either locally, or in a VM resides in the same vnet of the PE (if used)
- Check the above run's output to see any `check` failed
    
