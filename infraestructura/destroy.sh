#!/bin/bash

export CLUSTER="ethicalhackin-cluster"
export APP_SVC="ethicalhackin-svc"
export ALB_NAME="ethicalhackin-alb"
export TG_NAME="ethicalhackin-tg"
export REPO="ethicalhackin"

echo "==================================================="
echo "INICIANDO DESTRUCCIÓN DE RECURSOS: ETHICALHACKIN"
echo "==================================================="

echo "1. Eliminando Servicio ECS ($APP_SVC)..."
aws ecs delete-service --cluster $CLUSTER --service $APP_SVC --force > /dev/null
echo "   Esperando 60 segundos para evitar un error de clúster..."
sleep 60

echo "2. Eliminando Clúster ECS ($CLUSTER)..."
aws ecs delete-cluster --cluster $CLUSTER > /dev/null

echo "3. Eliminando Application Load Balancer ($ALB_NAME)..."
export ALB_ARN=$(aws elbv2 describe-load-balancers --names $ALB_NAME --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null)
if [ -n "$ALB_ARN" ]; then
    aws elbv2 delete-load-balancer --load-balancer-arn $ALB_ARN
    echo "   Esperando a que AWS destruya el ALB..."
    aws elbv2 wait load-balancers-deleted --load-balancer-arns $ALB_ARN
    
    echo "   Dando 30 segundos extra de margen para desconectar el Target Group..."
    sleep 30
fi

echo "4. Eliminando Target Group ($TG_NAME)..."
export TG_ARN=$(aws elbv2 describe-target-groups --names $TG_NAME --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null)
if [ -n "$TG_ARN" ]; then
    aws elbv2 delete-target-group --target-group-arn $TG_ARN
fi

echo "5. Eliminando Repositorio ECR ($REPO)..."
aws ecr delete-repository --repository-name $REPO --force > /dev/null

echo "6. Buscando la VPC del laboratorio..."
# Intento 1: Buscar a través del Security Group
export VPC_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=ethicalhackin-ecs-sg" --query 'SecurityGroups[0].VpcId' --output text 2>/dev/null)

# Intento 2 (Respaldo): Si el SG ya no existe, buscar por el bloque de IP (CIDR) que usamos en deploy.sh
if [ -z "$VPC_ID" ] || [ "$VPC_ID" == "None" ]; then
    export VPC_ID=$(aws ec2 describe-vpcs --filters "Name=cidr,Values=10.0.0.0/16" --query 'Vpcs[?IsDefault==`false`].VpcId | [0]' --output text 2>/dev/null)
fi

if [ -n "$VPC_ID" ] && [ "$VPC_ID" != "None" ] && [ "$VPC_ID" != "null" ]; then
    echo "   VPC detectada: $VPC_ID"
    
    echo "7. Eliminando Security Group..."
    export SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=ethicalhackin-ecs-sg" "Name=vpc-id,Values=$VPC_ID" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)
    if [ -n "$SG_ID" ] && [ "$SG_ID" != "None" ]; then
        aws ec2 delete-security-group --group-id $SG_ID 2>/dev/null
    fi

    echo "8. Eliminando Subredes..."
    export SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[*].SubnetId' --output text)
    for SUBNET in $SUBNETS; do
        aws ec2 delete-subnet --subnet-id $SUBNET 2>/dev/null
    done

    echo "9. Desacoplando y eliminando Internet Gateway..."
    export IGW_ID=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --query 'InternetGateways[0].InternetGatewayId' --output text)
    if [ -n "$IGW_ID" ] && [ "$IGW_ID" != "None" ]; then
        aws ec2 detach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID 2>/dev/null
        aws ec2 delete-internet-gateway --internet-gateway-id $IGW_ID 2>/dev/null
    fi

    echo "10. Eliminando Tablas de Ruteo personalizadas..."
    export RT_IDS=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' --output text)
    for RT in $RT_IDS; do
        aws ec2 delete-route-table --route-table-id $RT 2>/dev/null
    done

    echo "11. Eliminando la VPC principal..."
    aws ec2 delete-vpc --vpc-id $VPC_ID 2>/dev/null
    echo "   VPC eliminada."
else
    echo "   [!] No se pudo detectar la VPC. Es posible que ya esté eliminada."
fi

echo "¡LIMPIEZA COMPLETADA CON ÉXITO!"
