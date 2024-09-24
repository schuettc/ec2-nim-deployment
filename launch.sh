#!/bin/bash

# Enable exit on error and debug output
set -e

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Function to log errors
log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: $1" >&2
}

log_message "Script started"

# Load environment variables from .env file
if [ -f .env ]; then
    log_message "Loading .env file..."
    set -a
    source .env
    set +a
    log_message ".env file loaded"
else
    log_error ".env file not found"
    exit 1
fi

# Check required variables
required_vars=(
    "STACK_NAME"
    "AWS_REGION"
    "TEMPLATE_FILE"
    "INSTANCE_TYPE"
    "KEY_NAME"
    "DOMAIN_NAME"
    "HOSTED_ZONE_ID"
    "REPOSITORY"
    "LATEST_TAG"
    "NGC_API_KEY_SECRET_NAME"
)

log_message "Checking required variables..."
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        log_error "$var is not set in the .env file"
        exit 1
    fi
    log_message "$var is set"
done

# Set optional variables with default values
VPC_ID=${VPC_ID:-""}
SUBNET_IDS=${SUBNET_IDS:-""}
CAPACITY_RESERVATION_ID=${CAPACITY_RESERVATION_ID:-""}
PLACEMENT_GROUP_NAME=${PLACEMENT_GROUP_NAME:-""}

# Get AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Generate S3 bucket name
STACK_NAME_LOWER=$(echo "$STACK_NAME" | tr '[:upper:]' '[:lower:]')
S3_BUCKET_NAME="cf-templates-${STACK_NAME_LOWER}-${AWS_ACCOUNT_ID}-${AWS_REGION}"
log_message "Generated S3 bucket name: $S3_BUCKET_NAME"

# Function to create S3 bucket if it doesn't exist
create_s3_bucket() {
    if aws s3 ls "s3://$S3_BUCKET_NAME" 2>&1 | grep -q 'NoSuchBucket'
    then
        log_message "Creating S3 bucket: $S3_BUCKET_NAME"
        aws s3 mb "s3://$S3_BUCKET_NAME" --region "$AWS_REGION"
    else
        log_message "S3 bucket already exists: $S3_BUCKET_NAME"
    fi
}

# Function to upload templates to S3
upload_templates() {
    log_message "Uploading templates to S3..."
    aws s3 cp vpc-stack.yaml "s3://$S3_BUCKET_NAME/vpc-stack.yaml"
    aws s3 cp ec2-stack.yaml "s3://$S3_BUCKET_NAME/ec2-stack.yaml"
    aws s3 cp alb-stack.yaml "s3://$S3_BUCKET_NAME/alb-stack.yaml"
    aws s3 cp link-stack.yaml s3://${S3_BUCKET_NAME}/link-stack.yaml  
    log_message "Templates uploaded successfully"
}

# Function to check if the stack exists
stack_exists() {
    aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$AWS_REGION" --no-cli-pager >/dev/null 2>&1
}

# Function to create or update the CloudFormation stack
create_or_update_stack() {
    if stack_exists; then
        log_message "Stack '$STACK_NAME' already exists. Attempting to update..."
        update_stack
    else
        log_message "Stack '$STACK_NAME' does not exist. Attempting to create..."
        create_stack
    fi
}

# Function to update the CloudFormation stack
update_stack() {
    aws cloudformation update-stack \
        --stack-name "$STACK_NAME" \
        --region "$AWS_REGION" \
        --template-body "file://$TEMPLATE_FILE" \
        --parameters \
            ParameterKey=InstanceType,ParameterValue="$INSTANCE_TYPE" \
            ParameterKey=KeyName,ParameterValue="$KEY_NAME" \
            ParameterKey=DomainName,ParameterValue="$DOMAIN_NAME" \
            ParameterKey=HostedZoneId,ParameterValue="$HOSTED_ZONE_ID" \
            ParameterKey=VpcId,ParameterValue="$VPC_ID" \
            ParameterKey=SubnetIds,ParameterValue="$SUBNET_IDS" \
            ParameterKey=Repository,ParameterValue="$REPOSITORY" \
            ParameterKey=LatestTag,ParameterValue="$LATEST_TAG" \
            ParameterKey=NGCApiKeySecretName,ParameterValue="$NGC_API_KEY_SECRET_NAME" \
            ParameterKey=CapacityReservationId,ParameterValue="$CAPACITY_RESERVATION_ID" \
            ParameterKey=S3BucketName,ParameterValue="$S3_BUCKET_NAME" \
            ParameterKey=PlacementGroupName,ParameterValue="$PLACEMENT_GROUP_NAME" \
        --capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND \
        --no-cli-pager

    if [ $? -eq 0 ]; then
        log_message "Stack update initiated successfully"
    else
        log_error "Failed to update stack"
        exit 1
    fi
}

# Function to create the CloudFormation stack
create_stack() {
    log_message "Attempting to create CloudFormation stack..."
    aws cloudformation create-stack \
        --stack-name "$STACK_NAME" \
        --region "$AWS_REGION" \
        --template-body "file://$TEMPLATE_FILE" \
        --parameters \
            ParameterKey=InstanceType,ParameterValue="$INSTANCE_TYPE" \
            ParameterKey=KeyName,ParameterValue="$KEY_NAME" \
            ParameterKey=DomainName,ParameterValue="$DOMAIN_NAME" \
            ParameterKey=HostedZoneId,ParameterValue="$HOSTED_ZONE_ID" \
            ParameterKey=VpcId,ParameterValue="$VPC_ID" \
            ParameterKey=SubnetIds,ParameterValue="$SUBNET_IDS" \
            ParameterKey=Repository,ParameterValue="$REPOSITORY" \
            ParameterKey=LatestTag,ParameterValue="$LATEST_TAG" \
            ParameterKey=NGCApiKeySecretName,ParameterValue="$NGC_API_KEY_SECRET_NAME" \
            ParameterKey=CapacityReservationId,ParameterValue="$CAPACITY_RESERVATION_ID" \
            ParameterKey=S3BucketName,ParameterValue="$S3_BUCKET_NAME" \
            ParameterKey=PlacementGroupName,ParameterValue="$PLACEMENT_GROUP_NAME" \
        --capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND \
        --no-cli-pager
    
    if [ $? -eq 0 ]; then
        log_message "Stack creation initiated successfully"
    else
        log_error "Failed to create stack"
        exit 1
    fi
}

# Create S3 bucket and upload templates
create_s3_bucket
upload_templates

# Call create_or_update_stack function
log_message "Calling create_or_update_stack function..."
create_or_update_stack

# Wait for stack operation to complete
log_message "Waiting for stack operation to complete..."
if aws cloudformation wait stack-update-complete --stack-name "$STACK_NAME" --region "$AWS_REGION" --no-cli-pager || \
   aws cloudformation wait stack-create-complete --stack-name "$STACK_NAME" --region "$AWS_REGION" --no-cli-pager; then
    log_message "Stack operation completed successfully"
else
    log_error "Stack operation failed or timed out"
    exit 1
fi

log_message "Script completed successfully"