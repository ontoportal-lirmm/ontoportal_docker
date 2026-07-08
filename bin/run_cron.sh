#!/usr/bin/env bash

start() {
	local env_path='.env'
	local bash_cmd=$1

	echo "[+] Running cron script"

	if [ ! -f "$env_path" ]; then
		echo "[-] Error: Missing required configurations. Please provide your .env file"
		exit 1
	fi

	source "$env_path"

	docker_run_cmd="docker compose run --rm ncbo_cron bash -c \"$bash_cmd\""

	echo "[+] Starting the CRON"
	eval "$docker_run_cmd"

	if [ $? -ne 0 ]; then
		echo "[-] Error in run_cron function. Exiting..."
		exit 1
	fi

	echo "[+] The CRON is running successfully."
}

start "$1"
