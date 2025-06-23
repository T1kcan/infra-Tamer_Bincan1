variable "proxmox_api_url" {
  default = "https://192.168.0.35:8006/api2/json"
}

variable "proxmox_api_token_id" {
  default = "terraform-prov@pve!terra"
}

variable "proxmox_api_token_secret" {
  default = "7defa058-d370-423d-861c-52e6cf3e30de"
}

variable "pm_node" {
  default = "pve"
}

variable "storage" {
  default = "local"
}
