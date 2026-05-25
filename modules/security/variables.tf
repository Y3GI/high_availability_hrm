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

variable "workload_identity_pool" {
    description = "Workload Identity pool — format: PROJECT_ID.svc.id.goog"
    type        = string
}

variable "k8s_namespace" {
    description = "Kubernetes namespace the app runs in"
    type        = string
}

variable "k8s_sa_name" {
    description = "Kubernetes Service Account name the app pods use"
    type        = string
}

variable "db_instance_name" {
    description = "Cloud SQL instance name — used to scope the IAM binding"
    type        = string
}

variable "db_password_secret_id" {
    description = "Secret Manager secret ID for the DB password"
    type        = string
}

variable "domain" {
    description = "Domain for access to through iap"
    type        = string
}

variable "departments" {
    description = "List of department namespaces to provision"
    type        = list(string)
    default     = ["software", "devops", "db-engineering"]
}

variable "iap_members" {
    description = "Principals granted IAP access, e.g. [\"user:alice@gmail.com\"]"
    type        = list(string)
    default     = []
}