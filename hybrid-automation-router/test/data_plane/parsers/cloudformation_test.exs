# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule HAR.DataPlane.Parsers.CloudFormationTest do
  @moduledoc """
  Tests for the AWS CloudFormation template parser.

  Verifies conversion of CloudFormation YAML/JSON templates into HAR
  semantic graph operations. Handles AWS resource type mappings,
  property normalization, DependsOn explicit dependencies, and
  implicit dependencies from Ref/GetAtt intrinsic functions.
  """
  use ExUnit.Case

  alias HAR.DataPlane.Parsers.CloudFormation
  alias HAR.Semantic.{Graph, Dependency}

  describe "parse/2 with EC2 Instance" do
    test "parses EC2 Instance resource" do
      yaml = """
      AWSTemplateFormatVersion: "2010-09-09"
      Resources:
        MyInstance:
          Type: AWS::EC2::Instance
          Properties:
            InstanceType: t3.micro
            ImageId: ami-12345678
      """

      assert {:ok, %Graph{} = graph} = CloudFormation.parse(yaml)
      assert length(graph.vertices) == 1

      op = hd(graph.vertices)
      assert op.type == :vm_create
      assert op.params.instance_type == "t3.micro"
      assert op.params.image_id == "ami-12345678"
      assert op.metadata.source == :cloudformation
      assert op.metadata.logical_id == "MyInstance"
      assert op.metadata.resource_type == "AWS::EC2::Instance"
    end

    test "parses EC2 Instance with tags" do
      yaml = """
      AWSTemplateFormatVersion: "2010-09-09"
      Resources:
        WebServer:
          Type: AWS::EC2::Instance
          Properties:
            InstanceType: t3.micro
            ImageId: ami-12345678
            Tags:
              - Key: Name
                Value: WebServer
              - Key: Environment
                Value: production
      """

      assert {:ok, %Graph{} = graph} = CloudFormation.parse(yaml)
      op = hd(graph.vertices)
      assert op.params.name == "WebServer"
      assert length(op.params.tags) == 2
    end

    test "parses EC2 Instance with security groups and key name" do
      yaml = """
      AWSTemplateFormatVersion: "2010-09-09"
      Resources:
        MyInstance:
          Type: AWS::EC2::Instance
          Properties:
            InstanceType: t3.micro
            ImageId: ami-12345678
            KeyName: my-key
            SecurityGroupIds:
              - sg-12345678
      """

      assert {:ok, %Graph{} = graph} = CloudFormation.parse(yaml)
      op = hd(graph.vertices)
      assert op.params.key_name == "my-key"
      assert "sg-12345678" in op.params.security_group_ids
    end
  end

  describe "parse/2 with S3 Bucket" do
    test "parses S3 Bucket resource" do
      yaml = """
      AWSTemplateFormatVersion: "2010-09-09"
      Resources:
        MyBucket:
          Type: AWS::S3::Bucket
          Properties:
            BucketName: my-unique-bucket
            AccessControl: Private
      """

      assert {:ok, %Graph{} = graph} = CloudFormation.parse(yaml)
      op = hd(graph.vertices)
      assert op.type == :storage_bucket_create
      assert op.params.name == "my-unique-bucket"
      assert op.params.access_control == "Private"
    end

    test "parses S3 Bucket with versioning" do
      yaml = """
      AWSTemplateFormatVersion: "2010-09-09"
      Resources:
        VersionedBucket:
          Type: AWS::S3::Bucket
          Properties:
            BucketName: versioned-bucket
            VersioningConfiguration:
              Status: Enabled
      """

      assert {:ok, %Graph{} = graph} = CloudFormation.parse(yaml)
      op = hd(graph.vertices)
      assert op.params.versioning == "Enabled"
    end
  end

  describe "parse/2 with Lambda Function" do
    test "parses Lambda Function resource" do
      yaml = """
      AWSTemplateFormatVersion: "2010-09-09"
      Resources:
        MyFunction:
          Type: AWS::Lambda::Function
          Properties:
            FunctionName: my-function
            Runtime: python3.12
            Handler: index.handler
            Role: arn:aws:iam::123456789012:role/lambda-role
            MemorySize: 256
            Timeout: 30
      """

      assert {:ok, %Graph{} = graph} = CloudFormation.parse(yaml)
      op = hd(graph.vertices)
      assert op.type == :function_create
      assert op.params.name == "my-function"
      assert op.params.runtime == "python3.12"
      assert op.params.handler == "index.handler"
      assert op.params.memory_size == 256
      assert op.params.timeout == 30
    end

    test "parses Lambda with environment variables" do
      yaml = """
      AWSTemplateFormatVersion: "2010-09-09"
      Resources:
        MyFunction:
          Type: AWS::Lambda::Function
          Properties:
            FunctionName: my-function
            Runtime: python3.12
            Handler: index.handler
            Role: arn:aws:iam::123456789012:role/lambda-role
            Environment:
              Variables:
                TABLE_NAME: my-table
                REGION: us-east-1
      """

      assert {:ok, %Graph{} = graph} = CloudFormation.parse(yaml)
      op = hd(graph.vertices)
      assert op.params.environment["TABLE_NAME"] == "my-table"
    end
  end

  describe "parse/2 with VPC and networking" do
    test "parses VPC resource" do
      yaml = """
      AWSTemplateFormatVersion: "2010-09-09"
      Resources:
        MyVPC:
          Type: AWS::EC2::VPC
          Properties:
            CidrBlock: 10.0.0.0/16
            EnableDnsHostnames: true
            EnableDnsSupport: true
            Tags:
              - Key: Name
                Value: MyVPC
      """

      assert {:ok, %Graph{} = graph} = CloudFormation.parse(yaml)
      op = hd(graph.vertices)
      assert op.type == :network_vpc_create
      assert op.params.cidr_block == "10.0.0.0/16"
      assert op.params.enable_dns_hostnames == true
    end

    test "parses Subnet resource" do
      yaml = """
      AWSTemplateFormatVersion: "2010-09-09"
      Resources:
        PublicSubnet:
          Type: AWS::EC2::Subnet
          Properties:
            VpcId: vpc-12345678
            CidrBlock: 10.0.1.0/24
            AvailabilityZone: us-east-1a
            MapPublicIpOnLaunch: true
      """

      assert {:ok, %Graph{} = graph} = CloudFormation.parse(yaml)
      op = hd(graph.vertices)
      assert op.type == :network_subnet_create
      assert op.params.cidr_block == "10.0.1.0/24"
      assert op.params.availability_zone == "us-east-1a"
    end

    test "parses SecurityGroup resource" do
      yaml = """
      AWSTemplateFormatVersion: "2010-09-09"
      Resources:
        WebSG:
          Type: AWS::EC2::SecurityGroup
          Properties:
            GroupDescription: Allow HTTP
            GroupName: web-sg
            SecurityGroupIngress:
              - IpProtocol: tcp
                FromPort: 80
                ToPort: 80
                CidrIp: 0.0.0.0/0
      """

      assert {:ok, %Graph{} = graph} = CloudFormation.parse(yaml)
      op = hd(graph.vertices)
      assert op.type == :security_group_create
      assert op.params.description == "Allow HTTP"
      assert length(op.params.ingress_rules) == 1
    end
  end

  describe "parse/2 with IAM resources" do
    test "parses IAM Role resource" do
      yaml = """
      AWSTemplateFormatVersion: "2010-09-09"
      Resources:
        LambdaRole:
          Type: AWS::IAM::Role
          Properties:
            RoleName: lambda-execution-role
            Path: /
            AssumeRolePolicyDocument:
              Version: "2012-10-17"
              Statement:
                - Effect: Allow
                  Principal:
                    Service: lambda.amazonaws.com
                  Action: sts:AssumeRole
      """

      assert {:ok, %Graph{} = graph} = CloudFormation.parse(yaml)
      op = hd(graph.vertices)
      assert op.type == :role_create
      assert op.params.name == "lambda-execution-role"
      assert op.params.path == "/"
    end
  end

  describe "parse/2 with database resources" do
    test "parses RDS DBInstance" do
      yaml = """
      AWSTemplateFormatVersion: "2010-09-09"
      Resources:
        MyDB:
          Type: AWS::RDS::DBInstance
          Properties:
            DBInstanceIdentifier: mydb
            Engine: postgres
            EngineVersion: "15.4"
            DBInstanceClass: db.t3.micro
            AllocatedStorage: 20
            MultiAZ: true
      """

      assert {:ok, %Graph{} = graph} = CloudFormation.parse(yaml)
      op = hd(graph.vertices)
      assert op.type == :database_create
      assert op.params.name == "mydb"
      assert op.params.engine == "postgres"
      assert op.params.instance_class == "db.t3.micro"
      assert op.params.multi_az == true
    end

    test "parses DynamoDB Table" do
      yaml = """
      AWSTemplateFormatVersion: "2010-09-09"
      Resources:
        MyTable:
          Type: AWS::DynamoDB::Table
          Properties:
            TableName: users
            BillingMode: PAY_PER_REQUEST
            AttributeDefinitions:
              - AttributeName: id
                AttributeType: S
            KeySchema:
              - AttributeName: id
                KeyType: HASH
      """

      assert {:ok, %Graph{} = graph} = CloudFormation.parse(yaml)
      op = hd(graph.vertices)
      assert op.type == :database_table_create
      assert op.params.name == "users"
      assert op.params.billing_mode == "PAY_PER_REQUEST"
    end
  end

  describe "DependsOn explicit dependencies" do
    test "extracts DependsOn string dependency" do
      yaml = """
      AWSTemplateFormatVersion: "2010-09-09"
      Resources:
        MyVPC:
          Type: AWS::EC2::VPC
          Properties:
            CidrBlock: 10.0.0.0/16
        MySubnet:
          Type: AWS::EC2::Subnet
          DependsOn: MyVPC
          Properties:
            VpcId: vpc-12345
            CidrBlock: 10.0.1.0/24
      """

      assert {:ok, %Graph{} = graph} = CloudFormation.parse(yaml)
      assert length(graph.vertices) == 2

      explicit_deps =
        Enum.filter(graph.edges, fn dep ->
          dep.metadata[:reason] == "depends_on"
        end)

      assert length(explicit_deps) >= 1
    end

    test "extracts DependsOn list dependency" do
      yaml = """
      AWSTemplateFormatVersion: "2010-09-09"
      Resources:
        MyVPC:
          Type: AWS::EC2::VPC
          Properties:
            CidrBlock: 10.0.0.0/16
        MySG:
          Type: AWS::EC2::SecurityGroup
          Properties:
            GroupDescription: test
        MyInstance:
          Type: AWS::EC2::Instance
          DependsOn:
            - MyVPC
            - MySG
          Properties:
            InstanceType: t3.micro
            ImageId: ami-12345678
      """

      assert {:ok, %Graph{} = graph} = CloudFormation.parse(yaml)
      assert length(graph.vertices) == 3

      explicit_deps =
        Enum.filter(graph.edges, fn dep ->
          dep.metadata[:reason] == "depends_on"
        end)

      assert length(explicit_deps) >= 2
    end
  end

  describe "Ref and GetAtt implicit dependencies" do
    test "extracts Ref implicit dependency" do
      yaml = """
      AWSTemplateFormatVersion: "2010-09-09"
      Resources:
        MyVPC:
          Type: AWS::EC2::VPC
          Properties:
            CidrBlock: 10.0.0.0/16
        MySubnet:
          Type: AWS::EC2::Subnet
          Properties:
            VpcId:
              Ref: MyVPC
            CidrBlock: 10.0.1.0/24
      """

      assert {:ok, %Graph{} = graph} = CloudFormation.parse(yaml)
      assert length(graph.vertices) == 2

      ref_deps =
        Enum.filter(graph.edges, fn dep ->
          dep.metadata[:reason] == "ref"
        end)

      assert length(ref_deps) >= 1
    end

    test "extracts Fn::GetAtt implicit dependency" do
      yaml = """
      AWSTemplateFormatVersion: "2010-09-09"
      Resources:
        MyBucket:
          Type: AWS::S3::Bucket
          Properties:
            BucketName: my-bucket
        MyFunction:
          Type: AWS::Lambda::Function
          Properties:
            FunctionName: my-function
            Runtime: python3.12
            Handler: index.handler
            Role: arn:aws:iam::123456789012:role/role
            Environment:
              Variables:
                BUCKET_ARN:
                  Fn::GetAtt:
                    - MyBucket
                    - Arn
      """

      assert {:ok, %Graph{} = graph} = CloudFormation.parse(yaml)
      assert length(graph.vertices) == 2

      getatt_deps =
        Enum.filter(graph.edges, fn dep ->
          dep.metadata[:reason] == "get_att"
        end)

      assert length(getatt_deps) >= 1
    end
  end

  describe "parse/2 with multiple resources" do
    test "parses template with multiple resource types" do
      yaml = """
      AWSTemplateFormatVersion: "2010-09-09"
      Description: Multi-resource template
      Resources:
        MyVPC:
          Type: AWS::EC2::VPC
          Properties:
            CidrBlock: 10.0.0.0/16
        MyBucket:
          Type: AWS::S3::Bucket
          Properties:
            BucketName: my-bucket
        MyFunction:
          Type: AWS::Lambda::Function
          Properties:
            FunctionName: my-func
            Runtime: python3.12
            Handler: index.handler
            Role: arn:aws:iam::123456789012:role/role
      """

      assert {:ok, %Graph{} = graph} = CloudFormation.parse(yaml)
      assert length(graph.vertices) == 3

      types = Enum.map(graph.vertices, & &1.type)
      assert :network_vpc_create in types
      assert :storage_bucket_create in types
      assert :function_create in types
    end
  end

  describe "validate/1" do
    test "validates correct CloudFormation template" do
      yaml = """
      AWSTemplateFormatVersion: "2010-09-09"
      Resources:
        MyBucket:
          Type: AWS::S3::Bucket
      """

      assert :ok = CloudFormation.validate(yaml)
    end

    test "returns error for template without Resources section" do
      yaml = """
      AWSTemplateFormatVersion: "2010-09-09"
      Description: No resources
      """

      assert {:error, {:cloudformation_parse_error, _}} = CloudFormation.validate(yaml)
    end

    test "returns error for invalid YAML" do
      yaml = "invalid: [yaml: content"

      assert {:error, _} = CloudFormation.validate(yaml)
    end
  end

  describe "metadata" do
    test "sets graph metadata with source and template version" do
      yaml = """
      AWSTemplateFormatVersion: "2010-09-09"
      Description: Test template
      Resources:
        MyBucket:
          Type: AWS::S3::Bucket
      """

      assert {:ok, %Graph{} = graph} = CloudFormation.parse(yaml)
      assert graph.metadata.source == :cloudformation
      assert graph.metadata.template_version == "2010-09-09"
      assert graph.metadata.description == "Test template"
      assert %DateTime{} = graph.metadata.parsed_at
    end

    test "operation ID contains cfn prefix and logical ID" do
      yaml = """
      AWSTemplateFormatVersion: "2010-09-09"
      Resources:
        MyInstance:
          Type: AWS::EC2::Instance
          Properties:
            InstanceType: t3.micro
            ImageId: ami-12345678
      """

      assert {:ok, %Graph{} = graph} = CloudFormation.parse(yaml)
      op = hd(graph.vertices)
      assert op.id =~ "cfn_"
      assert op.id =~ "MyInstance"
    end

    test "stores DependsOn list in operation metadata" do
      yaml = """
      AWSTemplateFormatVersion: "2010-09-09"
      Resources:
        MyVPC:
          Type: AWS::EC2::VPC
          Properties:
            CidrBlock: 10.0.0.0/16
        MySubnet:
          Type: AWS::EC2::Subnet
          DependsOn: MyVPC
          Properties:
            VpcId: vpc-12345
            CidrBlock: 10.0.1.0/24
      """

      assert {:ok, %Graph{} = graph} = CloudFormation.parse(yaml)

      subnet_op =
        Enum.find(graph.vertices, fn op ->
          op.metadata.logical_id == "MySubnet"
        end)

      assert "MyVPC" in subnet_op.metadata.depends_on
    end
  end

  describe "resource type mapping coverage" do
    test "maps additional AWS resource types" do
      yaml = """
      AWSTemplateFormatVersion: "2010-09-09"
      Resources:
        MyQueue:
          Type: AWS::SQS::Queue
          Properties: {}
        MyTopic:
          Type: AWS::SNS::Topic
          Properties: {}
        MyLogGroup:
          Type: AWS::Logs::LogGroup
          Properties: {}
      """

      assert {:ok, %Graph{} = graph} = CloudFormation.parse(yaml)
      assert length(graph.vertices) == 3

      types = Enum.map(graph.vertices, & &1.type)
      assert :queue_create in types
      assert :notification_topic_create in types
      assert :log_group_create in types
    end

    test "maps unknown resource type to cloudformation_resource" do
      yaml = """
      AWSTemplateFormatVersion: "2010-09-09"
      Resources:
        CustomThing:
          Type: Custom::MyResource
          Properties:
            Foo: bar
      """

      assert {:ok, %Graph{} = graph} = CloudFormation.parse(yaml)
      op = hd(graph.vertices)
      assert op.type == :cloudformation_resource
    end
  end
end
