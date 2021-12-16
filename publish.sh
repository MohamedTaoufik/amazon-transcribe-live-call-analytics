#!/bin/bash

##############################################################################################
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
##############################################################################################

##############################################################################################
# Create new Cfn artifacts bucket if not already existing
# Build artifacts
# Upload artifacts to S3 bucket for deployment with CloudFormation
##############################################################################################

USAGE="$0 <cfn_bucket_basename> <cfn_prefix> <region> [public]"

BUCKET_BASENAME=$1
[ -z "$BUCKET_BASENAME" ] && echo "Cfn bucket name is a required parameter. Usage $USAGE" && exit 1

PREFIX=$2
[ -z "$PREFIX" ] && echo "Prefix is a required parameter. Usage $USAGE" && exit 1

REGION=$3
[ -z "$REGION" ] && echo "Region is a required parameter. Usage $USAGE" && exit 1
export AWS_DEFAULT_REGION=$REGION

ACL=$4
if [ "$ACL" == "public" ]; then
  echo "Published S3 artifacts will be acessible by public (read-only)"
  PUBLIC=true
else
  echo "Published S3 artifacts will NOT be acessible by public."
  PUBLIC=false
fi

# Remove trailing slash from prefix if needed, and append VERSION
VERSION=$(cat ./VERSION)
[[ "${PREFIX}" == */ ]] && PREFIX="${PREFIX%?}"
PREFIX_AND_VERSION=${PREFIX}/${VERSION}

# Append region to bucket basename
BUCKET=${BUCKET_BASENAME}-${REGION}

# Create bucket if it doesn't already exist
aws s3api list-buckets --query 'Buckets[].Name' | grep "\"$BUCKET\"" > /dev/null 2>&1
if [ $? -ne 0 ]; then
  echo "Creating s3 bucket: $BUCKET"
  aws s3 mb s3://${BUCKET} || exit 1
  aws s3api put-bucket-versioning --bucket ${BUCKET} --versioning-configuration Status=Enabled || exit 1
else
  echo "Using existing bucket: $BUCKET"
fi

echo -n "Make temp dir: "
timestamp=$(date "+%Y%m%d_%H%M")
tmpdir=/tmp/lca
[ -d $tmpdir ] && rm -fr $tmpdir
mkdir -p $tmpdir
pwd

dir=lca-chimevc-stack
echo "PACKAGING $dir"
pushd $dir
./publish.sh $BUCKET $PREFIX_AND_VERSION/lca-chimevc-stack $REGION || exit 1
popd


dir=lca-ai-stack
echo "PACKAGING $dir"
pushd $dir/deployment
rm -fr ../out
chmod +x ./build-s3-dist.sh
./build-s3-dist.sh $BUCKET_BASENAME $PREFIX_AND_VERSION/lca-ai-stack $VERSION $REGION || exit 1
popd

echo "PACKAGING Main Stack Cfn artifacts"
MAIN_TEMPLATE=lca-main.yaml

echo "Inline edit $MAIN_TEMPLATE to replace "
echo "   <ARTIFACT_BUCKET_TOKEN> with bucket name: $BUCKET"
echo "   <ARTIFACT_PREFIX_TOKEN> with prefix: $PREFIX_AND_VERSION"
echo "   <VERSION_TOKEN> with version: $VERSION"
echo "   <REGION_TOKEN> with region: $REGION"
cat ./$MAIN_TEMPLATE | 
sed -e "s%<ARTIFACT_BUCKET_TOKEN>%$BUCKET%g" | 
sed -e "s%<ARTIFACT_PREFIX_TOKEN>%$PREFIX_AND_VERSION%g" |
sed -e "s%<VERSION_TOKEN>%$VERSION%g" |
sed -e "s%<REGION_TOKEN>%$REGION%g" > $tmpdir/$MAIN_TEMPLATE
# upload main template
aws s3 cp $tmpdir/$MAIN_TEMPLATE s3://${BUCKET}/${PREFIX}/$MAIN_TEMPLATE || exit 1

if $PUBLIC; then
  echo "Setting public read ACLs on published artifacts"
  files=$(aws s3api list-objects --bucket ${BUCKET} --prefix ${PREFIX} --query "(Contents)[].[Key]" --output text)
  for file in $files
    do
    aws s3api put-object-acl --acl public-read --bucket ${BUCKET} --key $file
    done
fi

template="https://s3.${REGION}.amazonaws.com/${BUCKET}/${PREFIX}/${MAIN_TEMPLATE}"
echo "Validating template: $template"
aws cloudformation validate-template --template-url $template > /dev/null || exit 1

echo "OUTPUTS"
echo Template URL: $template
echo CF Launch URL: https://${REGION}.console.aws.amazon.com/cloudformation/home?region=${REGION}#/stacks/create/review?templateURL=${template}\&stackName=LiveCallAnalytics\&param_installDemoAsteriskServer=true
echo CLI Deploy: aws cloudformation deploy --region $REGION --template-file $tmpdir/$MAIN_TEMPLATE --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND --stack-name LiveCallAnalytics --parameter-overrides AllowedSignUpEmailDomain='ACME.COM' installDemoAsteriskServer=true demoSoftphoneAllowedCidr=CIDRBLOCK siprecAllowedCidrList=\"\" S3BucketName=\"\"
echo Done
exit 0

