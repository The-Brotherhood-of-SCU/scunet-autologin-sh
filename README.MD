# SCU Campus Network Auto Login Script

一个用于四川大学校园网认证页面的自动登录脚本，使用 POSIX `sh` 编写，适合在 Linux、OpenWrt、路由器、WSL、服务器等环境中运行。

脚本会定期检测网络连通性。如果网络不可用，它会自动访问校园网认证入口、跟随重定向、提取登录参数并提交账号密码完成登录。

> 当前版本的终端提示信息为英文，方便在不同系统环境中查看日志。

## 功能特点

- 使用 `/bin/sh`，不依赖 Bash 专有语法
- 不需要 Python
- 支持配置文件，不需要直接修改脚本
- 自动检测网络是否可用
- 自动处理校园网多次重定向
- 支持电信、移动、联通、校园网出口配置
- 使用临时 cookie 文件保存登录过程状态
- 支持 `Ctrl+C` 安全退出并清理临时文件
- 适合长期运行，也适合放到 Linux 服务里开机自启

## 适用场景

适用于使用类似以下认证接口的校园网环境：

```text
/eportal/InterFace.do?method=login
/eportal/InterFace.do?method=getOnlineUserInfo
```

如果你的学校校园网认证页面也是锐捷 ePortal，本脚本可能可以直接使用或稍作修改后使用。

## 文件说明

```text
.
├── scunet_login.sh       # 主脚本
├── scunet_config.conf       # 配置文件，需要自己编辑
├── examples/openwrt-init.d/scunet-login       # OpenWrt init.d 示例
└── README.MD
```

> 建议保留主脚本文件名 `scunet_login.sh`；如果在 OpenWrt/procd 中改名运行，脚本也会正常启动。

## 依赖环境

必须依赖：

- `sh`
- `curl`
- `ping`
- `sed`
- `grep`

可选依赖：

- `jq`：用于更可靠地 URL 编码
- `perl`：没有 `jq` 时用于 URL 编码

脚本不依赖 Python。

在 Debian / Ubuntu 上安装依赖：

```sh
sudo apt update
sudo apt install curl iputils-ping sed grep
```

如果想安装可选依赖：

```sh
sudo apt install jq perl
```

在 OpenWrt 上安装依赖：

```sh
opkg update
opkg install curl iputils-ping
```

## 快速开始

克隆项目或下载脚本后，进入脚本所在目录：

```sh
chmod +x scunet_login.sh
```

修改配置文件：

```sh
vi scunet_config.conf
```

如果仓库里没有示例配置文件，可以自己新建：

```sh
cat > scunet_config.conf <<'EOF'
MAIN_URL="http://192.168.2.135/"
USERID="你的校园网账号"
PASSWORD="你的校园网密码"
SERVICE="CHINATELECOM"
PING_HOST="223.5.5.5"
PING_ATTEMPTS="10"
PING_TIMEOUT="1"
PING_INTERVAL="1"
HEALTHY_LOG_INTERVAL="300"
MAX_ATTEMPTS_ALLOWED="0"
EOF
```

运行脚本：

```sh
./scunet_login.sh
```

如果系统默认不允许直接执行，可以使用：

```sh
sh scunet_login.sh
```

停止脚本：

```text
Ctrl+C
```

## 配置说明

配置文件必须和脚本放在同一个目录，文件名为：

```text
scunet_config.conf
```

可用配置项如下：

| 配置项 | 说明 | 示例 |
|---|---|---|
| `MAIN_URL` | 校园网认证入口地址 | `http://192.168.2.135/` |
| `USERID` | 校园网账号 | `2025000000000` |
| `PASSWORD` | 校园网密码 | `123456` |
| `SERVICE` | 网络出口服务 | `CHINATELECOM` |
| `PING_HOST` | 用于检测网络是否连通的主机 | `202.115.32.49` |
| `PING_ATTEMPTS` | 每轮检测 ping 的次数 | `10` |
| `PING_TIMEOUT` | 单次 ping 超时时间，单位通常为秒 | `1` |
| `PING_INTERVAL` | 两次 ping 之间的间隔 | `1` |
| `HEALTHY_LOG_INTERVAL` | 网络正常时日志打印间隔，单位秒；设为 `0` 可恢复每轮打印 | `300` |
| `MAX_ATTEMPTS_ALLOWED` | 登录失败后的最大重试次数；设为 `0` 表示无限重试 | `0` |

### SERVICE 可选值

| 值 | 含义 |
|---|---|
| `CHINATELECOM` | 电信出口 |
| `CHINAMOBILE` | 移动出口 |
| `CHINAUNICOM` | 联通出口 |
| `EDUNET` | 校园网 / 教育网出口 |

如果不确定自己该填哪个，可以先在网页端手动登录一次，观察登录页面中运营商选项的名称。

## 推荐的配置文件写法

```conf
MAIN_URL="http://192.168.2.135/"
USERID="2025000000000"
PASSWORD="your_password_here"
SERVICE="EDUNET"
PING_HOST="223.5.5.5"
PING_ATTEMPTS="10"
PING_TIMEOUT="1"
PING_INTERVAL="1"
HEALTHY_LOG_INTERVAL="300"
MAX_ATTEMPTS_ALLOWED="0"
```


## 开机自启示例：systemd

适用于普通 Linux 服务器、迷你主机、部分支持 systemd 的发行版。

假设脚本路径为：

```text
/home/yourname/scunet-autologin-sh/scunet_login.sh
```

创建服务文件：

```sh
sudo nano /etc/systemd/system/scunet-login.service
```

写入以下内容，注意修改 `WorkingDirectory` 和 `ExecStart`：

```ini
[Unit]
Description=Campus Network Auto Login
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/home/yourname/scunet-autologin-sh
ExecStart=/bin/sh /home/yourname/scunet-autologin-sh/scunet_login.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

启用并启动服务：

```sh
sudo systemctl daemon-reload
sudo systemctl enable scunet-login.service
sudo systemctl start scunet-login.service
```

查看运行状态：

```sh
systemctl status scunet-login.service
```

查看日志：

```sh
journalctl -u scunet-login.service -f
```

## OpenWrt 使用建议

OpenWrt 环境下可以把脚本放到 `/root/` 或 `/usr/bin/`，例如：

```sh
chmod +x /root/scunet_login.sh
sh /root/scunet_login.sh
```

如果要长期运行，建议使用 `procd`、`screen`、`tmux` 或者放入你自己的守护脚本中。
使用 `procd` 时请让脚本作为前台进程运行；脚本如果立刻退出，即使退出码为 `0`，也会被 procd 反复拉起并显示 crash loop。

仓库里提供了一个 OpenWrt `init.d` 示例，可以按需调整脚本路径后安装：

```sh
cp examples/openwrt-init.d/scunet-login /etc/init.d/scunet-login
chmod +x /etc/init.d/scunet-login
/etc/init.d/scunet-login enable
/etc/init.d/scunet-login start
```

查看日志：

```sh
logread -f -e scunet-login
```

不建议直接用普通 cron 每分钟启动一次，因为本脚本本身是长期循环运行的程序，重复启动可能造成多个实例同时登录。

## 安全提醒

配置文件里会保存校园网账号和密码。请注意：

1. 不要把自己的真实配置文件上传到 GitHub。
2. 不要把自己的账号密码发给别人。
3. 建议把配置文件加入 `.gitignore`。

推荐的 `.gitignore`：

```gitignore
*.conf
*.log
```

## 常见问题

### 1. 提示 Missing dependencies

说明系统缺少必要命令。请先安装 `curl` 和 `ping`。

Debian / Ubuntu：

```sh
sudo apt install curl iputils-ping
```

OpenWrt：

```sh
opkg install curl iputils-ping
```

### 2. 一直显示 Network connection failed

可能原因：

- 设备没有连接校园网 Wi-Fi
- `PING_HOST` 在当前网络下不可达
- 学校防火墙屏蔽了 ICMP ping
- 认证入口地址 `MAIN_URL` 填错

可以尝试把 `PING_HOST` 换成一个内网或公网可 ping 的地址，例如学校 DNS、网关、校园网首页地址对应的 IP。

### 3. Redirect failed

可能原因：

- `MAIN_URL` 不是正确的认证入口
- 学校认证系统的重定向流程和脚本预设的不一样
- 当前已经登录，但门户没有返回脚本能识别的 `success.jsp` 或 `userIndex`
- 校园网系统更新了页面格式

可以先浏览器手动打开 `MAIN_URL`，确认是否会跳转到认证页面。

### 4. Login failed

可能原因：

- 账号或密码错误
- `SERVICE` 选择错误
- 账号已经在其他设备在线
- 学校限制了同时在线设备数量
- 认证接口增加了验证码、加密或其他校验

### 5. 手动登录成功时脚本会怎样？

如果你在脚本尝试登录的同时手动登录成功，通常不会造成严重问题。脚本下一轮网络检测成功后会停止登录流程，并提示网络已经可用。

在少数情况下，脚本可能已经进入了一次登录流程，它会先完成当前请求或等待一次重试，然后再发现网络已经恢复。这通常只会造成日志上出现一次失败或重试，不会影响已经成功的手动登录。

## 已知限制

- 主要面向 Linux / BusyBox / OpenWrt 环境。
- 如果学校认证系统启用了验证码、复杂加密、二维码登录，本脚本可能无法直接使用。
- 如果认证页面结构发生变化，可能需要调整重定向 URL 提取逻辑。
- 本脚本是自用学习工具，不保证适用于所有校园网环境。

## 免责声明

本项目仅供学习和个人使用。请遵守学校网络使用规定，不要用于绕过学校管理策略、共享账号、恶意占用网络资源或其他违规用途。

使用本脚本造成的账号、网络、设备或其他问题，由使用者自行承担责任。

## License

GPL-3.0 License
