# ---- use variables defined in terraform.tfvars file
variable "tenancy_ocid" {}

variable "user_ocid" {}
variable "fingerprint" {}
variable "private_key_path" {}
variable "compartment_ocid" {}
variable "region" {}
variable "name_prefix" {}

# ---- provider
provider "oci" {
  region           = "${var.region}"
  tenancy_ocid     = "${var.tenancy_ocid}"
  user_ocid        = "${var.user_ocid}"
  fingerprint      = "${var.fingerprint}"
  private_key_path = "${var.private_key_path}"
}

# -------- get the list of available ADs
data "oci_identity_availability_domains" "ADs" {
  compartment_id = "${var.tenancy_ocid}"
}
 
# ------ Create a new VCN
variable "vcn_cdir" { default = "10.13.0.0/16" }

locals {
  vnc_subnet_workers = ["${cidrsubnet(var.vcn_cdir, 8, 11)}", "${cidrsubnet(var.vcn_cdir, 8, 12)}", "${cidrsubnet(var.vcn_cdir, 8, 13)}" ]
  vnc_subnet_loadbalancers = ["${cidrsubnet(var.vcn_cdir, 8, 21)}", "${cidrsubnet(var.vcn_cdir, 8, 22)}" ]
}

resource "oci_core_virtual_network" "oke-vcn" {
  cidr_block = "${var.vcn_cdir}"
  compartment_id = "${var.compartment_ocid}"
  display_name = "${var.name_prefix}-oke-vcn"
  dns_label = "${var.name_prefix}okevcn"
}
 
resource "oci_core_internet_gateway" "oke-ig" {
  compartment_id = "${var.compartment_ocid}"
  display_name = "${var.name_prefix}-oke-internet-gateway"
  vcn_id = "${oci_core_virtual_network.oke-vcn.id}"
}

resource "oci_core_default_route_table" "oke-rt" {
  manage_default_resource_id = "${oci_core_virtual_network.oke-vcn.default_route_table_id}"
  display_name = "${var.name_prefix}-oke-route-table"
  route_rules {
    destination = "0.0.0.0/0"
    network_entity_id = "${oci_core_internet_gateway.oke-ig.id}"
  }
}

# ------ Create a new security list to be used in the new subnet
# TODO - define proper policies for ingress/egress
resource "oci_core_security_list" "oke-worker-sl" {
  compartment_id = "${var.compartment_ocid}"
  display_name = "${var.name_prefix}-oke-worker-security-list"
  vcn_id = "${oci_core_virtual_network.oke-vcn.id}"
  egress_security_rules = [{
    protocol = "all"
    destination = "0.0.0.0/0"
  }]
 
  ingress_security_rules = [{
    protocol = "all"
    source = "0.0.0.0/0"
  }]
}

resource "oci_core_security_list" "oke-loadbalancer-sl" {
  compartment_id = "${var.compartment_ocid}"
  display_name = "${var.name_prefix}-oke-loadbalancer-security-list"
  vcn_id = "${oci_core_virtual_network.oke-vcn.id}"
  egress_security_rules = [{
    protocol = "all"
    destination = "0.0.0.0/0"
  }]
 
  ingress_security_rules = [{
    protocol = "all"
    source = "0.0.0.0/0"
  }]
}

resource "oci_core_subnet" "oke-subnet-worker" {
  count = 3
  availability_domain = "${lookup(data.oci_identity_availability_domains.ADs.availability_domains[count.index],"name")}"
  compartment_id = "${var.compartment_ocid}"
  display_name = "${var.name_prefix}-oke-subnet-worker${count.index+1}"
	cidr_block = "${local.vnc_subnet_workers[count.index]}"
	security_list_ids = ["${oci_core_security_list.oke-worker-sl.id}"]
  vcn_id = "${oci_core_virtual_network.oke-vcn.id}"
  dns_label = "${var.name_prefix}okesnw${count.index+1}"
}

resource "oci_core_subnet" "oke-subnet-lb" {
  count = 2
  availability_domain = "${lookup(data.oci_identity_availability_domains.ADs.availability_domains[count.index],"name")}"
  compartment_id = "${var.compartment_ocid}"
  display_name = "${var.name_prefix}-oke-subnet-loadbalancer${count.index+1}"
	cidr_block = "${local.vnc_subnet_loadbalancers[count.index]}"
	security_list_ids = ["${oci_core_security_list.oke-loadbalancer-sl.id}"]
  vcn_id = "${oci_core_virtual_network.oke-vcn.id}"
  dns_label = "${var.name_prefix}okelbw${count.index+1}"
}
