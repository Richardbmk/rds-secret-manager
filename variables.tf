# Input Variables

# AWS Region
variable "region" {
  description = "Region in which AWS Resource will be created"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "instance type of the EC2 instance"
  type        = string
  default     = "t2.micro"
}