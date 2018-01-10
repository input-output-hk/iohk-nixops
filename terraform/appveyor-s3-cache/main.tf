provider "aws" {
  region = "us-west-1"
}

terraform {
  backend "s3" {
    bucket  = "iohk-ops-tfstate"
    key     = "remote-tfstate/cache-s3-iam-policy/terraform.tfstate"
    region  = "us-west-1"
    encrypt = true
  }
}

module "ci-cache" {
  source     = "../modules/ci-cache-s3"
  prefix     = "appveyor-"              # <-- make sure to set this to a custom value.
  pgp_key    = "keybase:ielectric"      # <-- or a base64 encoded PGP public key
  cache_days = 30
}

output "bucket_name" {
  value = "${module.ci-cache.bucket_name}"
}

output "access_key" {
  value = "${module.ci-cache.access_key}"
}

output "secret_key" {
  value = "${module.ci-cache.secret_key}"
}
