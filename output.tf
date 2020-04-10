output "invoke_url" {
  value = aws_api_gateway_deployment.apigw.invoke_url
}

output "execution_arn" {
  value = aws_api_gateway_deployment.apigw.execution_arn
}

output "deployment_created_date" {
  value = aws_api_gateway_deployment.apigw.created_date
}

output "deployment_id" {
  value = aws_api_gateway_deployment.apigw.id
}

output "domain_name" {
  value = aws_api_gateway_domain_name.apigw.*.domain_name
}

output "api_id" {
  value = aws_api_gateway_rest_api.apigw.id
}

output "api_root_id" {
  value = aws_api_gateway_rest_api.apigw.root_resource_id
}

output "gateway_http_method" {
  value = aws_api_gateway_method.main.http_method
}

output "gateway_resource_id" {
  value = aws_api_gateway_method.main.resource_id
}

