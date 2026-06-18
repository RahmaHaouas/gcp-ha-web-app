variable "project_id" {
  description = "ID du projet GCP"
  type        = string
}

variable "region" {
  description = "Région de déploiement"
  type        = string
  default     = "europe-west1"
}