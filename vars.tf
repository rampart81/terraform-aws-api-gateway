variable "apigw_name" {
}

variable "stage" {
}

variable "path_part" {
}

variable "http_method" {
  default = "ANY"
}

variable "authorization" {
  default = "NONE"
}

variable "integration_http_method" {
  default = "POST"
}

variable "description" {
  default = ""
}

variable "metrics_enabled" {
  default = true
}

variable "logging_level" {
  default = "INFO"
}

variable "data_trace_enabled" {
  default = true
}

variable "custom_domain_enabled" {
  default = false
}

variable "aws_route53_zone_id" {
  default = -1
}

variable "domain_name" {
  default = ""
}

variable "regional_aws_acm_certificate_arn" {
  default = ""
}

variable "lambda_invoke_arn" {
}

variable "lambda_arn" {
}

## This has to be AWS_PROXY for now
variable "integration_type" {
  default = "AWS_PROXY"
}

variable "minimum_compression_size" {
  default = 1000000
}

variable "enable_cors" {
  type    = bool
  default = true
}

variable "cors_origin" {
  type    = string
  default = "*"
}

variable source_cidr {
  type = list(string)
}
