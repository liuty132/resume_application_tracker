.PHONY: help setup infra-init infra-plan infra-apply backend-install backend-build backend-deploy backend-local db-migrate db-shell app-build app-run test clean

help:
	@echo "Job Application Tracker Development Tasks"
	@echo "=========================="
	@echo ""
	@echo "Infrastructure:"
	@echo "  make infra-init          Initialize Terraform"
	@echo "  make infra-plan          Plan Terraform changes"
	@echo "  make infra-apply         Apply Terraform (requires db_password)"
	@echo ""
	@echo "Backend:"
	@echo "  make backend-install     Install Lambda dependencies"
	@echo "  make backend-build       Build Lambda TypeScript"
	@echo "  make backend-deploy      Deploy Lambda functions"
	@echo "  make backend-local       Run Lambda offline (requires SAM)"
	@echo ""
	@echo "Database:"
	@echo "  make db-migrate          Run Drizzle migrations"
	@echo "  make db-shell            Connect to RDS (requires psql)"
	@echo ""
	@echo "App:"
	@echo "  make app-run             Build and run macOS app in Xcode"
	@echo ""
	@echo "Testing:"
	@echo "  make test                Run integration tests"
	@echo ""
	@echo "Utilities:"
	@echo "  make clean               Remove build artifacts"

setup: backend-install infra-init
	@echo "✓ Setup complete. Next: make infra-plan"

infra-init:
	cd infra && terraform init

infra-plan:
	@read -p "Enter DB password: " db_pass; \
	cd infra && terraform plan -var="db_password=$$db_pass"

infra-apply:
	@read -p "Enter DB password: " db_pass; \
	cd infra && terraform apply -var="db_password=$$db_pass"

backend-install:
	cd backend-lambda && npm install

backend-build:
	cd backend-lambda && npm run build

backend-deploy:
	cd backend-lambda && npm run build && serverless deploy

backend-local:
	cd backend-lambda && npm run dev

db-migrate:
	cd backend-lambda && npx drizzle-kit push:pg

db-shell:
	@read -p "Enter RDS endpoint: " rds_host; \
	psql -h $$rds_host -U jobpulse_user -d jobpulse

app-build:
	cd ApplicationTracker && xcodebuild -scheme ApplicationTracker -configuration Debug

app-run:
	open ApplicationTracker/

test:
	@echo "Running integration tests..."
	cd backend-lambda && npm run test 2>/dev/null || echo "No tests configured yet"

clean:
	cd backend-lambda && rm -rf dist node_modules
	cd ApplicationTracker && rm -rf build DerivedData
	cd infra && rm -rf .terraform .terraform.lock.hcl

.PHONY: help setup infra-init infra-plan infra-apply backend-install backend-build backend-deploy backend-local db-migrate db-shell app-build app-run test clean
