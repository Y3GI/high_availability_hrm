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
    description = "The vpc id"
    type        = string
}

variable "subnet_id" {
    description = "The subnet id for GKE nodes"
    type        = string 
}

variable "pods_range_name" {
    description = "The name of the GKE pods range"
    type        = string
}

variable "services_range_name" {
    description = "The name of the GKE service range"
    type        = string
}

variable "node_count" {
    description = "The number of nodes per zone in the default node pool"
    type        = number
    default     = 1
}

variable "machine_type" {
    description = "Machine type for GKE nodes"
    type        = string
    default     = "e2-standard-2"
}

variable "disc_size_gb" {
    description = "Boot disc size in GB per node"
    type        = number
    default     = 50
}