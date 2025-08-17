#!/bin/bash
set -xe

# Update package lists and install required packages
apt update
apt install -y python3-pip

# Install AWS CloudFormation bootstrap scripts
pip3 install https://s3.amazonaws.com/cloudformation-examples/aws-cfn-bootstrap-py3-latest.tar.gz

# Run cfn-init to apply metadata configurations
cfn-init -v --stack ${AWS::StackName} --resource WireGuardEc2Instance --region ${AWS::Region}

# Start cfn-hup daemon to check for updates
cfn-hup -v