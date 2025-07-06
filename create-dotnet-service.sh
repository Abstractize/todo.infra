#!/bin/bash
if [ $# -eq 0 ]; then
    echo "Usage: $0 <project-name>"
    exit 1
fi

PROJECT_NAME="$1"

cd ..

dotnet new sln -o $PROJECT_NAME

cd $PROJECT_NAME

echo "Creating project names array..."
projects=("API" "Models" "Managers" "Data" "Extensions" "Services")

echo "Creating projects..."
mkdir src

for proj in "${projects[@]}"; do
    if [ "$proj" == "API" ]; then
        echo "Creating Web API project: $proj"
        dotnet new webapi -n "$proj" -o "src/$proj"
    else
        echo "Creating class library project: $proj"
        dotnet new classlib -n "$proj" -o "src/$proj"
        rm "src/$proj/Class1.cs"
    fi
    echo "Adding $proj to solution"
    dotnet sln add "src/$proj"
done

echo "Creating tests directory..."
mkdir tests

for proj in "${projects[@]}"; do
    test_proj="${proj}.Tests"
    echo "Creating test project: $test_proj"
    dotnet new xunit -n "$test_proj" -o "tests/$test_proj"
    rm "tests/$test_proj/UnitTest1.cs"
    echo "Adding $test_proj to solution"
    dotnet sln add "tests/$test_proj"
done


echo "Initializing git repository..."
dotnet new gitignore
git init

echo "Adding Dockerfile"
cat > Dockerfile <<EOF
FROM mcr.microsoft.com/dotnet/aspnet:9.0 AS base
WORKDIR /app
EXPOSE 8080

FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src
COPY src .
WORKDIR /src/API
RUN dotnet restore
RUN dotnet publish -c Release -o /app/publish

FROM base AS final
WORKDIR /app
COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "API.dll"]
EOF

echo "Adding Dockerfile.local"
cat > Dockerfile.local <<EOF
FROM mcr.microsoft.com/dotnet/sdk:9.0 AS dev

WORKDIR /app

RUN apt-get update \
    && apt-get install -y unzip \
    && mkdir -p /vsdbg \
    && curl -sSL https://aka.ms/getvsdbgsh | bash /dev/stdin -v latest -l /vsdbg

WORKDIR /src
COPY src .

WORKDIR /src/API
RUN dotnet restore

EXPOSE 8080

CMD ["dotnet", "watch", "run", "--no-launch-profile", "--urls=http://0.0.0.0:8080"]
EOF

echo "Add Helm and k8s files"
mkdir .helm
cd .helm

# Create Helm chart
helm create $PROJECT_NAME
rm -rf $PROJECT_NAME/templates/tests

mv $PROJECT_NAME/* .
mv $PROJECT_NAME/.* . 2>/dev/null || true
rmdir $PROJECT_NAME

# Modify Chart.yaml
cat > Chart.yaml <<EOF
apiVersion: v2
name: $PROJECT_NAME
description: A Helm chart for deploying $PROJECT_NAME API
type: application
version: 0.1.0
appVersion: "1.0"
EOF

# Create values.yaml
cat > values.yaml <<EOF
replicaCount: 1

image:
  repository: $PROJECT_NAME
  pullPolicy: IfNotPresent
  tag: "latest"

service:
  type: ClusterIP
  port: 80

ingress:
  enabled: false

resources: {}

nodeSelector: {}

tolerations: []

affinity: {}
EOF

# Create deployment.yaml
cat > templates/deployment.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}-api
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app: {{ .Release.Name }}-api
  template:
    metadata:
      labels:
        app: {{ .Release.Name }}-api
    spec:
      containers:
        - name: api
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          ports:
            - containerPort: 8080
EOF

# Create service.yaml
cat > templates/service.yaml <<EOF
apiVersion: v1
kind: Service
metadata:
  name: {{ .Release.Name }}-api
spec:
  type: {{ .Values.service.type }}
  ports:
    - port: {{ .Values.service.port }}
      targetPort: 8080
  selector:
    app: {{ .Release.Name }}-api
EOF

cd ..

echo "Opening project..."

if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
    start "$PROJECT_NAME.sln"
elif command -v code &> /dev/null; then
    code .
else
    echo "Could not detect Visual Studio or VS Code. Please open the project manually."
fi

read -n 1 -s -r -p "Press any key to exit..."
echo
