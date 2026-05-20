#Base variables
variable "project_id" {
    description = "The Project id"
    type        = string
}

variable "region" {
    description = "The region"
    type        = string 
}

variable "tags" {
    description = "Basic tags"
    type        = map(string)
}

variable "env" {
    description = "The project environment"
    type        = string
}

variable "email" {
    description = "The default email"
    type        = string
}

variable "network_id" {
    description = "VPC network ID for private service access peering"
    type        = string
}

variable "db_tier" {
    description = "Cloud SQL machine tier"
    type        = string
    default     = "db-g1-small"
}