# Дипломная работа по профессии «Системный администратор» - Сергеев Александр

## Задача

Разработать отказоустойчивую инфраструктуру для сайта, включающую мониторинг, сбор логов и
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
Для имитации сайта создана страница с внутренним IP-адресом и именем ВМ.

ВМ веб-серверов настроены на получение только внутреннего IP-адреса.
Доступ к ВМ по ssh настроен через бастион-сервер.
Доступ к web-порту ВМ настроен через балансировщик Yandex Cloud.
Из внутренней сети доступ web-порту также настроен для сервера Zabbix для получения статуса веб-сервера.

Настройка балансировщика:
- cоздана группа target-group, в нее включены ВМ web-a и web-b;
- cоздана группа backend-group, настроены backends на группу target group, настроен healthcheck на корень (/) и порт 80,
протокол HTTP;
- создан роутер http-router с путем "/" и ссылкой на группу backend group;
- создан L7-балансер application-load-balancer для распределения трафика на два веб-сервера, указан роутер http-router,
задан listener тип auto, порт 80.

### Мониторинг

Создана ВМ (zabbix), в ней развернут сервер Zabbix.
На каждую ВМ инфрраструктуры (bastion, web-a, web-b, es, kibana) установлен Zabbix Agent, настроены агенты на
отправление метрик в Zabbix.
На сервере Zabbix вручную настроены дашборды с отображением метрик по принципу USE (Utilization, Saturation, Errors)
для CPU, RAM, диски, сеть, http запросов к веб-серверам. Применены необходимые tresholds на соответствующие графики.

### Логи
Cоздана ВМ (es), в ней развернута Elasticsearch в контейнере Docker.
На ВМ веб-серверов установлен 2Filebeat в контейнере Docker и настроен на отправку access.log, error.log
сервера nginx в сервер Elasticsearch. При установке Filebeat однократно выполнена загрузка дашбордов в Kibana.
Создана ВМ (kibana), в ней развернут сервер Kibana и настроено соединение с Elasticsearch для чтения данных.

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

### Безопасность инфраструктуры

Доступ terraform в Yandex Cloud настроен по ключу "~/.yandex-cloud_terraform_authorized_key.json"
на локальном хосте. Файл с ключом находится вне рабочего каталога и не передается в github.

Доступ ssh на все ВМ настроен по ключу ~/.ssh/id_ed30032026.pub на локальном хосте.
Terraform копирует файл на ВМ при их создании. Файл с ключом находится вне рабочего каталога и не передается в github.

Доступ ansible в базу данных Zabbix настроен с логином zabbix по предустановленному паролю (15 знаков), который хранится
в файле terraform.tvars. Terraform передает пароль в ansible через локальный файл zabbix_server_db_password.txt.
В файле .gitignore задана маска, исключающая передачу файла в github. 

Доступ в веб-интерфейс Zabbix настроен с логином Admin по предустановленному паролю (15 знаков), который хранится
в файле terraform.tvars. Terraform копирует пароль и его хеш (заранее подготовлен) в локальные файлы
zabbix_server_password.txt и zabbix_server_password_hash.txt.
Ansible при установке сервера Zabbix читает эти файлы и сохраняет хеш прямым обращением в базу данных Zabbix,
а также использует этот пароль при регистрации хостов агентов в сервере Zabbix.
В файле .gitignore задана маска, исключающая передачу файлов в github. 

Доступ в веб-интерфейс Kibana настроен под логином elastic. Ansible извлекает пароль логина после установки 
Elasticsearch и записывается в локальный файл es_elastic_password.txt. Ansible читает этот файл при развертывании
filebeat на веб-серверах.
В файле .gitignore задана маска, исключающая передачу файла в github. 

Доступ сервера Kibana в сервер Elasticsearch настроен под логином kibana_system. Ansible извлекает пароль логина
после установки Elasticsearch и записывается в локальный файл es_kibana_system_password.txt.
Ansible читает этот файл при развертывании сервера Kibana.
В файле .gitignore задана маска, исключающая передачу файлf в github. 

### Конфигурирование Ansible

Файл стандартной конфигурации [ansible.cfg](ansible.cfg), сазданный командой ansible-config init --disabled > ansible.cfg,
дополнительно настроен:

- inventory=./hosts.ini # расположение файла с данными inventory;
- host_key_checking=False # подавление запросов ssh при подключении к неизвестным хостам;
- interpreter_python=auto_silent # подавление предупреждения о версии Python interpreter;
- remote_user=ubuntu # задание логина удаленного пользователя ВМ;
- pipelining=True # предотвращение ошибки создания БД (установка прав в каталоге tmp).

## Работа с инфраструктурой

### Развертывание инфраструктуры

1. Создать объекты Yandex Cloud:

```
terraform apply
```

Описание файлов terraform для создания объектов Yandex Cloud:

- [balancer.tf](balancer.tf) - создать балансировщик, вывести на консоль его публичный IP-адрес;
- [inventory.tf](inventory.tf) - создать файл hosts.ini как файл inventory для Ansible;
- [network.tf](network.tf) - создать объекты сети и группы безопасности;
- [providers.tf](providers.tf) - настроить провайдер Terraform и способ авторизации в Yandex Cloud;
- [snapshots.tf](snapshots.tf) - создать snapshots;
- [variables.tf](variables.tf) - декларировать переменные;
- [vms.tf](vms.tf) - создать ВМ, вывести на консоль их публичные и внутренние IP-адреса;
- terraform.tfvars - хранить переменные (не передается в github).

Время выполнения команды до 7 мин.

2. Развернуть серверы nginx на ВМ web-a и web-b:
```
ansible-playbook nginx_install.yml
```

3. Проверить работоспособность балансировщика и веб-серверов, создать тестовый трафик:
```
while true; do curl http://<IP балансировщика> ; echo ---------- ; sleep 3; done
```

<IP балансировщика> выведен на консоль командой "terraform apply" в строке «balancer_public_ip».

4. Развернуть серверы Elasticsearch и Kibana на ВМ kibana и es:
```
ansible-playbook docker_install.yml
ansible-playbook es_deploy.yml
ansible-playbook kibana_deploy.yml
```

5. Развернуть Filebeat на ВМ web-a и web-b, настроить kibana и es (дашборды):
```
ansible-playbook filebeat_deploy.yml
ansible-playbook filebeat_init.yml
```
Для настройки службы Filebeat применен файл конфигурации [filebeat.yml.j2](filebeat.yml.j2).

6. Проверить работоспособность сервера Kibana 'http://<IP сервера Kibana>:5601'

<IP сервера Kibana> выведен на консоль командой "terraform apply".
Вход с логином elastic, пароль сохранен в локальном файле es_elastic_password.txt.
В Stack management/Data views должен быть пункт filebeat-*.
В Dashboards/"[Filebeat Nginx] Access and error logs ECS" должны быть графики.

7. Установить сервер Zabbix на ВМ zabbix, зарегистрировать хосты, установить агенты Zabbix на всех ВМ:
```
ansible-playbook zabbix_server_install.yml
ansible-playbook zabbix_hosts_add.yml
ansible-playbook zabbix_agent_install.yml
```

8. Настроить дополнительные шаблоны дашбородов для веб-серверов:

Войти на веб-сервер Zabbix 'http://<IP сервера Zabbix>/zabbix' и вручную подготовить дашборды http запросов к веб-серверам:

- в Data collection/Hosts/Server web-a/Host/Templates добавить "Nginx by HTTP" (из группы Templates/Applications);
- в Data collection/Hosts/Server web-b/Host/Templates добавить "Nginx by HTTP" (из группы Templates/Applications);
- в Data collection/Hosts/Server web-a/Macros добавить {$NGINX.STUB_STATUS.HOST}=web-a;
- в Data collection/Hosts/Server web-b/Macros добавить {$NGINX.STUB_STATUS.HOST}=web-b.

<IP сервера Zabbix> выведен командой "terraform apply".
Вход с логином Admin, пароль сохранен в локальном файле zabbix_server_password.txt.
Для просмотра дашбордов войти в Monitoring/Hosts/Server xxxxx/Dashboards.


### Уничтожение инфраструктуры

1. Удалить объекты Terraform:
```
terraform destroy
```

2. Удалить файлы с паролями:
```
rm -f ./*password*.txt
```
