#!/bin/bash

appdata_dir="/opt/appdata"
backup_dir="/opt/to_cloud"

exclude=("rclone traefik")
declare -A tar_flags
tar_flags=(["hawkbot"]="--exclude=**/venv/** --exclude=**/Downloader/lib/**" ["orgbot"]="--exclude=**/venv/** --exclude=**/Downloader/lib/**" ["swag"]="--exclude=**.sample --exclude=**/geoip2db/** --exclude=**/dns-conf/**" ["unraider"]="--exclude=**/venv/** --exclude=**/Downloader/lib/**" ["grafana"]="--exclude=**/plugins/**")

function update() {

    for i in "${appdata_dir}"/*/docker-compose.yml; do
        compose="docker-compose -f $i"
        fldr="$(echo "${i}" | awk -F/ '{print $--NF}')"
        if [[ "${exclude[*]}" =~ ${fldr} ]]; then continue; fi

        if docker container inspect "${fldr}" >/dev/null 2>&1; then
            hashes=""
            for service in $(${compose} config --services); do
                IFS=: read -r image tag <<<"$(docker inspect --format='{{ "{{ index .Config.Image }}" }}' "$service")"
                IFS=* read -r d_hash d_tag <<<"$(docker images --digests --format="{{ "{{ .Digest }}*{{ .Tag }}" }}" "$image")"
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

function migrate() {

    for i in "${appdata_dir}"/*/docker-compose.yml; do
        compose="docker-compose -f $i"
        fldr="$(echo "${i}" | awk -F/ '{print $--NF}')"
        ${compose} down
        tarflags="-C ${appdata_dir}/"
        # shellcheck disable=SC2086
        tar ${tarflags} -pcvzf "${backup_dir}/${fldr}.tar.gz"
        ${compose} up -d
    done

    rclone="docker run --rm -i --name rclone -e RCLONE_CONFIG=/config/rclone.conf --user 1000:1000 -e TZ=Etc/UTC -v /opt/to_cloud:/opt/to_cloud -v /opt/appdata/rclone/config:/config rclone/rclone -v"

    for comp in "${backup_dir}"/*.tar.gz; do
        ${rclone} move "${comp}" rost:BotBox/migrate/
    done

}

function restore() {

    rclone="docker run --rm -i --name rclone -e RCLONE_CONFIG=/config/rclone.conf --user 1000:1000 -e TZ=Etc/UTC -v /home/roxedus/restore:/home/roxedus/restore -v /opt/appdata/rclone/config:/config rclone/rclone -v"

    ${rclone} copy rost:BotBox/migrate/ /home/roxedus/restore/ --create-empty-src-dirs

    for i in /home/roxedus/restore/*; do
        tarflags="-C ${appdata_dir}/"
        # shellcheck disable=SC2086
        tar -zxvf "${i}" ${tarflags}
    done

}


function pullio() {

    fldr="$(basename "$PULLIO_COMPOSE_WORKDIR")"
    echo "$fldr: Backing up container..."
    if [[ "${exclude[*]}" =~ ${fldr} ]]; then return; fi
    tarflags="-C ${appdata_dir}/"
    if [[ "${!tar_flags[*]}" =~ ${fldr} ]]; then tarflags="${tarflags} ${tar_flags[${fldr}]}"; fi
    echo -n "$PULLIO_OLD_VERSION" > "${appdata_dir}/${fldr}/opencontainer.txt"
    sleep 2
    # shellcheck disable=SC2086
    tar ${tarflags} -cvzf "${backup_dir}/${fldr}.tar.gz" "${fldr}"

}

function upload() {

    rclone="docker run --rm -i --name rclone -e RCLONE_CONFIG=/config/rclone.conf --user 1000:1000 -e TZ=Etc/UTC -v /opt/to_cloud:/opt/to_cloud -v /opt/appdata/rclone/config:/config rclone/rclone -v"

    ${rclone} ls rost:/BotBox >/dev/null && curl -fsS -m 10 --retry 5 -o /dev/null "https://hc-ping.com/{{ secret_healtchecks.pullio }}"

    for comp in "${backup_dir}"/*.tar.gz; do
        ${rclone} move "${comp}" rost:BotBox/"$(date --utc +%Y-%m-%d_%H)"/
    done

}

function reconnect() {

    rclone="docker run --rm -i --name rclone -e RCLONE_CONFIG=/config/rclone.conf --user 1000:1000 -e TZ=Etc/UTC -v /opt/appdata/rclone/config:/config rclone/rclone -v"

    ${rclone} config reconnect rost:

}


# Check if the function exists
if declare -f "$1" >/dev/null; then
    "$@"
else
    echo "The only valid arguments are update, upload and pullio"
    exit 1
fi
