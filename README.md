# WireGuard VPN Deployment Using AWS CloudFormation

This CloudFormation template deploys a fully configured **WireGuard VPN server** on AWS, ready for secure client connections.
It provisions the required networking, IAM roles, security groups, an EC2 instance with WireGuard pre-installed, and generates client tunnel configuration dynamically using a **Custom Resource Lambda function**.

To add or remove clients, simply update the **ClientConfig** parameter via a direct CloudFormation stack update. Within a few minutes, `cfn-hup` detects the metadata change, runs `cfn-init` again, updates the WireGuard configuration, and restarts the service automatically—without the need to use **Session Manager**.

## Parameters

The stack accepts several parameters to customize deployment:

| Parameter           | Type                 | Default         | Description                                                                                                             | Required |
| ------------------- | -------------------- | --------------- | ----------------------------------------------------------------------------------------------------------------------- | -------- |
| **AttachElasticIp** | String               | `false`         | Whether to associate an Elastic IP with the EC2 instance (`true` or `false`).                                           | Yes      |
| **ClientConfig**    | String               | (empty)         | Comma-separated list of clients in the format: `number:alias:PublicKey`. Example: `1:john:Base64Key,2:alice:Base64Key`. | Yes      |
| **InstanceType**    | String               | `t2.micro`      | Amazon EC2 instance type used to provision the WireGuard server.                                                        | Yes      |
| **Port**            | Number               | `51820`         | UDP port where the WireGuard server listens.                                                                            | Yes      |
| **Prefix**          | String               | (empty)         | Optional prefix for resource names. If set, must end with `-`.                                                          | No       |
| **PublicSubnetId**  | AWS::EC2::Subnet::Id | (empty)         | Public subnet within the VPC where the WireGuard EC2 instance will be deployed.                                         | Yes      |
| **VpcId**           | AWS::EC2::VPC::Id    | (empty)         | The VPC where the WireGuard VPN will operate.                                                                           | Yes      |
| **VpnCidr**         | String               | `100.64.0.0/16` | CIDR block for the VPN network. Must be between `/16` and `/24`.                                                        | Yes      |

## Resources

The template provisions several AWS resources:

### Core Infrastructure

* **IAM Role & Instance Profile**: Allows the EC2 instance to use SSM and bootstrap itself with CloudFormation helper scripts.
* **Security Group**: Opens the WireGuard UDP port (default `51820`) to all IPs.
* **Elastic IP (Conditional)**: Attached to the instance if `AttachElasticIp=true`.

### WaitCondition

* **WaitHandle**: Provides a presigned URL for signaling completion.
* **WaitCondition**: Ensures CloudFormation waits until the EC2 instance completes WireGuard configuration before proceeding. The setup script sends a **SUCCESS** signal including the server’s **public key**.

### WireGuard EC2 Instance

* Ubuntu 22.04 AMI (latest via SSM parameter).
* Installs WireGuard, generates keys, sets up `wg0.conf`, applies client configurations, and enables IP forwarding.
* Bootstrapped with `cfn-init` and auto-updates via `cfn-hup`.

### Custom Resources

* **Lambda Function**: Generates client tunnel configuration by combining the WireGuard server’s public key, public IP and port, VPN CIDR, and VPC routes.
* **Custom::WireGuardTunnelConfig**: Calls the Lambda, which returns the client tunnel configuration in **Base64** format.

## Outputs

The stack provides the following useful outputs:

| Output                          | Description                                                       |
| ------------------------------- | ------------------------------------------------------------------|
| **WireGuardSecurityGroupId**    | Security Group ID attached to the WireGuard EC2 instance.         |
| **WireGuardInstanceId**         | EC2 instance ID running the WireGuard server.                     |
| **WireGuardPublicIp**           | Public IP (Elastic IP if attached, otherwise instance public IP). |
| **WireGuardPrivateIp**          | Private IP of the EC2 instance.                                   |
| **TestPing**                    | Command to ping the WireGuard private IP.                         |
| **WireGuardTunnelConfig**       | Base64-encoded client tunnel configuration.                       |
| **WireGuardPort**               | UDP port used by WireGuard.                                       |
| **WireGuardVpcId**              | VPC where the VPN is deployed.                                    |
| **WireGuardVpnCidr**            | CIDR block assigned to VPN.                                       |
| **WireGuardConfigFile**         | Path to WireGuard configuration.                                  |
| **WireGuardRestartCommand**     | Command to restart the WireGuard service.                         |
| **WireGuardStatusCommand**      | Command to check WireGuard status.                                |
| **WireGuardInstallationUrl**    | Official WireGuard installation documentation.                    |
| **ClientTunnelConfigDecodeUrl** | Online Base64 decoder for the client tunnel configuration.        |

## Notes

* The **WaitCondition** ensures reliable provisioning by waiting for WireGuard setup before signaling stack success.
* The **Custom Resource Lambda** provides dynamic tunnel configs without manual editing.
* The **ClientConfig parameter** must include valid WireGuard public keys.
* Modifications to the **ClientConfig** can be done directly via CloudFormation; `cfn-hup` applies changes automatically, updating WireGuard and restarting the service, all without the need to use **Session Manager**.

## Updates / Client Management

To modify the WireGuard clients:

1. Open the CloudFormation stack in the AWS Management Console (or use AWS CLI).
2. Perform a **direct update** on the existing template and adjust the **ClientConfig** parameter with the new list of clients.

   * Format: `number:alias:PublicKey` (comma-separated for multiple clients)
   * Example: `1:john:Base64Key,2:alice:Base64Key,3:bob:Base64Key`
3. Within a few minutes, the EC2 instance detects the change via **cfn-hup**, runs **cfn-init**, updates `/etc/wireguard/wg0.conf`, and restarts the WireGuard service.

This allows you to **add or remove clients easily** without the need to use **Session Manager**, keeping updates centralized and reproducible through CloudFormation.
