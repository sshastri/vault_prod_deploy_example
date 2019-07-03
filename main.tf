provider aws {
  region = "us-west-2"
}

locals {
  cluster_name = "dev-primary-us-1"
  acm_certificate_domain = "vault-dev-us-1.hashi-demos.com"
  hostname               = "vault-dev-us-1"
  route53_zone_name      = "hashi-demos.com."
}


data "aws_caller_identity" "current" {}

# -------------------------------------------------------
# Source the vpc id from a  workspace in Terraform Cloud
# called "network_vault_cluster"
# -------------------------------------------------------
data "terraform_remote_state" "network" {
  backend = "remote"
  config = {
    organization = "ise"
    workspaces {
      name = "network_vault_cluster"
    }
  }
}

data "aws_ami" "consul_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = ["*consul-ent-*"]
  }

  owners = ["${data.aws_caller_identity.current.account_id}"]
}

data "aws_ami" "vault_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = ["*vault-ent-*"]
  }

  owners = ["${data.aws_caller_identity.current.account_id}"]
}

module "consul_network" {
  source              = "git@github.com:hashicorp/IS-terraform-aws-consul-enterprise-ansible.git?ref=vault_tls//consul_network"
  security_group_name = "consul-${local.cluster_name}"
  vpc_id              = "${data.terraform_remote_state.network.vpc_id}"

  server_rpc_port = 7300
  lan_serf_port   = 7301
  wan_serf_port   = 7302
  https_port      = 7501
  http_port       = -1
  dns_port        = 7600

}

module "consul_storage" {
  source             = "git@github.com:hashicorp/IS-terraform-aws-consul-enterprise-ansible.git?ref=vault_tls"
  cluster_name       = "consul-${local.cluster_name}"
  join_tag_key       = "ConsulClusterJoin"
  join_tag_value     = "${local.cluster_name}"
  cluster_size       = 5
  instance_type      = "t3a.medium"
  ssh_key_name       = "shobhna"
  ami_id             = "${data.aws_ami.consul_ami.id}"
  aws_region         = "us-west-2"
  availability_zones = [
                          "us-west-2a",
                          "us-west-2b",
                          "us-west-2c",
                        ]
  vpc_id             = "${data.terraform_remote_state.network.vpc_id}"
  private_subnets    = ["${data.terraform_remote_state.network.private_subnets}"]

  consul_cluster_security_group_id = "${module.consul_network.cluster_security_group_id}"

  additional_sg_ids = [
    "${data.terraform_remote_state.network.bastion_security_group_id}",
  ]

  # Additional tags for dynamic Ansible inventory
  additional_tags = "${
    list(
      map("key", "AnsibleManaged", "value", "True", "propagate_at_launch", true),
    )
  }"

}

module "vault" {
  source             = "../IS-terraform-aws-vault-ansible"
  cluster_name       = "vault-${local.cluster_name}"
  join_tag_key       = "ConsulClusterJoin"
  join_tag_value     = "${local.cluster_name}"
  cluster_size       = 3
  instance_type      = "t3a.medium"
  ssh_key_name       = "shobhna"
  ami_id             = "${data.aws_ami.vault_ami.id}"
  aws_region         = "us-west-2"
  availability_zones = [
                          "us-west-2a",
                          "us-west-2b",
                          "us-west-2c",
                        ]
  vpc_id             = "${data.terraform_remote_state.network.vpc_id}"
  private_subnets    = ["${data.terraform_remote_state.network.private_subnets}"]

  consul_cluster_security_group_id = "${module.consul_network.cluster_security_group_id}"

  lb_security_group_id = "${aws_security_group.vault_alb.id}"

  additional_sg_ids = [
    "${data.terraform_remote_state.network.bastion_security_group_id}",
  ]

  # Additional tags for dynamic Ansible inventory
  additional_tags = "${
    list(
      map("key", "AnsibleManaged", "value", "True", "propagate_at_launch", true),
    )
  }"
}
