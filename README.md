# Docker compose

## Commands

* `docker-compose -f docker-compose.yml up`    # Start all services in foreground
* `docker-compose -f docker-compose.yml up -d` # Start all services in background
* `docker-compose -f docker-compose.yml stop`  # Stop all services
* `docker-compose -f docker-compose.yml down`  # Stop and remove all services

## Folders

* `.shared`   # Shared folder between services, mounted to `/app/shared`
* `agent`     # Agent service configuration
* `nesachain` # NesaChain service configuration
* `db`        # MySQL Database files
* `logs`      # Logs
