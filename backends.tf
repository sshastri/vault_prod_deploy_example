terraform {
  backend "remote" {
    hostname = "app.terraform.io"
    organization = "ise"

    workspaces {
      name = "vault-dev-primary-us-1"
    }
  }
}
