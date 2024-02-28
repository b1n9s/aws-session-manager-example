# AWS Session Manager Example

Key points are:

- Enable VPC's DNS support
- Create the endpoints for:
  - ec2messages
  - ssm
  - ssmmessages
- The private DNS is enabled on the endpoints
- Endpoints are associated with the subnet
- The security group of the endpoints allows 443 egress
- The Instance profile has the policy `AmazonSSMManagedInstanceCore` attached
- And of course, The AMI being used needs to have the SSM agent pre-installed
