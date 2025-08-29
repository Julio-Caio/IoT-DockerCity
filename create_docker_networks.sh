#!/bin/bash

# Definição de cores para as saídas
RED='\e[31m'       # Vermelho
GREEN='\e[32m'     # Verde
YELLOW='\e[33m'    # Amarelo
BLUE='\e[34m'      # Azul
CYAN='\e[36m'      # Ciano
RESET='\e[0m'      # Resetar cor

is_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Require root privileges!${RESET}\n"
        exit 1
    fi
}

function criar_redes_docker() {
    # rede sensores: brteste01
    docker network create --driver bridge --subnet=172.18.0.0/24 brteste01 \
        && echo "Rede brteste01 criada!" \
        || echo "Erro ao criar rede brteste01!"

    # rede monitoramento: brteste02
    docker network create --driver bridge --subnet=172.19.0.0/24 brteste02 \
        && echo "Rede brteste02 criada!" \
        || echo "Erro ao criar rede brteste02!"

    # enviar ao arquivo 'mininet_interfaces.txt' os nomes das bridges
    echo "br-$(docker network inspect brteste01 -f '{{.Id}}' | cut -c1-12)" > ./stack-infra/mininet/mininet_interfaces.txt
    echo "br-$(docker network inspect brteste02 -f '{{.Id}}' | cut -c1-12)" >> ./stack-infra/mininet/mininet_interfaces.txt
}

main()
{
    is_root
    verificar_distro
    echo -e "\n
    A seguir, serão criadas as subredes brteste01/02

    Gostaria de prosseguir? [Y/n] \n"

    read -rp "Deseja prosseguir com a instalação? [Y/n]: " opcao

    if [[ "$opcao" == "Y" || "$opcao" == "y" || -z "$opcao" ]]; then
        criar_redes_docker

        echo -e "${GREEN}Ambiente preparado com sucesso para produção.${RESET}"
    else
        echo -e "${RED}Saindo...${RESET}"
        exit 1
    fi
}

main