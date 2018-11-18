## How to set up an APIGW using Terraform

Setting up an APIGW via Terraform can be a complicated and convoluted process since there are so many resources and configurations that need to be set up.

### 1. Set up an APIGW entity

```terraform
resource "aws_api_gateway_rest_api" "apigw" {
  name        = "${var.apigw_name}"
  description = "${var.description}"
}
```

Now that we have set up an APIGW entity, use configure it so that it behaves as we want it.
Just like a regular API endpoint, AWS API Gateway need to know which `resource`s and `method`s it needs to be listening. Then, we need to tell the APIGW what to do with requests. In our case, we forward them to our lambda functions. This part is called `integration`.

### 2. Set up resource for the API gateway 

```terraform
resource "aws_api_gateway_resource" "main" {
  rest_api_id = "${aws_api_gateway_rest_api.apigw.id}"
  parent_id   = "${aws_api_gateway_rest_api.apigw.root_resource_id}"
  path_part   = "${var.path_part}"
}
```
* This is where we’ll configure on what endpoint are we listening for requests. 
* The `path_part` argument will contain a string that represents the endpoint path, as our case is a simple proxy, AWS provides a special handler to listen all the requests, the `{proxy+}`. This handler can also be applied to a more specific path, i.e `users/{proxy+}` where it will listen to anything starting with users ( i.e `users/1/posts` , `users/3/notes` , etc). 
* The other values presented in there are related to where will this resource be applied.
    * The `rest_api_id` will have the id of what API we are mounting this resource.
    * The `parent_id` has the id of the parent on where are mounting this. This last one can be mounted directly on the root api (as we have) or mounted in another `aws_api_gateway_resource` rather than to the api root too, allowing for multi level routes. You can do this by changing the `parent_id` property to point to another `aws_api_gateway_resource.id`.

### 3. Set up method for the API Gateway

```terraform
resource "aws_api_gateway_method" "main" {
  rest_api_id   = "${aws_api_gateway_rest_api.apigw.id}"
  resource_id   = "${aws_api_gateway_resource.main.id}"
  http_method   = "${var.http_method}"
  authorization = "${var.authorization}"
}
```
* In the method resource is were we build the specification of the endpoint we are listening. 
* The `http_method` argument will have the string with what HTTP method we’re interested.
    * There is a special value `ANY` where it'll accept any HTTP method that comes its way. 
* In the case we have in hands we won’t need any authorization done in our AWS API Gateway, and that’s why the value in authorization is `NONE` . 

### 4. Set up the integration between the API Gateway and lambda function

```terraform
resource "aws_api_gateway_integration" "main" {
  rest_api_id = "${aws_api_gateway_rest_api.apigw.id}"
  resource_id = "${aws_api_gateway_method.main.resource_id}"
  http_method = "${aws_api_gateway_method.main.http_method}"

  integration_http_method = "${var.integration_http_method}"
  type                    = "${var.integration_type}"
  uri                     = "${var.lambda_invoke_arn}"
}
```

* The integration resource is related to how are we going to react to the request that we just received, it could go from passing the request to a backend, run some lambda function or even doing nothing with it. 
* The `http_method` argument that will be the same as the method resource (that’s why we link both of them with the `"${aws_api_gateway_method.wemakeprice.http_method}"` ).
* The `integration_http_method` argument represents the HTTP method that will be done from the integration to our backend (again the `ANY` value is a special one).
* The `type` argument is where we configure what type of integration this is. 
    * `AWS`: for integrating the API method request with an AWS service action, including the Lambda function-invoking action. With the Lambda function-invoking action, this is referred to as the Lambda custom integration. With any other AWS service action, this is known as AWS integration.
    * `AWS_PROXY`: for integrating the API method request with the Lambda function-invoking action with the client request passed through as-is. This integration is also referred to as the Lambda proxy integration.
    * `HTTP`: for integrating the API method request with an HTTP endpoint, including a private HTTP endpoint within a VPC. This integration is also referred to as the HTTP custom integration.
    * `HTTP_PROXY`: for integrating the API method request with an HTTP endpoint, including a private HTTP endpoint within a VPC, with the client request passed through as-is. This is also referred to as the HTTP proxy integration.
    * `MOCK`: for integrating the API method request with API Gateway as a "loop-back" endpoint without invoking any backend.
* The `uri` argument contains the endpoint to where we are proxying to.  In our case, we are proxying it to auto distributor lambda functions

### 5. API Gateway Deployment

Just like a regular API which needs to be deployed when it's created or updated, we need to set up an deployment for the API GW so that it can be deployed properly.

```terraform
resource "aws_api_gateway_deployment" "apigw" {
  depends_on = [
    "aws_api_gateway_integration.main"
  ]

  rest_api_id = "${aws_api_gateway_rest_api.apigw.id}"
  stage_name  = "${var.stage}"
}
```
* `stage_name` is the name of the stage. 
    * If the specified stage already exists, it will be updated to point to the new deployment.
    * If the stage does not exist, a new one will be created and point to this deployment. 
    * Use `""` to point at the default stage.
* `variables` (Optional) is a map that defines variables for the stage.
* `NOTE`: terraform’s `aws_api_gateway_deployment` won’t deploy subsequent releases in the event that something has changed in an integration, method, etc because nothing in the actual aws_api_gateway_deployment module changed. This is by design so that you can have a shared definition of your API across stages, but then do environment/stage specific deployments. To force a deployment:
    * Manually tainting the resource.
    * Or trigger a change to the deployment by adding a variable to the deployments variables map including some sort of version for the release.

### 6. Allow API Gateway To Access Lambda

If a API Gateway is integrated with AWS Lambda, which is the case for this module, then the API Gateway needs to given a permission to access the labmda.

```terraform
resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = "${var.lambda_arn}"
  principal     = "apigateway.amazonaws.com"

  # The /*/* portion grants access from any method on any resource
  # within the API Gateway "REST API".
  source_arn = "${aws_api_gateway_deployment.apigw.execution_arn}/*/*"
}
```
 
### 7. Enalbe CloudWatchLogs For API Gateway
It's important to enable logs for API gateway so we can see what has happened, what's currently going on, and etc.
In order to enable CloudWatchLogs for API gateway, we need to configure proper IAM role and IAM role policy, and then set method settings properly.

```terraform
resource "aws_api_gateway_account" "apigw" {
  cloudwatch_role_arn = "${aws_iam_role.apigw.arn}"
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
  role = "${aws_iam_role.apigw.id}"

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
  rest_api_id = "${aws_api_gateway_rest_api.apigw.id}"
  stage_name  = "${var.stage}"
  #method_path = "${aws_api_gateway_resource.main.path_part}/${aws_api_gateway_method.main.http_method}"
  ## Currently there is an open bug with this resource which is that the mehtod settings are 
  ## not updated properly. An workaround is to set the method_path to "*/*".
  ## For more info: https://github.com/terraform-providers/terraform-provider-aws/issues/1550
  method_path = "*/*"

  settings {
    metrics_enabled    = "${var.metrics_enabled}"
    logging_level      = "${var.logging_level}"
    data_trace_enabled = "${var.data_trace_enabled}"
  }

  depends_on = ["aws_api_gateway_deployment.apigw"]
}
```
* `NOTE`: there is an open bug with the `aws_api_gateway_method_settings` resource. Read the comment above for more info.

### 8. Set up custom domain for API Gateway
Usually you would want to use your own domain for API Gateway, although it's not required.
To do that, you need to first set up domain name for the API gateway. Then map the base path to the domain.
Obiviously, route53 record also needs to be set up for this to work.

```terraform
resource "aws_api_gateway_domain_name" "apigw" {
  count                    = "${var.custom_domain_enabled? 1 : 0}"
  domain_name              = "${var.domain_name}"
  regional_certificate_arn = "${var.regional_aws_acm_certificate_arn}"

  endpoint_configuration {
    types = [ "REGIONAL" ]
  }
}

resource "aws_route53_record" "apigw" {
  count   = "${var.custom_domain_enabled? 1 : 0}"
  zone_id = "${var.aws_route53_zone_id}"
  name    = "${aws_api_gateway_domain_name.apigw.domain_name}"
  type    = "A"

  alias {
    name                   = "${aws_api_gateway_domain_name.apigw.regional_domain_name}"
    zone_id                = "${aws_api_gateway_domain_name.apigw.regional_zone_id}"
    evaluate_target_health = true
  }
}

resource "aws_api_gateway_base_path_mapping" "apigw" {
  count       = "${var.custom_domain_enabled? 1 : 0}"
  api_id      = "${aws_api_gateway_rest_api.apigw.id}"
  domain_name = "${aws_api_gateway_domain_name.apigw.domain_name}"
}
```
