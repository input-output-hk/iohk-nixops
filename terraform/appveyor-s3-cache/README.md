# Prerequisites

To start with, create a bucket to store terraform state:

- name: iohk-ops-tfstate
- region: US West (N. California)
- turn on versioning

Side note: terraform will pick credentials from ~/.aws/credentials and you can switch profiles by doing

     export AWS_PROFILE=iohk

To start and see what terraform will do:

    terraform init
    AWS_PROFILE=iohk terraform plan

# Provisioning appveyor bucket

Go ahead by making changes and output variables we need:

    AWS_PROFILE=iohk terraform apply

You'll have to decrypt secret_key:

    AWS_PROFILE=iohk terraform output secret_key | base64 --decode | gpg --decrypt

For each of the outputs use following form to encrypt them:

https://ci.appveyor.com/tools/encrypt

And then modify appveyor.yml with the output values:

environment:
  global:
    AWS_ACCESS_KEY_ID:
      secure: BSNfEghh/xxx=
    AWS_SECRET_ACCESS_KEY
      secure: BSNfEghh/xxx=
    S3_BUCKET: XXX
