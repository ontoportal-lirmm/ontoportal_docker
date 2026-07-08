#!/usr/bin/env bash
# Services of the API stack in docker-compose.yml
API_SERVICES="api ncbo_cron redis solr mgrep virtuoso"

setup() {
  echo "[+] Setup API"
  if [ ! -f ".env" ]; then
    cp .env.sample .env
  fi
  source .env
}

status_ok() {
  curl -sSf http://$1:9393 >/dev/null 2>&1
}

logs() {
  docker exec -it api-service tail -f log/production.log
}

reset_data() {
  echo "[+] Removing containers and data volumes"
  docker compose down --volumes --remove-orphans
  # Leftovers from the old layout where containers were started with 'docker compose run'
  docker container rm -f api-service ui-service cron-service >/dev/null 2>&1
}

clean() {
  echo "[+] Cleaning the API"
  reset_data
}

update() {
  echo "[+] Pulling latest images for the API"
  docker compose pull $API_SERVICES
}

stop() {
  echo "[+] Stopping the API"
  docker compose stop $API_SERVICES
}

provision() {
  if [ -z "$1" ]; then
    source .env
    reset_data
    echo "[+] Running Cron provisioning"
    commands=(
        "bin/run_cron.sh 'bundle exec rake user:create[admin,admin@nodomain.org,password]'"
        "bin/run_cron.sh 'bundle exec rake user:adminify[admin]'"
        "bin/run_cron.sh 'bundle exec bin/ncbo_ontology_import --admin-user admin --ontologies $STARTER_ONTOLOGY --from-apikey $OP_APIKEY --from $OP_API_URL'"
        "bin/run_cron.sh 'bundle exec bin/ncbo_ontology_process -o ${STARTER_ONTOLOGY}'"
    )
    for cmd in "${commands[@]}"; do
        echo "[+] Run: $cmd"
        if ! eval "$cmd"; then
            echo "Error: Failed to run provisioning .  $cmd"
            exit 1
        fi
    done
    echo "CRON Setup completed successfully!"
  elif [ "$1" == "--no-provision" ]; then
    echo "[+] Skipping Cron provisioning"
  fi
}

run() {
  echo "[+] Starting the API"
  if ! docker compose up -d api; then
    echo "[-] Error starting the API containers. Exiting..."
    exit 1
  fi

  local HOST_IP='localhost'
  if [ -f "/.dockerenv" ]; then
    # we are inside the container of ontoportal_docker so we have to test the IP of the machine
    docker_host_IP=$(dig +short A host.docker.internal)
    if [ -n "$docker_host_IP" ]; then
      echo "IP of the local machine: $docker_host_IP"
      HOST_IP=$docker_host_IP
    else
      echo "Cannot get the IP address of the host machine, localhost will be used"
    fi
  fi
  source utils/loading_animation.sh "[+] Waiting for the server http://$HOST_IP:9393 to be up..." "http://$HOST_IP:9393" 300

  if status_ok $HOST_IP; then
    echo "[+] API is up and running!"
  else
    echo "[x] Timed out waiting for the server to be up."
    exit 1
  fi
}

start() {
  echo "[+] Running api script"
  setup
  update
  provision "$1"
  run
  if [ $? -ne 0 ]; then
    echo "[-] Error Running API. Exiting..."
    exit 1
  fi
}

usage() {
  echo "Usage: $0 <option>"
  echo "Options:"
  echo "  start      Start the API"
  echo "  stop       Stop the API"
  echo "  logs       View the logs of the API"
  echo "  clean      Stop the appliance and remove all containers and data volumes"
  echo "  update     Update the API containers to the latest version"
  exit 1
}

# Option parser
if [[ $# -eq 0 ]]; then
  usage
fi


case $1 in
  "start")
    start "$2"
    ;;
  "stop")
    stop
    ;;
  "logs")
    logs
    ;;
  "clean")
    clean
    ;;
  "update")
    update
    ;;
  "setup")
    setup
    ;;
  *)
    echo "Invalid option: $1"
    usage
    ;;
esac

exit 0
