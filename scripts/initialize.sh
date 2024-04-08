#!/usr/bin/env bash

pull_start_containers () {
    # Docker pull and start containers
    local MAX_WAIT_SECONDS=60
    local WAIT_INTERVAL=5
    local project="$1"
    local container_name="$2"
    local compose_file="$3"

    while true; do

        printf '\n\n Waiting for Docker container %s to start...\n' "${container_name}"
        if [[ ! "${container_name}" == "proxy" ]]; then
            docker-compose pull && docker-compose up -d
        else
            docker-compose pull && docker-compose -f "${compose_file}" up -d
        fi

        elapsed_seconds=0
        while [ $elapsed_seconds -lt $MAX_WAIT_SECONDS ]; do
            container_status=$(docker ps -f "name=$container_name" --format "{{.Status}}")

            if [[ $container_status == *"Up"* ]] && [[ ! "${container_name}" == "proxy" ]]; then
                printf 'Container %s status: %s \n' "${container_name}" "${container_status}"
                printf 'access the gateway at http://%s.localtest.me' "${project}"
                break
            elif [[ $container_status == *"Up"* ]] && [[ "${container_name}" == "proxy" ]]; then
                sleep $WAIT_INTERVAL
                printf 'Container %s status: %s \n' "${container_name}" "${container_status}"
                break
            fi

            sleep $WAIT_INTERVAL
            elapsed_seconds=$((elapsed_seconds + WAIT_INTERVAL))
        done

        if [ $elapsed_seconds -ge $MAX_WAIT_SECONDS ]; then
            printf 'Timed out waiting for container %s to start. \n' "${container_name}"
            printf 'Container %s status: %s \n' "${container_name}" "${container_status}"
        fi
        
        break
    done
}

printf '\n\n Ignition Project Initialization'
printf '\n ==================================================================== \n'

initialize_project() {
	read -rep $' Enter project name: ' project_name

	# Setup and start Docker for reverse proxy
	# Run a command to check proxy.localtest.me for Traefik dashboard, if its not there then wait 5 seconds and try again
	printf '\n Checking Traefik dashboard at http(s)://proxy.localtest.me/dashboard/#/ \n'

	while true; do
		http_response=$(curl -s -o /dev/null -w "%{http_code}" "http://proxy.localtest.me/dashboard/#/")
		https_response=$(curl -s -o /dev/null -w "%{http_code}" "https://proxy.localtest.me/dashboard/#/")

		if [ "$http_response" == "200" ] || [ "$https_response" == "200" ] || [ "$http_response" == "302" ] || [ "$https_response" == "302" ]; then
			printf '\n Traefik dashboard is up and running! \n'
			break
		else
			printf '\n Traefik Proxy dashboard not accessible. \n'
			install_path="${HOME}"/dg-traefik-proxy/
			echo -n ' Default location is: '"${install_path}"
			read -rep $' Would you like to use this default path (y/n)?' use_default

			case "${use_default}" in
				[yY]* ) 
					mkdir -p "${install_path}";;
				[nN]* )
					install_path=""
					while true; do
						if [ -d "${install_path}" ]; then
							echo "${install_path}"
							ls -al "${install_path}"
							read -rep $'\n\n Would you like to clone the design-group/dg-traefik-proxy to your local PC in this location? (y/n) \n' install_proxy
							case "${install_proxy}" in
								[yY]* )
									break;;
								[nN]* )
									install_path="";;
								* ) 
									printf ' Please answer y or n. \n';;
							esac
						else
							read -rep $'\n Please enter a valid empty folder path to clone into [Format: /home/user/dg-traefik-proxy/]: ' install_path
							if [[ "$install_path" =~ ^(/[^/ ]*)+/?$ ]]; then
								mkdir -p "${install_path}"
							fi
						fi;
					done;;
				* )
					printf ' Please answer y or n. \n'
			esac


			printf ' Cloning design-group/dg-traefik-proxy into %s...\n' "${install_path}"
			if git clone https://github.com/design-group/dg-traefik-proxy.git "${install_path}" ; then
				pull_start_containers "${project_name}" proxy "${install_path}"/docker-compose.yml
				break
			else
				printf ' Failed to clone dg-traefik-proxy. \n'
				printf ' Please check your git credentials and try again, This may require creating a personal access token. \n'
				printf ' For more information, please see: https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry#authenticating-with-a-personal-access-token-classic \n'
			fi;
		fi;
	done

	# Update local files with project name
	printf '\n\n Renaming file %s.code-workspace... \n' "${project_name}"
	mv ./*.code-workspace "${project_name}".code-workspace

	printf ' Updating Traefik compose file and README file with %s. \n' "${project_name}"
	sed -i.bak "s/<project-name>/${project_name}/g" docker-compose.yaml
	sed -i.bak "s/\$project-name/${project_name}/g" README.md
	# Replace line 1 of the README file with the project name
	sed -i.bak "1s/.*/# ${project_name}/" README.md

	if [ -f "docker-compose.yaml" ] && [ -f "docker-compose.yaml.bak" ]; then
		rm docker-compose.yaml.bak
	fi

	if [ -f "README.md" ] && [ -f "README.md.bak" ]; then
		rm README.md.bak
	fi


	mkdir -p ignition-data

	# Write a file to indicate the project has been initialized
	printf '\n\n Writing file to indicate the project has been initialized... \n'
	echo "$project_name" > scripts/.initialized

	# Git
	printf '\n Creating initial commit for repository. \n'
	git add .
	git commit --quiet -m "Initial commit"
}

# If the project has not been initialized, run the initialization script
if [ ! -f scripts/.initialized ]; then
	initialize_project
else 
	project_name=$(cat scripts/.initialized)
	printf '\n\n %s has already been initialized. \n' "${project_name}"
fi

if ! command -v python &> /dev/null; then
	printf '\n python not found, please install... \n'
	exit 1
fi

# Check that the user has pre-commit installed 
if ! command -v pre-commit &> /dev/null; then
	printf '\n Installing pre-commit... \n'
	pip install pre-commit
fi

# Run pre-commit
printf '\n Installing pre-commit in the repo... \n'
pre-commit install -c linting/.pre-commit-config.yaml

# Verify the user has the linting dependencies installed
if ! command -v markdownlint &> /dev/null; then
	printf '\n Markdownlint not found, please install... \n'
	exit 1
fi

if ! command -v shellcheck &> /dev/null; then
	printf '\n shellcheck not found, please install... \n'
	exit 1
fi

if ! command -v yamllint &> /dev/null; then
	printf '\n Installing yamllint... \n'
	pip install yamllint
fi

# Setup and start Docker for Gateway
while true; do
    read -rep $'\n\n Do you want to pull any changes to the Docker image and start the Ignition Gateway container? (y/n) \n' start_container
    case "${start_container}" in
        [yY]* ) 
            pull_start_containers "${project_name}" "${project_name}-gateway-1" ./docker-compose.yaml;
            break;;
        [nN]* ) 
            printf '\n Please run: \n docker compose pull && docker compose up -d'
            printf '\n Once the container is started, in a web browser, access the gateway at http://%s.localtest.me' "${project_name}";
            break;;
        * ) 
            printf ' Please answer y or n.';;
    esac
done

printf '\n\n\n Ignition project initialization finished!'
printf '\n ==================================================================== \n'
