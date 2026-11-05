#!/bin/sh
# ============================================================
# QingNZ 探针 Dashboard 一键安装/管理脚本
# 参考官方 nezhahq/scripts install.sh 定制, 自包含全部模板
#
#   安装目录: /etc/.qingnz/dashboard
#   二进制:   /etc/.qingnz/dashboard/app
#   配置:     /etc/.qingnz/dashboard/data/config.yaml
#   服务名:   qingnz-dashboard.service (systemd) / qingnz-dashboard (OpenRC)
#   Docker:   ghcr.io/qingdeng888/nezha
#
# 用法:
#   curl -L https://raw.githubusercontent.com/qingdeng888/nezha/master/script/install.sh -o qingnz.sh && chmod +x qingnz.sh && sudo ./qingnz.sh
#
# 子命令: install / modify_config / restart_and_update / show_log / uninstall / update_script
#
# 可选环境变量:
#   NZ_GH_PROXY   GitHub 下载加速前缀, 例: https://ghproxy.example.com/
# ============================================================

NZ_BASE_PATH="/etc/.qingnz"
NZ_DASHBOARD_PATH="${NZ_BASE_PATH}/dashboard"
NZ_DASHBOARD_SERVICE="/etc/systemd/system/qingnz-dashboard.service"
NZ_DASHBOARD_SERVICERC="/etc/init.d/qingnz-dashboard"
NZ_REPO="qingdeng888/nezha"
NZ_DOCKER_IMG="ghcr.io/qingdeng888/nezha:latest"
NZ_SCRIPT_RAW_URL="raw.githubusercontent.com/qingdeng888/nezha/master/script/install.sh"

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

err() {
    printf "${red}%s${plain}\n" "$*" >&2
}

warn() {
    printf "${red}%s${plain}\n" "$*"
}

success() {
    printf "${green}%s${plain}\n" "$*"
}

info() {
    printf "${yellow}%s${plain}\n" "$*"
}

println() {
    printf "$*\n"
}

# 非 root 时自动借道 sudo
sudo() {
    myEUID=$(id -ru)
    if [ "$myEUID" -ne 0 ]; then
        if command -v sudo > /dev/null 2>&1; then
            command sudo "$@"
        else
            err "错误: 您的系统未安装 sudo，因此无法进行该项操作。"
            exit 1
        fi
    else
        "$@"
    fi
}

# 可选加速前缀: NZ_GH_PROXY 前缀到 GitHub 下载链接
gh_url() {
    if [ -n "$NZ_GH_PROXY" ]; then
        printf "%s%s" "$NZ_GH_PROXY" "$1"
    else
        printf "%s" "$1"
    fi
}

deps_check() {
    deps="curl wget unzip grep"
    for dep in $deps; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            err "未找到依赖 $dep，请先安装。"
            exit 1
        fi
    done
}

check_init() {
    init=$(readlink /sbin/init)
    case "$init" in
        *systemd*)
            INIT=systemd
            ;;
        *openrc-init*|*busybox*)
            INIT=openrc
            ;;
        *)
            err "Unknown init"
            exit 1
            ;;
    esac
}

env_check() {
    uname=$(uname -m)
    case "$uname" in
        amd64|x86_64)
            os_arch="amd64"
            ;;
        i386|i686)
            os_arch="386"
            ;;
        aarch64|arm64)
            os_arch="arm64"
            ;;
        *arm*)
            os_arch="arm"
            ;;
        s390x)
            os_arch="s390x"
            ;;
        riscv64)
            os_arch="riscv64"
            ;;
        *)
            err "未知架构：$uname"
            exit 1
            ;;
    esac
}

installation_check() {
    if docker compose version >/dev/null 2>&1; then
        DOCKER_COMPOSE_COMMAND="docker compose"
        if sudo $DOCKER_COMPOSE_COMMAND ls | grep -qw "$NZ_DASHBOARD_PATH/docker-compose.yaml" >/dev/null 2>&1; then
            NZ_IMAGES=$(sudo docker images --format "{{.Repository}}":"{{.Tag}}" | grep -w "qingdeng888/nezha")
            if [ -n "$NZ_IMAGES" ]; then
                echo "存在带有 qingdeng888/nezha 仓库的 Docker 镜像："
                echo "$NZ_IMAGES"
                IS_DOCKER_NZ=1
                FRESH_INSTALL=0
                return
            else
                echo "未找到带有 qingdeng888/nezha 仓库的 Docker 镜像。"
            fi
        fi
    elif command -v docker-compose >/dev/null 2>&1; then
        DOCKER_COMPOSE_COMMAND="docker-compose"
        if sudo $DOCKER_COMPOSE_COMMAND -f "$NZ_DASHBOARD_PATH/docker-compose.yaml" config >/dev/null 2>&1; then
            NZ_IMAGES=$(sudo docker images --format "{{.Repository}}":"{{.Tag}}" | grep -w "qingdeng888/nezha")
            if [ -n "$NZ_IMAGES" ]; then
                echo "存在带有 qingdeng888/nezha 仓库的 Docker 镜像："
                echo "$NZ_IMAGES"
                IS_DOCKER_NZ=1
                FRESH_INSTALL=0
                return
            else
                echo "未找到带有 qingdeng888/nezha 仓库的 Docker 镜像。"
            fi
        fi
    fi

    if [ -f "$NZ_DASHBOARD_PATH/app" ]; then
        IS_DOCKER_NZ=0
        FRESH_INSTALL=0
    fi
}

select_version() {
    if [ -z "$IS_DOCKER_NZ" ]; then
        info "请自行选择您的安装方式："
        info "1. Docker"
        info "2. 独立安装"
        while true; do
            printf "请输入选择 [1-2]："
            read -r option
            case "${option}" in
                1)
                    IS_DOCKER_NZ=1
                    break
                    ;;
                2)
                    IS_DOCKER_NZ=0
                    break
                    ;;
                *)
                    err "请输入正确的选择 [1-2]"
                    ;;
            esac
        done
    fi
}

init() {
    deps_check
    check_init
    env_check
    installation_check
}

update_script() {
    echo "> 更新脚本"

    curl -sL "$(gh_url "https://${NZ_SCRIPT_RAW_URL}")" -o /tmp/qingnz.sh
    mv -f /tmp/qingnz.sh ./qingnz.sh && chmod a+x ./qingnz.sh

    echo "3s后执行新脚本"
    sleep 3s
    clear
    exec ./qingnz.sh
    exit 0
}

before_show_menu() {
    echo && info "* 按回车返回主菜单 *" && read temp
    show_menu
}

install() {
    echo "> 安装"

    # QingNZ 探针面板目录
    if [ ! "$FRESH_INSTALL" = 0 ]; then
        sudo mkdir -p $NZ_DASHBOARD_PATH
    else
        echo "您可能已经安装过面板端，重复安装会覆盖数据，请注意备份。"
        printf "是否退出安装? [Y/n]"
        read -r input
        case $input in
        [yY][eE][sS] | [yY])
            echo "退出安装"
            exit 0
            ;;
        [nN][oO] | [nN])
            echo "继续安装"
            ;;
        *)
            echo "退出安装"
            exit 0
            ;;
        esac
    fi

    modify_config 0

    if [ $# = 0 ]; then
        before_show_menu
    fi
}

# 自包含配置/服务模板, 不依赖外部文件下载
write_templates() {
    cat > /tmp/qingnz-config.yaml <<'EOF'
debug: false
listen_port: nz_port
language: nz_language
site_name: "nz_site_title"
install_host: nz_hostport
tls: nz_tls
EOF

    cat > /tmp/qingnz-docker-compose.yaml <<'EOF'
services:
  dashboard:
    image: ghcr.io/qingdeng888/nezha:latest
    container_name: qingnz-dashboard
    restart: always
    volumes:
      - ./data:/dashboard/data
    ports:
      - nz_port:nz_port
EOF

    cat > /tmp/qingnz-dashboard.service <<'EOF'
[Unit]
Description=QingNZ Dashboard
After=syslog.target
After=network.target
After=mariadb.service mysqld.service postgresql.service memcached.service redis.service

[Service]
# Modify these two values and uncomment them if you have
# repos with lots of files and get an HTTP error 500 because
# of that
###
#LimitMEMLOCK=infinity
#LimitNOFILE=65535
Type=simple
#User=root
#Group=root
WorkingDirectory=/etc/.qingnz/dashboard/
ExecStart=/etc/.qingnz/dashboard/app
Restart=always
#Environment=DEBUG=true

# Some distributions may not support these hardening directives. If you cannot start the service due
# to an unknown option, comment out the ones not supported by your version of systemd.
ProtectSystem=full
PrivateDevices=yes
PrivateTmp=yes
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

    cat > /tmp/qingnz-dashboard.openrc <<'EOF'
#!/sbin/openrc-run
supervisor=supervise-daemon
name=qingnz-dashboard
output_log=/var/log/${name}.log
error_log=/var/log/${name}.err
pidfile="/run/${RC_SVCNAME}.pid"
command="/etc/.qingnz/dashboard/app"
command_args=""
command_background=true
directory="/etc/.qingnz/dashboard"

depend() {
	  need net
}

start_pre() {
    checkpath -f -m 0644 -o root:root "/var/log/${name}.log"
}
EOF
}

modify_config() {
    echo "> 修改配置"

    if [ "$IS_DOCKER_NZ" = 1 ]; then
        if [ -z "$DOCKER_COMPOSE_COMMAND" ]; then
            err "请手动安装 docker-compose。 https://docs.docker.com/compose/install/linux/"
            before_show_menu
        fi
    fi

    write_templates

    printf "请输入站点标题: "
    read -r nz_site_title
    printf "请输入暴露端口: (默认 8008)"
    read -r nz_port
    printf "请指定安装命令中预设的 qingnz agent 连接地址 （例如 example.com:443）"
    read -r nz_hostport
    printf "是否希望通过 TLS 连接 Agent？（影响安装命令）[y/N]"
    read -r input
    case $input in
    [yY][eE][sS] | [yY])
        nz_tls=true
        ;;
    [nN][oO] | [nN])
        nz_tls=false
        ;;
    *)
        nz_tls=false
        ;;
    esac
    println "请指定后台语言"
    println "1. 中文（简体）"
    println "2. 中文（台灣）"
    println "3. English"
    while true; do
        printf "请输入选项 [1-3]"
        read -r option
        case "${option}" in
            1)
                nz_lang=zh_CN
                break
                ;;
            2)
                nz_lang=zh_TW
                break
                ;;
            3)
                nz_lang=en_US
                break
                ;;
            *)
                err "请输入正确的选项 [1-3]"
                ;;
        esac
    done

    if [ -z "$nz_lang" ] || [ -z "$nz_site_title" ] || [ -z "$nz_hostport" ]; then
        err "所有选项都不能为空"
        before_show_menu
        return 1
    fi

    if [ -z "$nz_port" ]; then
        nz_port=8008
    fi

    sed -i "s/nz_port/${nz_port}/" /tmp/qingnz-config.yaml
    sed -i "s/nz_language/${nz_lang}/" /tmp/qingnz-config.yaml
    sed -i "s/nz_site_title/${nz_site_title}/" /tmp/qingnz-config.yaml
    sed -i "s/nz_hostport/${nz_hostport}/" /tmp/qingnz-config.yaml
    sed -i "s/nz_tls/${nz_tls}/" /tmp/qingnz-config.yaml
    if [ "$IS_DOCKER_NZ" = 1 ]; then
        sed -i "s/nz_port/${nz_port}/g" /tmp/qingnz-docker-compose.yaml
    fi

    sudo mkdir -p $NZ_DASHBOARD_PATH/data
    sudo mv -f /tmp/qingnz-config.yaml ${NZ_DASHBOARD_PATH}/data/config.yaml
    if [ "$IS_DOCKER_NZ" = 1 ]; then
        sudo mv -f /tmp/qingnz-docker-compose.yaml ${NZ_DASHBOARD_PATH}/docker-compose.yaml
    fi

    if [ "$IS_DOCKER_NZ" = 0 ]; then
        echo "正在写入服务文件"
        if [ "$INIT" = "systemd" ]; then
            sudo mv -f /tmp/qingnz-dashboard.service $NZ_DASHBOARD_SERVICE
        elif [ "$INIT" = "openrc" ]; then
            sudo mv -f /tmp/qingnz-dashboard.openrc $NZ_DASHBOARD_SERVICERC
            sudo chmod +x $NZ_DASHBOARD_SERVICERC
        fi
    fi

    success "Dashboard 配置 修改成功，请稍等 Dashboard 重启生效"

    restart_and_update

    if [ $# = 0 ]; then
        before_show_menu
    fi
}

restart_and_update() {
    echo "> 重启并更新"

    if [ "$IS_DOCKER_NZ" = 1 ]; then
        _cmd="restart_and_update_docker"
    elif [ "$IS_DOCKER_NZ" = 0 ]; then
        _cmd="restart_and_update_standalone"
    fi

    if eval "$_cmd"; then
        success "QingNZ 探针面板 重启成功"
        info "默认地址：域名:站点访问端口"
    else
        err "重启失败，可能是因为启动时间超过了两秒，请稍后查看日志信息"
    fi

    if [ $# = 0 ]; then
        before_show_menu
    fi
}

restart_and_update_docker() {
    sudo $DOCKER_COMPOSE_COMMAND -f ${NZ_DASHBOARD_PATH}/docker-compose.yaml pull
    sudo $DOCKER_COMPOSE_COMMAND -f ${NZ_DASHBOARD_PATH}/docker-compose.yaml down
    sleep 2
    sudo $DOCKER_COMPOSE_COMMAND -f ${NZ_DASHBOARD_PATH}/docker-compose.yaml up -d
}

restart_and_update_standalone() {
    _version=$(curl -m 10 -sL "https://api.github.com/repos/${NZ_REPO}/releases/latest" | grep "tag_name" | head -n 1 | awk -F ":" '{print $2}' | sed 's/\"//g;s/,//g;s/ //g')

    if [ -z "$_version" ]; then
        err "获取 Dashboard 版本号失败，请检查本机能否链接 https://api.github.com/repos/${NZ_REPO}/releases/latest (或设置 NZ_GH_PROXY 后重试)"
        return 1
    else
        echo "当前最新版本为： ${_version}"
    fi

    if [ "$INIT" = "systemd" ]; then
        sudo systemctl daemon-reload
        sudo systemctl stop qingnz-dashboard
    elif [ "$INIT" = "openrc" ]; then
        sudo rc-service qingnz-dashboard stop
    fi

    NZ_DASHBOARD_URL="$(gh_url "https://github.com/${NZ_REPO}/releases/download/${_version}/dashboard-linux-${os_arch}.zip")"

    sudo wget -qO $NZ_DASHBOARD_PATH/app.zip "$NZ_DASHBOARD_URL" >/dev/null 2>&1 && sudo unzip -qq -o $NZ_DASHBOARD_PATH/app.zip -d $NZ_DASHBOARD_PATH && sudo mv $NZ_DASHBOARD_PATH/dashboard-linux-$os_arch $NZ_DASHBOARD_PATH/app && sudo rm $NZ_DASHBOARD_PATH/app.zip
    sudo chmod +x $NZ_DASHBOARD_PATH/app

    sleep 2

    if [ "$INIT" = "systemd" ]; then
        sudo systemctl enable qingnz-dashboard
        sudo systemctl restart qingnz-dashboard
    elif [ "$INIT" = "openrc" ]; then
        sudo rc-update add qingnz-dashboard
        sudo rc-service qingnz-dashboard restart
    fi
}

show_log() {
    echo "> 获取日志"

    if [ "$IS_DOCKER_NZ" = 1 ]; then
        show_dashboard_log_docker
    elif [ "$IS_DOCKER_NZ" = 0 ]; then
        show_dashboard_log_standalone
    fi

    if [ $# = 0 ]; then
        before_show_menu
    fi
}

show_dashboard_log_docker() {
    sudo $DOCKER_COMPOSE_COMMAND -f ${NZ_DASHBOARD_PATH}/docker-compose.yaml logs -f
}

show_dashboard_log_standalone() {
    if [ "$INIT" = "systemd" ]; then
        sudo journalctl -xf -u qingnz-dashboard.service
    elif [ "$INIT" = "openrc" ]; then
        sudo tail -n 10 /var/log/qingnz-dashboard.err
    fi
}

uninstall() {
    echo "> 卸载"

    warn "警告：卸载前请备份您的文件。"
    printf "继续？ [y/N] "
    read -r input
    case $input in
    [yY][eE][sS] | [yY])
        info "卸载中…"
        ;;
    [nN][oO] | [nN])
        return
        ;;
    *)
        return
        ;;
    esac

    if [ "$IS_DOCKER_NZ" = 1 ]; then
        uninstall_dashboard_docker
    elif [ "$IS_DOCKER_NZ" = 0 ]; then
        uninstall_dashboard_standalone
    fi

    if [ $# = 0 ]; then
        before_show_menu
    fi
}

uninstall_dashboard_docker() {
    sudo $DOCKER_COMPOSE_COMMAND -f ${NZ_DASHBOARD_PATH}/docker-compose.yaml down
    sudo rm -rf $NZ_DASHBOARD_PATH
    sudo docker rmi -f $NZ_DOCKER_IMG >/dev/null 2>&1
}

uninstall_dashboard_standalone() {
    sudo rm -rf $NZ_DASHBOARD_PATH

    if [ "$INIT" = "systemd" ]; then
        sudo systemctl disable qingnz-dashboard
        sudo systemctl stop qingnz-dashboard
    elif [ "$INIT" = "openrc" ]; then
        sudo rc-update del qingnz-dashboard
        sudo rc-service qingnz-dashboard stop
    fi

    if [ "$INIT" = "systemd" ]; then
        sudo rm $NZ_DASHBOARD_SERVICE
    elif [ "$INIT" = "openrc" ]; then
        sudo rm $NZ_DASHBOARD_SERVICERC
    fi
}

show_usage() {
    echo "QingNZ 探针面板 管理脚本使用方法: "
    echo "--------------------------------------------------------"
    echo "./qingnz.sh                    - 显示管理菜单"
    echo "./qingnz.sh install            - 安装面板端"
    echo "./qingnz.sh modify_config      - 修改面板配置"
    echo "./qingnz.sh restart_and_update - 重启并更新面板"
    echo "./qingnz.sh show_log           - 查看面板日志"
    echo "./qingnz.sh uninstall          - 卸载管理面板"
    echo "--------------------------------------------------------"
}

show_menu() {
    println "${green}QingNZ 探针面板管理脚本${plain}"
    echo "--- https://github.com/qingdeng888/nezha ---"
    println "${green}1.${plain}  安装面板端"
    println "${green}2.${plain}  修改面板配置"
    println "${green}3.${plain}  重启并更新面板"
    println "${green}4.${plain}  查看面板日志"
    println "${green}5.${plain}  卸载管理面板"
    echo "————————————————-"
    println "${green}6.${plain}  更新脚本"
    echo "————————————————-"
    println "${green}0.${plain}  退出脚本"

    echo && printf "请输入选择 [0-6]: " && read -r num
    case "${num}" in
        0)
            exit 0
            ;;
        1)
            install
            ;;
        2)
            modify_config
            ;;
        3)
            restart_and_update
            ;;
        4)
            show_log
            ;;
        5)
            uninstall
            ;;
        6)
            update_script
            ;;
        *)
            err "请输入正确的数字 [0-6]"
            ;;
    esac
}

init

if [ $# -gt 0 ]; then
    case $1 in
        "install")
            install 0
            ;;
        "modify_config")
            modify_config 0
            ;;
        "restart_and_update")
            restart_and_update 0
            ;;
        "show_log")
            show_log 0
            ;;
        "uninstall")
            uninstall 0
            ;;
        "update_script")
            update_script 0
            ;;
        *) show_usage ;;
    esac
else
    select_version
    show_menu
fi
