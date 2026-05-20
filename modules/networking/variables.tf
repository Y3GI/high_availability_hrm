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

variable "secondary_subnets" {
    description = "Subnet CIDR blocks"
    type        = list(object({
        range_name = string
        ip_cidr_range = string
    }))
    default = [
        {
            range_name      = "k8s-pods-range"
            ip_cidr_range   = "10.48.0.0/14"
        },
        {
            range_name      = "k8s-service-range"
            ip_cidr_range   = "10.52.0.0/20"
        }
    ]
}