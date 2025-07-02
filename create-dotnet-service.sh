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
cat > src/Dockerfile <<EOF
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

echo "Add Helm and k8s files"
mkdir .helm
cd .helm

echo "Opening project in Visual Studio..."
start "$PROJECT_NAME.sln"

read -n 1 -s -r -p "Press any key to exit..."
echo
