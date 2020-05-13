###########################################################
## API Gateway Set Up
###########################################################
resource "aws_api_gateway_rest_api" "apigw" {
  name                     = var.apigw_name
  description              = var.description
  minimum_compression_size = var.minimum_compression_size

  policy = <<EOF

{
  "Version": "2012-10-17",
  "Statement": [{
      "Effect": "Allow",
      "Principal": "*",
      "Action": "execute-api:Invoke",
      "Resource": "execute-api:/*/*/*"
    },
    {
      "Effect": "Deny",
      "Principal": "*",
      "Action": "execute-api:Invoke",
      "Resource": "execute-api:/*/*/*",
      "Condition": {
        "NotIpAddress": {
          "aws:SourceIp": ["${join("\", \"", var.source_cidr)}"]
        }
      }
    }
  ]
}
EOF

}

resource "aws_api_gateway_resource" "main" {
  rest_api_id = aws_api_gateway_rest_api.apigw.id
  parent_id   = aws_api_gateway_rest_api.apigw.root_resource_id
  path_part   = var.path_part
}

resource "aws_api_gateway_method" "main" {
  rest_api_id   = aws_api_gateway_rest_api.apigw.id
  resource_id   = aws_api_gateway_resource.main.id
  http_method   = var.http_method
  authorization = var.authorization
}

resource "aws_api_gateway_integration" "main" {
  rest_api_id = aws_api_gateway_rest_api.apigw.id
  resource_id = aws_api_gateway_method.main.resource_id
  http_method = aws_api_gateway_method.main.http_method

  # The integration HTTP method specifying how API Gateway 
  # will interact with the back end. Not all methods are 
  # compatible with all AWS integrations. e.g. 
  # Lambda function can only be invoked via POST.
  integration_http_method = var.integration_http_method
  type                    = var.integration_type
  uri                     = var.lambda_invoke_arn
}

resource "aws_api_gateway_deployment" "apigw" {
  depends_on  = [aws_api_gateway_integration.main]
  rest_api_id = aws_api_gateway_rest_api.apigw.id
  stage_name  = var.stage
}

###########################################################
## Allowing API Gateway to Access Lambda
###########################################################
resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_arn
  principal     = "apigateway.amazonaws.com"

  # The /*/* portion grants access from any method on any resource
  # within the API Gateway "REST API".
  source_arn = "${aws_api_gateway_deployment.apigw.execution_arn}/*/*"
}

###########################################################
## Enabling API Gateway logs via CloudWatchLogs
###########################################################
resource "aws_api_gateway_account" "apigw" {
  cloudwatch_role_arn = aws_iam_role.apigw.arn
}

resource "aws_iam_role" "apigw" {
  name               = "${var.apigw_name}-apigw-role"
  assume_role_policy = <<EOF
{
 "Version": "2012-10-17",
 "Statement": [
    {
      "Sid"       : "",
      "Effect"    : "Allow",
      "Principal" : {
        "Service"   : "apigateway.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

}

resource "aws_iam_role_policy" "cloudwatch" {
  name = "${var.apigw_name}-apigw-cloudwatch-policy"
  role = aws_iam_role.apigw.id

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:DescribeLogGroups",
                "logs:DescribeLogStreams",
                "logs:PutLogEvents",
                "logs:GetLogEvents",
                "logs:FilterLogEvents"
            ],
            "Resource": "*"
        }
    ]
}
EOF

}

resource "aws_api_gateway_method_settings" "apigw" {
  rest_api_id = aws_api_gateway_rest_api.apigw.id
  stage_name  = var.stage

  #method_path = "${aws_api_gateway_resource.main.path_part}/${aws_api_gateway_method.main.http_method}"
  ## Currently there is a open bug with this resource which is that the mehtod settings are 
  ## not updated properly. An workaround is to set the method_path to "*/*".
  ## For more info: https://github.com/terraform-providers/terraform-provider-aws/issues/1550
  method_path = "*/*"

  settings {
    metrics_enabled    = var.metrics_enabled
    logging_level      = var.logging_level
    data_trace_enabled = var.data_trace_enabled
  }

  depends_on = [aws_api_gateway_deployment.apigw]
}

###########################################################
## Custom Domain Set up
###########################################################
resource "aws_api_gateway_domain_name" "apigw" {
  count                    = var.custom_domain_enabled ? 1 : 0
  domain_name              = var.domain_name
  regional_certificate_arn = var.regional_aws_acm_certificate_arn

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_route53_record" "apigw" {
  count   = var.custom_domain_enabled ? 1 : 0
  zone_id = var.aws_route53_zone_id
  name    = aws_api_gateway_domain_name.apigw[0].domain_name
  type    = "A"

  alias {
    name                   = aws_api_gateway_domain_name.apigw[0].regional_domain_name
    zone_id                = aws_api_gateway_domain_name.apigw[0].regional_zone_id
    evaluate_target_health = true
  }
}

resource "aws_api_gateway_base_path_mapping" "apigw" {
  count       = var.custom_domain_enabled ? 1 : 0
  api_id      = aws_api_gateway_rest_api.apigw.id
  domain_name = aws_api_gateway_domain_name.apigw[0].domain_name
  stage_name  = aws_api_gateway_deployment.apigw.stage_name
}


###########################################################
## CORS endpoint
###########################################################
resource "aws_api_gateway_method" "cors" {
  count = var.enable_cors ? 1 : 0

  rest_api_id   = aws_api_gateway_rest_api.apigw.id
  resource_id   = aws_api_gateway_resource.main.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "cors" {
  count = var.enable_cors ? 1 : 0

  rest_api_id = aws_api_gateway_rest_api.apigw.id
  resource_id = aws_api_gateway_method.main.resource_id
  http_method = aws_api_gateway_method.cors[0].http_method

  type = "MOCK"

  request_templates = {
    "application/json" = "{ \"statusCode\": 200 }"
  }
}

resource "aws_api_gateway_integration_response" "cors" {
  count = var.enable_cors ? 1 : 0

  rest_api_id = aws_api_gateway_rest_api.apigw.id
  resource_id = aws_api_gateway_method.main.resource_id
  http_method = aws_api_gateway_method.cors[0].http_method

  status_code         = 200
  response_parameters = {
    "method.response.header.Content-Type"                 = "'application/json'",
    "method.response.header.Access-Control-Allow-Origin"  = "'${var.cors_origin}'",
    "method.response.header.Access-Control-Allow-Methods" = "'POST, GET, OPTIONS, PUT, DELETE'",
    "method.response.header.Access-Control-Allow-Headers" = "'Accept, Content-Type, Content-Length, Accept-Encoding, Authorization'",
  }

  depends_on = [
    aws_api_gateway_integration.cors,
    aws_api_gateway_method_response.cors,
  ]
}

resource "aws_api_gateway_method_response" "cors" {
  count = var.enable_cors ? 1 : 0

  rest_api_id = aws_api_gateway_rest_api.apigw.id
  resource_id = aws_api_gateway_method.main.resource_id
  http_method = aws_api_gateway_method.cors[0].http_method

  status_code         = 200
  response_parameters = {
    "method.response.header.Content-Type"                 = true,
    "method.response.header.Access-Control-Allow-Origin"  = true,
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Headers" = true,
  }

  response_models = {
    "application/json" = "Empty"
  }

  depends_on = [aws_api_gateway_method.cors]
}

###########################################################
## GraphiQL
###########################################################
resource "aws_api_gateway_method" "graphiql" {
  rest_api_id   = aws_api_gateway_rest_api.apigw.id
  resource_id   = aws_api_gateway_resource.main.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "graphiql" {

  rest_api_id = aws_api_gateway_rest_api.apigw.id
  resource_id = aws_api_gateway_method.main.resource_id
  http_method = aws_api_gateway_method.graphiql.http_method

  type = "MOCK"

  request_templates = {
    "application/json" = "{ \"statusCode\": 200 }"
  }
}

resource "aws_api_gateway_integration_response" "graphiql" {
  count = var.enable_cors ? 1 : 0

  rest_api_id = aws_api_gateway_rest_api.apigw.id
  resource_id = aws_api_gateway_method.main.resource_id
  http_method = aws_api_gateway_method.graphiql.http_method

  status_code         = 200
  response_parameters = {
    "method.response.header.Content-Type"                 = "'text/html'",
    "method.response.header.Access-Control-Allow-Origin"  = "'${var.cors_origin}'",
    "method.response.header.Access-Control-Allow-Methods" = "'POST, GET, OPTIONS, PUT, DELETE'",
    "method.response.header.Access-Control-Allow-Headers" = "'Accept, Content-Type, Content-Length, Accept-Encoding, Authorization'",
  }

  response_templates = {
    "text/html"      =  var.graphiql_html
  }

  depends_on = [
    aws_api_gateway_integration.graphiql,
    aws_api_gateway_method_response.graphiql,
  ]
}

resource "aws_api_gateway_method_response" "graphiql" {
  rest_api_id = aws_api_gateway_rest_api.apigw.id
  resource_id = aws_api_gateway_method.main.resource_id
  http_method = aws_api_gateway_method.graphiql.http_method

  status_code         = 200
  response_parameters = {
    "method.response.header.Content-Type"                 = true,
    "method.response.header.Access-Control-Allow-Origin"  = true,
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Headers" = true,
  }

  response_models = {
    "text/html" = "Empty"
  }

  depends_on = [aws_api_gateway_method.graphiql]
}
