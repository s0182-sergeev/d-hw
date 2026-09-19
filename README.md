# Дипломная работа по профессии «Системный администратор» - Сергеев Александр

## Задача

Ключевая задача — разработать отказоустойчивую инфраструктуру для сайта, включающую мониторинг, сбор логов и
резервное копирование основных данных. Инфраструктура должна размещаться в Yandex Cloud и отвечать минимальным
стандартам безопасности: запрещается выкладывать токен от облака в git.

## Описание инфраструктуры

Для развёртки инфраструктуры использован Terraform и Ansible.
Для ansible inventory ip-адреса использованы короткие fqdn имена виртуальных машин (ВМ).
Применены минимальные конфигурации ВМ: 2 ядра, 20% Intel ice lake, 2-4Гб памяти, 10hdd, прерываемая.
Схема инфраструктуры с указанием основных сетевых взимодействий приведена на рисунке.

![Схема инфрструктуры](/img/image1.png)`

### Сайт

Созданы две ВМ (web-a, web-b) в разных зонах с идентичными ОС и содержимым, на которые установлен веб-сервер nginx.
Для идентификации веб-сервера настроен вывод внутреннего IP-адреса и имени ВМ на странице по умолчанию.

ВМ веб-серверов настроены на получение только внутреннего IP-адреса.
Доступ к ВМ по ssh настроен через бастион-сервер.
Доступ к web-порту ВМ настроен через балансировщик Yandex Cloud.
Из внутренней сети доступ web-порту также настроен для сервера Zabbix для получения статуса веб-сервера.

Настройка балансировщика:
- cоздана группа target-group, в нее включены ВМ web-a и web-b;
- cоздана группа backend-group, настроены backends на группу target group, настроен healthcheck на корень (/) и порт 80, протокол HTTP;
- создан роутер http-router с путем "/" и ссылкой на группу backend group;
- создан L7-балансер application-load-balancer для распределения трафика на два веб-сервера, указан роутер http-router,
задан listener тип auto, порт 80.

Протестирован сайт:
`curl -v <публичный IP балансера>:80` 

### Мониторинг

Создана ВМ (zabbix), в ней развернут сервер Zabbix.
На каждую ВМ инфрраструктуры (bastion, web-a, web-b, es, kibana) установлен Zabbix Agent, настроены агенты на отправление метрик в Zabbix.
На сервере Zabbix настроены дашборды с отображением метрик по принципу USE (Utilization, Saturation, Errors)
для CPU, RAM, диски, сеть, http запросов к веб-серверам. Добавлены необходимые tresholds на соответствующие графики.

### Логи
Cоздана ВМ (es), в ней развернута Elasticsearch в контейнере Docker.
На ВМ веб-серверов установлен filebeat и настроен на отправку access.log, error.log nginx в сервер Elasticsearch.
Создана ВМ (kibana), в ней развернута Kibana и настроено соединение с Elasticsearch.

### Сеть

Развернут один VPC. На ВМ с веб-серверами и сервером Elasticsearch настроен только внутренний IP-адрес.
На ВМ с серверами Zabbix, Kibana дополнительно настроен публичный IP-адрес.
Сервис application load balancer автоматически получает публичный IP-адрес.
Настроены группы безопасности security-groups соответствующих сервисов на входящий трафик только к нужным портам.
Порт ssh открыт только на ВМ bastion. Эта ВМ реализует концепцию "bastion host"
Подключение ansible к серверам web, Elasticsearch, kibana настроено через ВМ bastion с помощью ProxyCommand.
Скрипт ansible настроен на выполнение на локальном хосте, а его команды выполняются на удаленных хостах.
Исходящий доступ в интернет для ВМ внутреннего контура через NAT-шлюз Yandex Cloud.

### Резервное копирование
Созданы snapshot дисков всех ВМ. Время жизни snapshot установлено в одну неделю.
Выполнение snapshot настроено на ежедневное копирование.

## Работа с инфраструктурой

### Безопасность инфраструктуры

Доступ в Yandex Cloud настроен по ключу, который хранится в файле "~/.yandex-cloud_terraform_authorized_key.json"
на локальном хосте. Файл с ключом находится вне рабочего каталога и не передается в репозиторий github.

Доступ ssh на все ВМ настроен по ключу, который хранится на локальном хосте и передается на
ВМ при их создании параметром ssh-keys = "ubuntu:${file("~/.ssh/id_ed30032026.pub")}".
Пароли при доступе ssh не используются. Файл с ключом находится вне рабочего каталога и не передается в
репозиторий github.

Доступ в веб-интерфейс Zabbix настроен с логином Admin по предустановленному паролю (15 знаков), который хранится
в файле terraform.tvars. Команда "terraform apply" записывает этот пароль и его хеш в локальные файлы
zabbix_server_password.txt и zabbix_server_password_hash.txt.
В скриптах ansible читает эти файлы, записывет хеш пароля напрямую в базу данных Zabbix, а также использует
этот пароль при регистрации хостов агентов в сервере Zabbix.
В файле .gitignore задана маска, исключающая передачу этих файлов в репозиторий github. 

Доступ в веб-интерфейс Kibana настроен под логином elastic. Пароль этого логина извлекается скриптом ansible после установки 
Elasticsearch и записывается в локальный файл es_elastic_password.txt. Этот файл используется при развертывании
на веб-серверах службы filebeat.
В файле .gitignore задана маска, исключающая передачу файлf в репозиторий github. 

Доступ сервера Kibana в сервер Elasticsearch настроен под логином kibana_system. Пароль этого логина извлекается скриптом
ansible после установки Elasticsearch и записывается в локальный файл es_kibana_system_password.txt.
Этот файл используется при развертывании сервера Kibana.
В файле .gitignore задана маска, исключающая передачу файлf в репозиторий github. 

### Конфигурирование Ansible

Файл конфигурации по умолчанию [ansible.cfg](ansible.cfg), созданный командой ansible-config init --disabled > ansible.cfg,
был корректирован:
- inventory=./hosts.ini # расположение файла с данными inventory
- host_key_checking=False # подавление запросов ssh при подключении неизвестных хостов
- interpreter_python=auto_silent # подавление предупреждения о версии Python interpreter
- remote_user=ubuntu # логин удаленного пользователя на ВМ не совпадает с моим текущим логином
- pipelining=True # для предотвращения ошибки создания БД (установка прав в каталоге tmp)

### Развертывание инфраструктуры

1. Создать объекты Yandex Cloud:

```
terraform apply
```

Описание файлов terraform для создания объектов Yandex Cloud:

- [balancer.tf](balancer.tf) - создать балансировщик, вывести на консоль его публичный IP-адрес
- [inventory.tf](inventory.tf) - создать файл hosts.ini как файл inventory для Ansible
- [network.tf](network.tf) - создать объекты сети и группы безопасности
- [providers.tf](providers.tf) - настроить провайдер Terraform и способ авторизации в Yandex Cloud
- [snapshots.tf](snapshots.tf) - создать snapshots
- [variables.tf](variables.tf) - декларировать переменные
- [vms.tf](vms.tf) - создать ВМ, вывести на консоль их публичные и внутренние IP-адреса
- [terraform.tfvars](terraform.tfvars) - хранить переменные

2. Обновить локально SSH ключи для группы хостов:
ansible-playbook ssh_reset.yml

3. Развернуть серверы nginx на ВМ web-a и web-b:
```
ansible-playbook nginx_install.yml
```

4. Развернуть серверы Elasticsearch и Kibana на ВМ kibana и es:
```
ansible-playbook docker_install.yml
ansible-playbook es_deploy.yml
ansible-playbook kibana_deploy.yml
```

5. Развернуть Filebeat на ВМ filebeat:
```
ansible-playbook filebeat_deploy.yml
ansible-playbook filebeat_init.yml
```

6. Развернуть сервер Zabbix на ВМ zabbix и агенты Zabbix на всех остальных ВМ:
```
ansible-playbook zabbix_server_install.yml
ansible-playbook zabbix_agent_install.yml
ansible-playbook zabbix_hosts_add.yml
```

7. Войти на сервер Zabbix и вручную добавить опрос статуса веб-серверов:
Data collection/Hosta/Server web-a/Templates=Nginx by HTTP (из группы Templates/Applications),
возможно установить <макрос>=<имя сервера>


### Проверка работы инфраструктуры

1. Проверить готовность балансировщика и веб-серверов:
```
http://<IP балансировщика>
```
где <IP балансировщика> выводит команда "terraform apply" в строке «balancer_public_ip».

2. Проверить работоспособность сервера Zabbix:
```
http://<IP сервера Zabbix>/zabbix
```
где <IP сервера Zabbix> выводит команда "terraform apply" в строке «zabbix_public_ip =».
Настроен вход с логином Admin, пароль сохранен в локальном файле zabbix_server_password.txt.
В веб-интерфейсе для просмотра dashbords войти в Monitoring/Hosts/Server xxxxx/Dashboards.

3. Проверить работоспособность сервера Kibana:
```
http://<IP сервера Kibana>:5601
```
где <IP сервера Kibana> выводит команда "terraform apply" в строке «kibana_public_ip =».
Настроен вход с логином elastic, пароль сохранен в локальном файле es_elastic_password.txt.

### Уничтожение инфраструктуры

```
terraform destroy
```
