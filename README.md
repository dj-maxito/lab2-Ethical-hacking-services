# Despliegue Serverless en AWS ECS Fargate - Ethical Hacking Services (Lab 2)
Max Coñoman y Benjamin Uribe

Bienvenido al repositorio de infraestructura y despliegue del MVP para **Ethical Hacking Services**. Este proyecto automatiza la creación de una arquitectura en alta disponibilidad usando **Amazon ECS sobre Fargate**, un **Application Load Balancer (ALB)** y **Amazon ECR**, gestionado enteramente mediante **AWS CLI**.

## Estructura del Proyecto

El proyecto sigue el principio de separación de responsabilidades y está organizado de la siguiente manera:

* **`sitio-web/`**: Contiene el código fuente de la aplicación web y su respectivo `Dockerfile` optimizado (basado en Nginx).
* **`infraestructura/`**: Contiene los scripts automatizados de Bash (`deploy.sh` y `destroy.sh`) encargados del aprovisionamiento y destrucción de toda la infraestructura en la nube de AWS.

## Requisitos Previos

Antes de ejecutar el despliegue de la infraestructura, asegúrate de cumplir con lo siguiente:

1.  **Docker Desktop** abierto y ejecutándose en tu equipo local.
2.  **AWS CLI** instalado y debidamente configurado (`aws configure`) con credenciales activas.
3.  **Terminal Bash** (Git Bash, WSL en Windows, o terminal nativa en Linux/macOS).
4.  **Importante (Rol IAM):** Este script asume que la cuenta de AWS ya posee el rol `ecsTaskExecutionRole` activo. Si despliegas en una cuenta personal nueva, debes crear este rol previamente para que Fargate tenga permisos de descargar la imagen desde ECR. *(En cuentas de AWS Academy este rol suele venir por defecto)*.
5.  **Número de cuenta AWS:** Al momento de crear el repositorio en ECR, es posible que necesites ajustar tu número de cuenta de AWS dentro del archivo `deploy.sh` según la configuración requerida.

## Guía de Uso y Despliegue

Sigue estos pasos para levantar y luego limpiar la infraestructura completa:

### 1. Preparar el entorno

Clona este repositorio en tu máquina local y navega a la carpeta de infraestructura:

```bash```
cd infraestructura

### 2. Otorgar permisos de ejecución
Solo es necesario hacer este paso una vez para que los scripts puedan ejecutarse en tu terminal.

```Bash```
chmod +x deploy.sh destroy.sh
### 3. Ejecutar el despliegue
Inicia el proceso automatizado. El script construirá la imagen de Docker, la subirá a ECR, configurará la red privada (VPC Multi-AZ), el balanceador de carga y levantará los contenedores en Fargate. Al finalizar, la terminal te entregará la URL pública (DNS del ALB) para acceder a la web.

```Bash```
./deploy.sh
(Alternativa: bash deploy.sh)

### 4. Limpieza de recursos
Para evitar cobros innecesarios en AWS, una vez finalizado el laboratorio asegúrate de destruir toda la infraestructura creada. Este script eliminará los servicios ECS, el clúster, el ALB, los grupos de seguridad y la red VPC.

```Bash```
./destroy.sh
(Alternativa: bash destroy.sh)
