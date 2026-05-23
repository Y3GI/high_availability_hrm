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

variable "github_repo" {
    description = "Github repo"
    type        = string
}

variable "github_token_secret_id" {
    description = "Secret Manager secret ID containing the github PAT"
    type        = string
}