#!/bin/bash

echo "==================================================="
echo "INICIANDO DESPLIEGUE SERVERLESS: ETHICALHACKIN"
echo "==================================================="

# --- VARIABLES GLOBALES ---
export AWS_REGION="us-east-1"
export ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export REPO="ethicalhackin"
export CLUSTER="ethicalhackin-cluster"
export APP_SVC="ethicalhackin-svc"
export EXEC_ROLE_ARN="arn:aws:iam::$ACCOUNT:role/ecsTaskExecutionRole"
export AZ1="${AWS_REGION}a"
export AZ2="${AWS_REGION}b"

# Asegurar rol de servicio de ECS
aws iam create-service-linked-role --aws-service-name ecs.amazonaws.com > /dev/null 2>&1

echo "   -> Eliminando versiones locales previas de $REPO:1.0 (si existen)..."
docker rmi -f $REPO:1.0 > /dev/null 2>&1

echo "   -> Construyendo la imagen desde la carpeta './sitio-web'..."
docker build --no-cache -t $REPO:1.0 ../sitio-web


# FASE 1: PUBLICACIÓN EN AMAZON ECR
echo "1. Creando repositorio en ECR..."
aws ecr create-repository --repository-name $REPO --region $AWS_REGION > /dev/null 2>&1

echo "2. Autenticando Docker con AWS ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ACCOUNT.dkr.ecr.$AWS_REGION.amazonaws.com

export IMG=$ACCOUNT.dkr.ecr.$AWS_REGION.amazonaws.com/$REPO:1.0

echo "3. Etiquetando y subiendo imagen..."
docker tag $REPO:1.0 $IMG
docker push $IMG



# FASE 2: RED Y BALANCEADOR (ALB)
echo "4. Creando VPC y red Multi-AZ..."
export VPC_ID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --query 'Vpc.VpcId' --output text)
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames

export IGW_ID=$(aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID

export RT_ID=$(aws ec2 create-route-table --vpc-id $VPC_ID --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --route-table-id $RT_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID > /dev/null

export SUBNET_1=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.1.0/24 --availability-zone $AZ1 --query 'Subnet.SubnetId' --output text)
aws ec2 modify-subnet-attribute --subnet-id $SUBNET_1 --map-public-ip-on-launch
aws ec2 associate-route-table --route-table-id $RT_ID --subnet-id $SUBNET_1 > /dev/null

export SUBNET_2=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.2.0/24 --availability-zone $AZ2 --query 'Subnet.SubnetId' --output text)
aws ec2 modify-subnet-attribute --subnet-id $SUBNET_2 --map-public-ip-on-launch
aws ec2 associate-route-table --route-table-id $RT_ID --subnet-id $SUBNET_2 > /dev/null



# FASE 3: SECURITY GROUP, ALB Y TARGET GROUP
echo "5. Creando Security Group..."
export SG_ID=$(aws ec2 create-security-group --group-name "ethicalhackin-ecs-sg" --description "SG Fargate" --vpc-id $VPC_ID --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 80 --cidr 0.0.0.0/0 > /dev/null



# FASE 4: ALB Y TARGET GROUP
echo "6. Creando Application Load Balancer y Target Group..."
export ALB_ARN=$(aws elbv2 create-load-balancer --name ethicalhackin-alb --subnets $SUBNET_1 $SUBNET_2 --security-groups $SG_ID --query 'LoadBalancers[0].LoadBalancerArn' --output text)
echo "Esperando unos segundos a que el ALB esté disponible..."
aws elbv2 wait load-balancer-available --load-balancer-arns $ALB_ARN



# Creación del Target Group y Listener
export TG_ARN=$(aws elbv2 create-target-group --name ethicalhackin-tg --protocol HTTP --port 80 --vpc-id $VPC_ID --target-type ip --query 'TargetGroups[0].TargetGroupArn' --output text)
export LISTENER_ARN=$(aws elbv2 create-listener  --load-balancer-arn $ALB_ARN --protocol HTTP --port 80 --default-actions Type=forward,TargetGroupArn=$TG_ARN --query 'Listeners[0].ListenerArn' --output text)
export ALB_DNS=$(aws elbv2 describe-load-balancers  --load-balancer-arns $ALB_ARN  --query 'LoadBalancers[0].DNSName'  --output text)



# FASE 5: ORQUESTACIÓN EN ECS FARGATE
echo "7. Creando Clúster ECS y Task Definition..."
aws ecs create-cluster --cluster-name $CLUSTER > /dev/null

cat <<EOF > task-def.json
{
  "family": "ethicalhackin-task",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "executionRoleArn": "$EXEC_ROLE_ARN",
  "containerDefinitions": [
    {
      "name": "web",
      "image": "$IMG",
      "portMappings": [{"containerPort": 80, "hostPort": 80, "protocol": "tcp"}],
      "essential": true
    }
  ]
}
EOF

aws ecs register-task-definition --cli-input-json file://task-def.json > /dev/null


echo "8. Desplegando Servicio en Fargate..."
aws ecs create-service  --cluster $CLUSTER  --service-name $APP_SVC  --task-definition ethicalhackin-task  --desired-count 2  --launch-type FARGATE --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_1,$SUBNET_2],
  securityGroups=[$SG_ID],assignPublicIp=ENABLED}"  --load-balancers "targetGroupArn=$TG_ARN,containerName=web,containerPort=80" > /dev/null


echo "9. Esperando a que las tareas de Fargate estén estables y registradas en el ALB (esto puede tomar 2-3 minutos)..."
aws ecs wait services-stable --cluster $CLUSTER --services $APP_SVC

echo "==================================================="
echo "¡DESPLIEGUE FINALIZADO EXITOSAMENTE!"
echo "Tus contenedores están arrancando. Puedes acceder a:"
echo "URL del sitio: http://$ALB_DNS"
echo "==================================================="