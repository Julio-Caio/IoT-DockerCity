#!/bin/bash

# --------------- infra-up  -----------------------
NAME_REPO="iot-dockercity"
NAME_SCRIPT="INFRA-UP!"
VERSION="1.3.1"

# Owner: Júlio Caio
# Date: 24/08/2025
# Last Modified: 29/08/2025
# Name: infra-up
# Location: <REPOSITORY>/run.sh
# -------------------------------------------------
HELP="\nUSO: ./run.sh [-h]
#
#
#	 -h // --help
#	 -cl // --clean: Remove quaisquer imagens Docker
#	 -V // versão do script
#   	 -a // --all:  aqui ele executará todas as funções
#        -m // --monit  subir containers de monitoramento
#        -d // --devices subir containers dos dispositivos emulados
#        -c // --create  criar rotas dentro do container
#        -i // --infra levantar rede mininet
"

################### VARIABLES ################################
#
#================== GLOBAL ###################################
BASE=${PWD}
PATH_MONIT_CONTROLLER="${BASE}/stack-infra/monitoramento"
PATH_BROKER_FILES="${BASE}/devices"
PATH_MININET_FILES="${BASE}/stack-infra/mininet"

CHECKING_NET=$(docker network ls | awk '{print $2}' | grep -E "brteste*")
FIGLET_NAME=$(figlet ${NAME_SCRIPT})

BRTESTE01_RANGE="172.18.0.0/24"
BRTESTE02_RANGE="172.19.0.0"

BRTESTE01_DEVICES=(esp32-p1 edge-vision-p2 ops243-p3 broker_mosquitto)
BRTESTE02_DEVICES=(grafana prometheus)

# Ajuste aqui os gateways reais configurados pelo linuxrouter.py
GW_BRTESTE01="172.18.0.10"
GW_BRTESTE02="172.19.0.10"

#================== FLAGS  ==================================#

F_COLORED=0 #true: 1 or false: 0
F_CONFIRM=0
F_IS_ROOT=1
F_CLEANUP_IMAGES=0
F_PORTAINER_INSTALL=0
F_IS_NET_CREATED=0

#================ CHECKING OPTIONS =================================#
# Define a cor com base no suporte do terminal

if [[ -t 1 ]]; then
    declare -A COLORS=(
        [RED]='\e[31m'
        [GREEN]='\e[1;32m'
        [YELLOW]='\e[33m'
        [BLUE]='\e[34m'
        [MAGENTA]='\e[35m'
        [CYAN]='\e[1;36m'
        [WHITE]='\e[37m'
        [NC]='\e[0m'
    )
fi

log_info() {
    echo -e "${COLORS[CYAN]}[INFO]${COLORS[NC]} $1"
}

log_warn() {
    echo -e "${COLORS[YELLOW]}[WARN]${COLORS[NC]} $1"
}

log_error() {
    echo -e "${COLORS[RED]}[ERRO]${COLORS[NC]} $1" >&2
}

log_success() {
    echo -e "${COLORS[GREEN]}[OK]${COLORS[NC]} $1"
}

check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        log_error "Execute o script como root."
        exit 1
    fi
}

#############################################################
                #   Functions
#############################################################

set -e  # parar se algum comando falhar

### limpar imagens docker antigas ou para atualizar versão ######

cleanup_images(){
	log_warn "CLEANING IMAGES DOCKER..."
  	docker rmi -f $(docker images | awk '{print $3}' | grep -v "IMAGE")
}

create_docker_networks() {
    log_info "Verificando se as redes Docker 'brteste01' e 'brteste02' existem..."
    if ! docker network ls | grep -q 'brteste01'; then
        log_info "Rede 'brteste01' não encontrada. Criando..."
        docker network create --subnet=${BRTESTE01_RANGE} brteste01
        log_success "Rede 'brteste01' criada."
    else
        log_warn "Rede 'brteste01' já existe."
    fi

    if ! docker network ls | grep -q 'brteste02'; then
        log_info "Rede 'brteste02' não encontrada. Criando..."
        docker network create --subnet=${BRTESTE02_RANGE} brteste02
        log_success "Rede 'brteste02' criada."
    else
        log_warn "Rede 'brteste02' já existe."
    fi
}

stop_containers() {
    log_info "Stopping Prometheus and Grafana containers..."
    docker-compose -f ${PATH_MONIT_CONTROLLER}/docker-compose.yml down

    log_info "Stopping MQTT broker and IoT devices containers..."
    docker-compose -f ${PATH_BROKER_FILES}/docker-compose.yml down
}

start_observability() {
    log_info "Starting Prometheus and Grafana..."
    docker-compose -f ${PATH_MONIT_CONTROLLER}/docker-compose.yml up -d
}

start_devices() {
    log_info "Starting MQTT broker and IoT devices..."
    docker-compose -f ${PATH_BROKER_FILES}/docker-compose.yml up -d
}

start_mininet() {
    log_info "Starting Mininet router..."
    cd ${PATH_MININET_FILES}
    if ! sudo python3 ./linuxrouter.py; then
        log_warn "Mininet failed. Checking for process using port 6653..."

        PID=$(sudo lsof -t -i:6653)
        if [ -n "$PID" ]; then
            echo "[INFO] Killing process $PID on port 6653..."
            sudo kill -9 $PID
            sleep 2
	    log_info "Retrying Mininet..."
            sudo python3 ${PATH_MININET_FILES}/linuxrouter.py
        else
            log_error "No process found on port 6653, but Mininet still failed."
            exit 1
        fi
    fi
}

implement_routes() {
    echo -e "Implementando rotas nos devices IoT e broker\n"

    for c in "${BRTESTE01_DEVICES[@]}"; do
        log_info "Adicionando rota no container $c: ${BRTESTE02_RANGE} via ${GW_BRTESTE01}"

        # Checa se a rota já existe
        if docker exec "$c" sh -c "ip route | grep -q '${BRTESTE02_RANGE}'"; then
            log_warn "Rota já existe no container $c"
            continue
        fi

        # Tenta adicionar com ip route
        docker exec "$c" sh -c "ip route add ${BRTESTE02_RANGE} via ${GW_BRTESTE01}" 2>/dev/null
        if [ $? -eq 0 ]; then
           log_success "Rota adicionada com ip route no container $c"
        else
            # fallback: tenta route add -net se ip não existir ou falhar
            docker exec "$c" sh -c "route add -net ${BRTESTE02_RANGE} gw ${GW_BRTESTE01}" 2>/dev/null
            if [ $? -eq 0 ]; then
                log_success "Rota adicionada com route add -net no container $c"
            else
                log_error "Falha ao adicionar rota no container $c"
                docker exec "$c" ip route show
            fi
        fi
    done

    echo -e "Implementando rotas no Prometheus e Grafana\n"
    for c in "${BRTESTE02_DEVICES[@]}"; do
        log_info "Adicionando rota no container $c: ${BRTESTE01_RANGE} via ${GW_BRTESTE02}"

        if docker exec "$c" sh -c "ip route | grep -q '${BRTESTE01_RANGE}'"; then
            log_warn "Rota já existe no container $c"
            continue
        fi

        docker exec "$c" sh -c "ip route add ${BRTESTE01_RANGE} via ${GW_BRTESTE02}" 2>/dev/null
        if [ $? -eq 0 ]; then
            log_success "Rota adicionada com ip route no container $c"
        else
            docker exec "$c" sh -c "route add -net ${BRTESTE01_RANGE} netmask 255.255.255.0 gw ${GW_BRTESTE02}" 2>/dev/null
            if [ $? -eq 0 ]; then
                log_success "Rota adicionada com route add -net no container $c"
            else
                log_error "Falha ao adicionar rota no container $c"
                docker exec "$c" ip route show
            fi
        fi
    done
}

main() {
    echo -e "\e[33m${FIGLET_NAME}\e[0m"
    log_info "Starting to create scenario...\n"
    sleep 1
    stop_containers
    sleep 1
    start_devices
    sleep 1
    start_observability
    sleep 2
    if ( implement_routes ); then
	 log_success "[SUCCESS] Scenario initialized!\n"
    else
	log_error "Scenario initialization failed. Check routes!\n"
        exit 1
    fi
}

################### MAIN EXECUTION ###########################

################### MAIN EXECUTION ###########################

# Processa os argumentos de linha de comando
if [[ $# -eq 0 ]]; then
    main
else
    while [ "$1" != "" ]; do
        case "$1" in
            -h|--help)
                echo -e "$HELP"
                exit 0
                ;;
            -V|--version)
                echo "infra-up - Versão $VERSION"
                exit 0
                ;;
            -a|--all)
                check_root
                main
                ;;
            -m|--monit)
                check_root
                create_docker_networks
                start_observability
                ;;
            -d|--devices)
                check_root
                create_docker_networks
                start_devices
                ;;
            -c|--create)
                check_root
                implement_routes
                ;;
            -i|--infra)
                check_root
                start_mininet
                ;;
            -cl|--clean)
                check_root
                cleanup_images
                ;;
            *)
                log_error "Opção inválida: $1"
                echo "$HELP"
                exit 1
                ;;
        esac
        shift
    done
fi
