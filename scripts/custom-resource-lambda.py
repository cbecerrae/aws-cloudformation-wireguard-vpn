import json
import base64
import boto3
import cfnresponse

# Initialize EC2 client
ec2 = boto3.client("ec2")

def handler(event, context):
    try:
        # Log the received CloudFormation event for debugging
        print("Received event:", json.dumps(event))

        # Extract resource properties from the CloudFormation custom resource
        props = event["ResourceProperties"]
        server_pubkey_wrapper = props["ServerPublicKey"]

        # Decode the wrapper JSON containing WireGuard server public key
        wrapper = json.loads(server_pubkey_wrapper)
        server_pubkey = wrapper["WireGuardConfig"]

        # Extract additional properties
        public_ip = props["PublicIp"]
        vpn_cidr = props["VpnCidr"]
        port = int(props["Port"])
        vpc_id = props["VpcId"]
        additional_cidrs = props["AdditionalCidrs"]
        
        # Retrieve VPC CIDR block from AWS
        vpc_resp = ec2.describe_vpcs(VpcIds=[vpc_id])
        vpc_cidr = vpc_resp["Vpcs"][0]["CidrBlock"]
        
        # Build client tunnel configuration
        lines = [
            f"Address = {vpn_cidr.rsplit('.', 1)[0] + './' + vpn_cidr.split('/')[-1]}",  # Client's VPN address
            "[Peer]",  # Begin peer section
            f"PublicKey = {server_pubkey}",  # WireGuard server public key
            f"AllowedIPs = {vpn_cidr}, {vpc_cidr} {',' + additional_cidrs if additional_cidrs else ''}",  # Routes allowed for the client
            f"Endpoint = {public_ip}:{port}"  # Server endpoint for this peer
        ]
        tunnel_config = "\n".join(lines)

        # Encode tunnel configuration in base64 to safely transport via JSON
        encoded_tunnel_config = base64.b64encode(tunnel_config.encode()).decode()

        # Prepare response data for CloudFormation
        response_data = {"TunnelConfig": encoded_tunnel_config}

        # Send SUCCESS response to CloudFormation
        cfnresponse.send(event, context, cfnresponse.SUCCESS, response_data)

    except Exception as e:
        # On any error, send FAILED response with error message
        cfnresponse.send(event, context, cfnresponse.FAILED, {"Error": str(e)})