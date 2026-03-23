#!/bin/bash

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}JobPulse Setup Verification${NC}"
echo "=============================="
echo ""

# Check prerequisites
echo "Checking prerequisites..."

# Check Node.js
if command -v node &> /dev/null; then
    NODE_VERSION=$(node -v)
    echo -e "${GREEN}✓${NC} Node.js $NODE_VERSION"
else
    echo -e "${RED}✗${NC} Node.js not found (required)"
    exit 1
fi

# Check npm
if command -v npm &> /dev/null; then
    NPM_VERSION=$(npm -v)
    echo -e "${GREEN}✓${NC} npm $NPM_VERSION"
else
    echo -e "${RED}✗${NC} npm not found"
    exit 1
fi

# Check Terraform
if command -v terraform &> /dev/null; then
    TERRAFORM_VERSION=$(terraform -version | head -1)
    echo -e "${GREEN}✓${NC} $TERRAFORM_VERSION"
else
    echo -e "${YELLOW}⚠${NC} Terraform not found (optional for local development)"
fi

# Check AWS CLI
if command -v aws &> /dev/null; then
    AWS_VERSION=$(aws --version 2>&1 | head -1)
    echo -e "${GREEN}✓${NC} $AWS_VERSION"
else
    echo -e "${YELLOW}⚠${NC} AWS CLI not found (optional)"
fi

# Check Xcode
if command -v xcode-select &> /dev/null; then
    XCODE_PATH=$(xcode-select -p 2>/dev/null)
    echo -e "${GREEN}✓${NC} Xcode installed at $XCODE_PATH"
else
    echo -e "${YELLOW}⚠${NC} Xcode not found (required for macOS app)"
fi

echo ""
echo "Checking project structure..."

# Check directories
REQUIRED_DIRS=(
    "JobPulse-macOS"
    "backend-lambda"
    "infra"
)

for dir in "${REQUIRED_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        echo -e "${GREEN}✓${NC} $dir"
    else
        echo -e "${RED}✗${NC} $dir not found"
    fi
done

echo ""
echo "Checking Lambda dependencies..."

# Check Lambda package.json
if [ -f "backend-lambda/package.json" ]; then
    echo -e "${GREEN}✓${NC} backend-lambda/package.json"
    if [ -d "backend-lambda/node_modules" ]; then
        echo -e "${GREEN}✓${NC} Dependencies installed"
    else
        echo -e "${YELLOW}⚠${NC} Run 'cd backend-lambda && npm install' to install dependencies"
    fi
else
    echo -e "${RED}✗${NC} backend-lambda/package.json not found"
fi

echo ""
echo "Checking Lambda handlers..."

HANDLERS=(
    "backend-lambda/src/handlers/presign.ts"
    "backend-lambda/src/handlers/postJob.ts"
    "backend-lambda/src/handlers/getJobs.ts"
)

for handler in "${HANDLERS[@]}"; do
    if [ -f "$handler" ]; then
        echo -e "${GREEN}✓${NC} $(basename $handler)"
    else
        echo -e "${RED}✗${NC} $handler not found"
    fi
done

echo ""
echo "Checking Swift source files..."

SWIFT_FILES=(
    "JobPulse-macOS/JobPulseApp.swift"
    "JobPulse-macOS/AppState.swift"
    "JobPulse-macOS/Models/PendingJob.swift"
    "JobPulse-macOS/Views/MenuBarView.swift"
    "JobPulse-macOS/Views/URLInputView.swift"
    "JobPulse-macOS/Views/PendingJobRow.swift"
    "JobPulse-macOS/Services/AuthService.swift"
    "JobPulse-macOS/Services/WebViewFetcher.swift"
    "JobPulse-macOS/Services/JobAPIService.swift"
)

for file in "${SWIFT_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo -e "${GREEN}✓${NC} $(basename $file)"
    else
        echo -e "${RED}✗${NC} $file not found"
    fi
done

echo ""
echo "Checking Terraform configuration..."

TF_FILES=(
    "infra/main.tf"
    "infra/variables.tf"
    "infra/outputs.tf"
)

for file in "${TF_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo -e "${GREEN}✓${NC} $(basename $file)"
    else
        echo -e "${RED}✗${NC} $file not found"
    fi
done

echo ""
echo "Checking configuration files..."

CONFIG_FILES=(
    "backend-lambda/.env.example"
    "backend-lambda/tsconfig.json"
    "backend-lambda/drizzle.config.ts"
    "backend-lambda/serverless.yml"
    "Makefile"
    "README.md"
)

for file in "${CONFIG_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo -e "${GREEN}✓${NC} $file"
    else
        echo -e "${RED}✗${NC} $file not found"
    fi
done

echo ""
echo "=============================="
echo -e "${GREEN}Setup verification complete!${NC}"
echo ""
echo "Next steps:"
echo "1. Copy backend-lambda/.env.example to backend-lambda/.env"
echo "2. Update environment variables in backend-lambda/.env"
echo "3. Run 'make infra-init' to initialize Terraform"
echo "4. Run 'make infra-plan' to preview infrastructure changes"
echo "5. Run 'make infra-apply' to provision AWS resources"
echo "6. Run 'make backend-deploy' to deploy Lambda functions"
echo "7. Open JobPulse-macOS in Xcode and configure Firebase"
echo ""
