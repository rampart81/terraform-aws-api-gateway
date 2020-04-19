# terraform-aws-api-gateway
Terraform module which creates API Gateway on AWS 

<aside class="warning">
This module is for terraform version 0.12 and higher.
For 0.11 and below, use the `feature/0.11` branch.
</aside>

## Usage Example

```terraform
module "apigw" {
  source = "github.com/rampart81/terraform-aws-api-gateway"

  apigw_name                       = local.project_name
  description                      = "API Gateway for ${local.project_name}"
  stage                            = local.stage_name
  path_part                        = local.api_path
  http_method                      = "POST"
  authorization                    = local.api_gateway_authorization
  metrics_enabled                  = true
  logging_level                    = "INFO"
  data_trace_enabled               = true
  custom_domain_enabled            = true
  domain_name                      = local.api_domain
  aws_route53_zone_id              = data.aws_route53_zone.wecode.id
  regional_aws_acm_certificate_arn = data.aws_acm_certificate.wecode.arn
  lambda_invoke_arn                = module.api.invoke_arn
  lambda_arn                       = module.api.arn
  enable_cors                      = true
  cors_origin                      = "https://${local.api_domain}"
}
```
* if `enable_cors` is `true`, then a Mock endpoint with OPTIONS method will be created which returns CORS enabled headers including the access allowed origin header set to the value of `cors_origin` input.
