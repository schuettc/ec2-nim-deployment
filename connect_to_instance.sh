#!/bin/bash

# Load environment variables from .env file
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
else
    echo "Error: .env file not found."
    exit 1
fi

# Check if STACK_NAME is set in .env
if [ -z "$STACK_NAME" ]; then
    echo "Error: STACK_NAME is not set in .env file."
    exit 1
fi

# Get the AutoScalingGroup name from CloudFormation outputs
ASG_NAME=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='InstanceId'].OutputValue" \
    --output text)

if [ -z "$ASG_NAME" ]; then
    echo "Error: Unable to retrieve AutoScalingGroup name from stack outputs."
    exit 1
fi

# Get the EC2 instance ID from the AutoScalingGroup
INSTANCE_ID=$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "$ASG_NAME" \
    --query "AutoScalingGroups[0].Instances[0].InstanceId" \
    --output text)

if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" == "None" ]; then
    echo "Error: No running instances found in the AutoScalingGroup."
    exit 1
fi

echo "Connecting to instance $INSTANCE_ID in stack $STACK_NAME..."

# Use SSM to start a session with the instance
aws ssm start-session --target "$INSTANCE_ID"