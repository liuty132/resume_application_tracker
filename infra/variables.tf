variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "apptracker"
  sensitive   = false
}

variable "db_user" {
  description = "PostgreSQL database user"
  type        = string
  default     = "apptracker_user"
  sensitive   = false
}

variable "db_password" {
  description = "PostgreSQL database password"
  type        = string
  sensitive   = true
}

variable "firebase_project_id" {
  description = "Firebase project ID"
  type        = string
  sensitive   = true
}
