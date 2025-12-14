# 🚀 RemnaNode Multi-Instance Setup

<div align="center">

![RemnaNode](https://img.shields.io/badge/RemnaNode-Multi--Instance-blue?style=for-the-badge)
![Bash](https://img.shields.io/badge/Bash-Script-green?style=for-the-badge&logo=gnu-bash)
![License](https://img.shields.io/badge/License-MIT-yellow?style=for-the-badge)

**Автоматическая установка и настройка нескольких RemnaNode на одном сервере с Policy-Based Routing**

[Установка](#-быстрая-установка) • [Требования](#-требования) • [Как это работает](#-как-это-работает) • [Команды](#-полезные-команды) • [FAQ](#-faq)

</div>

---

## 📋 Описание

Этот скрипт автоматизирует процесс развёртывания **трёх нод RemnaNode** на одном сервере с разными IP-адресами. Скрипт настраивает Policy-Based Routing (PBR) для корректной маршрутизации трафика через разные сетевые интерфейсы.

>ℹ️ Использование на примере Yandex Cloud с созданием виртуальной машины с 3 тремя публичными ip-адрсами
>
>⚠️ Важно! Официально, из коробки, несколько инстансов Remnanode не могут быть установлены на одной виртуальной машине, и разработчиками рекомендуется использовать 1 Remnanode = 1 VM.
>
>✅ Между тем, техническая возможность установки и использования нескольких Remnanode в рамках одной виртуальной машины с несколькими публичными ip-адресами существует.

### ✨ Возможности

- 🔄 Автоматическое определение IP-адресов и сетевых интерфейсов
- 📝 Модификация существующей конфигурации RemnaNode
- 📁 Создание конфигураций для дополнительных нод
- 🌐 Настройка Policy-Based Routing (PBR)
- 🔧 Установка systemd-сервисов для автозапуска
- 🛡️ Автоматическое обновление PBR при перезапуске контейнеров

---

## 📌 Требования

### Сервер

| Требование | Минимум |
|------------|---------|
| ОС | Ubuntu 24.04+ |
| RAM | 2 GB |
| CPU | 2 vCPU |
| Сетевые интерфейсы | 3 (eth0, eth1, eth2) |
| IP-адреса | 3 внутренних IP |
| IP-адреса | 3 публичных IP |

>Важно понимать, что на 1 ВМ будут крутится 3 ядра xray, а это означает нагрузку х3, поэтому, если пользователей будет много, то ВМ 2/2 будет плохо, планируйте мощности сразу или планируйте апгрейд по потребностям.

### Предустановленное ПО

- ✅ Docker
- ✅ Docker Compose
- ✅ curl
- ✅ Установленная основная нода RemnaNode в `/opt/remnanode/`

---

## 🚀 Быстрая установка

### Шаг 0: Создание виртуальной машины в Yandex Cloud

Создаем виртуальную машину в той зоне, в которой все 3 наших нужных ip-адреса
https://console.yandex.cloud/folders/_____________/compute/create-instance

В процессе создания ВМ, добавляем еще 2 сетевых интерфейса и выбираем для каждого из интерфейсов свой публичный ip-адрес.

Доступ:
- прописываем имя пользователя, любое, например - mysuser4856
- и добавляем SSH ключ - Добавить ключ - Генерировать

Создать ВМ

Ждем, пока ВМ создается.

В процесс создания, трём сетевым интерфейсам будут назначены внутренние ip-адреса, соответствующие 3 внешним ip-адресам, примерно такого вида:

| внутренний ip-адрес | внешний ip-адрес |
|---------------------|------------------|
| 10.128.0.8 | 51.250.123.123 |
| 10.131.0.17 | 84.201.123.123 |
| 10.132.0.32 | 178.154.123.123 |

Они нам пригодятся в будущем.

Прежде чем подключиться по SSH, нам нужно создать инбаунды в профиле в панели Remnawave.

Для этого мождно исползовать ваш основной профиль, или создать отдельный новый профиль специально под это дело, например:
```bash
ya-cloud-profile
```

Пример конфига:
[xray_config_yacl.yml](https://raw.githubusercontent.com/probizvpn/remnanodes-yacl/refs/heads/main/xray_config_yacl.yml)

После сохранения профиля, нужно включить (поставить галочки) новые инбаунды во внутреннем скваде.

Далее берем первый внешний ip-адрес и идем подключаться по SSH.
В моем примере:
```bash
51.250.123.123
```

Возьмем права рута:
```bash
mysuser4856@compute-vm-2-2-20-ssd-1765658014436:~$ sudo -i
```
и двигаемся дальше...

### Шаг 1: Установите основную ноду RemnaNode

Если у вас ещё не установлена основная нода, установите её согласно [официальной документации RemnaWave](https://github.com/remnawave/node).

А еще лучше, воспользоваться скриптом автоустановки RemnaSetup от [Capybara](https://github.com/Capybara-z/RemnaSetup):

```bash
curl -fsSL https://raw.githubusercontent.com/Capybara-z/RemnaSetup/refs/heads/main/install.sh -o install.sh && chmod +x install.sh && sudo bash ./install.sh
```

>Важно! Ставим только remnanode, больше ничего не надо, ни caddy, ни другое.

>пункты меню:
2 - 2 - 2

Скрипт установит докер, поставит ноду, logrotate.
Выходим из скрипта.
>8 - 0

В результате у вас уже будет одна настроенная и запущенная нода.

В панели в окне создания ноды - Далее
Выбираем профиль и из него 4 первых инбаунда (1-1, 1-2, 1-3, 1-4)
Сохранить - Создать ноду

Сейчас уже можно добавить 4 хоста для 4 разных инбаундов (1-1, 1-2, 1-3, 1-4) с 4 разными сни для этой новой 1 ноды на 51 айпи.

И проверить работу в клиентском приложении. Все должно работать как обычно.

>Далее добавление второй и третьей нод.

### Шаг 2: Запустите скрипт установки RemnaNode Multi-Instance Setup

```bash
curl -fsSL https://raw.githubusercontent.com/probizvpn/remnanodes-yacl/main/install.sh -o install.sh && chmod +x install.sh && sudo bash ./install.sh
```

### Шаг 3: Следуйте инструкциям

Скрипт запросит:


>NODE_PORT для remnanode1 (укажите свой)
NODE_PORT для remnanode2 (укажите свой)
SECRET_KEY для remnanode1 (скопируйте из панели управления)
SECRET_KEY для remnanode2 (скопируйте из панели управления)

В процессе, также в панели создаем добавляем ноды, как это делали обычно.
Для второй и третьей ноды указываем соответственно наши ip-адреса привязанные к ВМ.
В моем примере:
```bash
84.201.123.123
178.154.123.123
```
Скрипт сам создаст папки, создаст файлы docker-compose.yml, создаст службы сервисы, запросит SECRET_KEY и NODE_PORT и перезапустит контейнеры и все включит в работу.

В результате у вас будет настроенная и запущенная 2 и 3 нода.

В панели в окне создания 2 ноды - Далее
Выбираем профиль и из него 4 инбаунда (2-1, 2-2, 2-3, 2-4 )
Сохранить - Создать ноду

В панели в окне создания 3 ноды - Далее
Выбираем профиль и из него 4 инбаунда (3-1, 3-2, 3-3, 3-4)
Сохранить - Создать ноду

Сейчас уже можно добавить 4 хоста для 4 разных инбаундов (2-1, 2-2, 2-3) с 4 разными сни для этой новой 2 ноды на 84 айпи.

Сейчас уже можно добавить 4 хоста для 4 разных инбаундов (3-1, 3-2, 3-3, 3-4) с 4 разными сни для этой новой 3 ноды на 178 айпи.

И проверить работу в клиентском приложении. Все должно работать как обычно.

>Важно! В примере конфиге [xray_config_yacl.yml](https://raw.githubusercontent.com/probizvpn/remnanodes-yacl/refs/heads/main/xray_config_yacl.yml), уже предусмотрена логика - весь трафик с этой ВМ роутится на ЕУ-ВМ, если вы делаете на основе вашего конфига, предусмотрите роутинг.

## 🔧 Как это работает

### Архитектура
```bash
┌─────────────────────────────────────────────────────┐
│                        СЕРВЕР                       │
├─────────────────────────────────────────────────────┤
│                                                     │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  │
│  │  remnanode  │  │ remnanode1  │  │ remnanode2  │  │
│  │  (Docker)   │  │  (Docker)   │  │  (Docker)   │  │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  │
│         │                │                │         │
│         ▼                ▼                ▼         │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  │
│  │    eth0     │  │    eth1     │  │    eth2     │  │
│  │ 10.128.0.x  │  │ 10.131.0.x  │  │ 10.132.0.x  │  │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  │
│         │                │                │         │
└─────────┼────────────────┼────────────────┼─────────┘
          │                │                │
          ▼                ▼                ▼
     ┌──────────┐     ┌──────────┐     ┌──────────┐
     │ Внешний  │     │ Внешний  │     │ Внешний  │
     │   IP 1   │     │   IP 2   │     │   IP 3   │
     └──────────┘     └──────────┘     └──────────┘
```
### Структура файлов после установки

```bash
/opt/
├── remnanode/
│   └── docker-compose.yml      # Основная нода
├── remnanode1/
│   └── docker-compose.yml      # Дополнительная нода 1
├── remnanode2/
│   └── docker-compose.yml      # Дополнительная нода 2
├── setup-pbr.sh                # Скрипт настройки PBR
└── pbr-docker-watch.sh         # Скрипт мониторинга Docker

/etc/systemd/system/
├── pbr-setup.service           # Сервис запуска PBR при загрузке
└── pbr-docker-watch.service    # Сервис мониторинга Docker событий
```


## Policy-Based Routing (PBR)

PBR обеспечивает корректную маршрутизацию ответного трафика через тот же интерфейс, через который пришёл запрос:


>Входящий трафик → помечается меткой (mark) в зависимости от интерфейса
Метка сохраняется в conntrack для всего соединения
Исходящий трафик → маршрутизируется через соответствующий интерфейс на основе метки


## 📝 Полезные команды

### Управление контейнерами

```bash
# Статус всех контейнеров
docker ps
```

```bash
# Логи конкретной ноды
cd /opt/remnanode && docker compose logs -f -t
cd /opt/remnanode1 && docker compose logs -f -t
cd /opt/remnanode1 && docker compose logs -f -t
```

```bash
# или
cd /opt/remnanode && docker logs remnanode
cd /opt/remnanode1 && docker logs remnanode1
cd /opt/remnanode2 && docker logs remnanode2
```

```bash
# Перезапуск ноды
cd /opt/remnanode && docker compose down && docker compose up -d
cd /opt/remnanode1 && docker compose down && docker compose up -d
cd /opt/remnanode2 && docker compose down && docker compose up -d
```

```bash
# Остановка всех нод
cd /opt/remnanode && docker compose down
cd /opt/remnanode1 && docker compose down
cd /opt/remnanode2 && docker compose down
```

```bash
# Запуск всех нод
cd /opt/remnanode && docker compose up -d
cd /opt/remnanode1 && docker compose up -d
cd /opt/remnanode2 && docker compose up -d
```

### Управление PBR

```bash
# Ручной запуск настройки PBR
sudo /opt/setup-pbr.sh
```

```bash
# Статус сервиса мониторинга
sudo systemctl status pbr-docker-watch
```

```bash
# Перезапуск сервиса мониторинга
sudo systemctl restart pbr-docker-watch
```

```bash
# Просмотр логов PBR
sudo journalctl -u pbr-docker-watch -f
```

### Диагностика

```bash
# Проверка IP-адресов
ip route | grep default
```

```bash
# Проверка правил маршрутизации
ip rule show
```

```bash
# Проверка iptables меток
sudo iptables -t mangle -L -n -v
```

```bash
# Проверка NAT правил
sudo iptables -t nat -L -n -v
```

```bash
# Проверка портов
ss -tlnp | grep -E '(2222|443)'
```

## ❓ FAQ

### Сколько нод можно запустить?

Скрипт настроен на 3 ноды (remnanode, remnanode1, remnanode2). Для большего количества потребуется модификация скрипта.

### Что делать, если PBR не работает после перезагрузки?

```bash
# Проверьте статус сервисов
sudo systemctl status pbr-setup
sudo systemctl status pbr-docker-watch
```

```bash
# Запустите PBR вручную
sudo /opt/setup-pbr.sh
```

### Как обновить ноды?

```bash
# Обновите образ в docker-compose.yml каждой ноды
# Затем выполните:
cd /opt/remnanode && docker compose pull && docker compose up -d
cd /opt/remnanode1 && docker compose pull && docker compose up -d
cd /opt/remnanode2 && docker compose pull && docker compose up -d
```

### Как удалить дополнительные ноды?

```bash
# Остановите и удалите контейнеры
cd /opt/remnanode1 && docker compose down
cd /opt/remnanode2 && docker compose down
```

```bash
# Удалите папки
sudo rm -rf /opt/remnanode1 /opt/remnanode2
```

```bash
# Отключите сервисы PBR (опционально)
sudo systemctl disable pbr-setup pbr-docker-watch
sudo systemctl stop pbr-docker-watch
```

### Как проверить, что трафик идёт через правильный интерфейс?

С внешнего сервера выполните:

```bash
# Замените IP и PORT на ваши значения
nc -zv ВНЕШНИЙ_IP_1 PORT
nc -zv ВНЕШНИЙ_IP_2 PORT
nc -zv ВНЕШНИЙ_IP_3 PORT
```
---

### Структура репозитория
```bash
remnanodes-yacl/
├── README.md
├── LICENSE
├── install.sh
├── setup-pbr.sh
├── pbr-docker-watch.sh
├── pbr-setup.service
├── pbr-docker-watch.service
└── xray_config_yacl.yml
```
---
## 🤝 Сообщество

<div align="center">
🦊 Specially for SoloBot Community

[https://github.com/Vladless/Solo_bot](https://github.com/Vladless/Solo_bot)
</div>

## 🙏 Благодарности

💚 [RemnaWave](https://github.com/remnawave)
 — за потрясающий проект

🧡 [SoloBot Community](https://github.com/Vladless/Solo_bot)
 — за поддержку

## 📄 Лицензия

Этот проект распространяется под лицензией MIT. Подробности в файле [LICENSE](https://raw.githubusercontent.com/probizvpn/remnanodes-yacl/refs/heads/main/LICENSE)

<div align="center">
⭐ Если проект был полезен, поставьте звезду! ⭐
</div>


