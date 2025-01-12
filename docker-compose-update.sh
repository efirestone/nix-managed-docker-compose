# Update the running docker containers to match the Docker compose files in /etc/docker-compose.

set -E
function handle_error {
    local retval=$?
    local line=$1
    echo -e "Failed at $line: $BASH_COMMAND"
    exit $retval
}
trap 'handle_error $LINENO' ERR

echo "Running docker compose script using $DOCKER_BACKEND"

ETC_DIR=/etc/docker-compose

# Find docker compose file for a running container
function compose_file_for_container() {
    local container_id="$1"

    if [ -z "$container_id" ]; then
        echo "Usage: compose_file_for_container <container_name>"
        return 1
    fi

    # Inspect the container to find the Compose project directory and file
    compose_dir=$($DOCKER_BACKEND inspect "$container_id" \
        --format='{{ index .Config.Labels "com.docker.compose.project.working_dir" }}')
    compose_file=$($DOCKER_BACKEND inspect "$container_id" \
        --format='{{ index .Config.Labels "com.docker.compose.project.config_files" }}')

    # The config_files field sometimes includes the complete path, and sometimes just includes the compose YAML file name
    if [ $compose_file == $compose_dir* ]; then
        # The path doesn't start with the directory, so combine them.
        compose_file="$compose_dir/$compose_file"
    fi

    if [ -f "$compose_file" ]; then
        real_path=$(realpath "$compose_file")
        echo "$real_path"
    fi
}

# Find the list of docker compose files for all currently-running containers.
function collect_compose_files_for_running_containers() {
    # Get the list of all running container IDs
    local all_containers=$($DOCKER_BACKEND ps -q)
    local compose_files=()

    for container_id in $all_containers; do
        compose_files+=($(compose_file_for_container "$container_id"))
    done

    # Remove duplicates
    IFS=" " read -r -a compose_files <<< "$(tr ' ' '\n' <<< "${compose_files[@]}" | sort -u | tr '\n' ' ')"

    local -n result=$1
    result=$compose_files
}

# Find the docker compose files which should currently be installed (but may not be quite yet).
function collect_current_compose_files() {
    # Find the full paths to all current docker-compose files.
    local compose_files=()

    while IFS= read -r -d $'\0' file; do
        real_path=$(realpath "$file")
        compose_files+=("$real_path")
    done < <(find "$ETC_DIR" -regex '.*/\(compose\|docker-compose\|container-compose\)\.ya?ml' -print0)

    local -n result=$1
    result=$compose_files
}

declare -a current_compose_files
collect_current_compose_files current_compose_files

declare -a compose_files_for_running_containers
collect_compose_files_for_running_containers compose_files_for_running_containers

stale_compose_files=($(comm -13 <(printf '%s\n' "${current_compose_files[@]}" | LC_ALL=C sort) <(printf '%s\n' "${compose_files_for_running_containers[@]}" | LC_ALL=C sort)))

# Spin down any services from compose files that have been removed.
for compose_file in ${stale_compose_files[@]}; do
    echo "Unloading: $compose_file"
    $DOCKER_BACKEND compose --file $compose_file down
done

# Spin up services for the current compose files.
for compose_file in ${current_compose_files[@]}; do
    echo "Loading: $compose_file"
    $DOCKER_BACKEND compose --file $compose_file up --detach
done
