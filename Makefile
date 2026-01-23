.PHONY: up down reset migrate seed psql test

up:
	docker compose up -d db

down:
	docker compose down

reset:
	docker compose down -v
	docker compose up -d db

migrate:
	docker compose run --rm flyway

seed:
	./scripts/seed.sh

psql:
	./scripts/psql.sh

test:
	./scripts/test.sh
