#!/bin/bash

appdata_dir="/opt/appdata"
backup_dir="/opt/to_cloud"

exclude=("rclone")
declare -A tar_flags
tar_flags=(["hawkbot"]="--exclude=**/venv/**" ["swag"]="--exclude=**.sample --exclude=**/geoip2db/**" ["unraider"]="--exclude=**/venv/**")

function update() {

    for i in "${appdata_dir}"/*/docker-compose.yml; do
        compose="docker-compose -f $i"
        fldr="$(echo "${i}" | awk -F/ '{print $--NF}')"
        if [[ "${exclude[*]}" =~ ${fldr} ]]; then continue; fi

        if docker container inspect "${fldr}" >/dev/null 2>&1; then
            hashes=""
            for service in $(${compose} config --services); do
                IFS=: read -r image tag <<<"$(docker inspect --format='{{ index .Config.Image }}' "$service")"
                IFS=* read -r d_hash d_tag <<<"$(docker images --digests --format="{{ .Digest }}*{{ .Tag }}" "$image")"
                if [[ "${tag:="latest"}" == "${d_tag}" ]]; then hashes="${hashes}$image@$d_hash\n"; fi
            done
            printf "%s" "${hashes}" >"${appdata_dir}/${fldr}/current_hashes.txt"
        fi
        logger -p user.info "Started backup for ${fldr}"
        ${compose} pull
        ${compose} down
        tarflags="-C ${appdata_dir}/"
        if [[ "${!tar_flags[*]}" =~ ${fldr} ]]; then tarflags="${tarflags} ${tar_flags[${fldr}]}"; fi
        # shellcheck disable=SC2086
        tar ${tarflags} -cvzf "${backup_dir}/${fldr}.tar.gz" "${fldr}"
        ${compose} up -d
    done
    docker system prune -fa --filter "label=ansible.managed=true"

}

function upload() {

    rclone="docker-compose -f ${appdata_dir}/rclone/docker-compose.yml run rclone -v"

    for comp in "${backup_dir}"/*.tar.gz; do
        ${rclone} move "${comp}" union:BotBox/"$(date --utc +%Y-%m-%d_%H)"/
    done

}

# Check if the function exists
if declare -f "$1" >/dev/null; then
    "$@"
else
    echo "The only valid arguments are update and upload"
    exit 1
fi
