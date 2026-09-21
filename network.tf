// Создать VPC Network
resource "yandex_vpc_network" "student" {
  name = "student-fops-${var.flow}"
}

// Создать VPC NAT Gateway
resource "yandex_vpc_gateway" "nat_gw" {
  name = "fops-gateway-${var.flow}"
  shared_egress_gateway {}
}

// Создать VPC Route Table (web-a, web-b to the Internet via NAT)
resource "yandex_vpc_route_table" "rt" {
  name       = "fops-route-table-${var.flow}"
  network_id = yandex_vpc_network.student.id
  static_route {
    destination_prefix = "0.0.0.0/0"
    gateway_id         = yandex_vpc_gateway.nat_gw.id
  }
}

// Константы подсетей
locals {
  subnets_config = {
    "subnet-a" = {
      zone           = "ru-central1-a"
      v4_cidr_blocks = ["10.0.1.0/24"]
    }
    "subnet-b" = {
      zone           = "ru-central1-b"
      v4_cidr_blocks = ["10.0.2.0/24"]
    }
  }
}

// Создать VPC Subnet (zone a, b)
resource "yandex_vpc_subnet" "snet" {
  for_each = local.subnets_config

  name           = "student-fops-${var.flow}-${each.value.zone}"
  zone           = each.value.zone
  v4_cidr_blocks = each.value.v4_cidr_blocks
  network_id     = yandex_vpc_network.student.id
  route_table_id = yandex_vpc_route_table.rt.id
}


// =========================== Группа безопасности для ВМ Bastion
resource "yandex_vpc_security_group" "bastion_sg" {
  name       = "bastion-sg-${var.flow}"
  network_id = yandex_vpc_network.student.id

  ingress {
    protocol       = "TCP"
    description    = "Входящий ssh из интернета "
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 22
  }

  egress {
    protocol       = "TCP"
    description    = "Исходящий ssh во внутреннюю сеть"
    v4_cidr_blocks = [for subnet in local.subnets_config : subnet.v4_cidr_blocks[0]]
    port           = 22
  }

  egress {
    protocol       = "ANY"
    description    = "Исходящий через NAT-шлюз (для скачивания пакетов/обновлений)"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }

  ingress {
    protocol       = "TCP"
    description    = "Для приема входящих запросов от сервера Zabbix (Passive checks)"
    v4_cidr_blocks = [for subnet in local.subnets_config : subnet.v4_cidr_blocks[0]]
    port           = 10050
  }

  egress {
    protocol       = "TCP"
    description    = "Для передачи данных на сервер Zabbix (Active checks)"
    v4_cidr_blocks = [for subnet in local.subnets_config : subnet.v4_cidr_blocks[0]]
    port           = 10051
  }
}


// =========================== Группа безопасности для ВМ Web servers
resource "yandex_vpc_security_group" "web-servers-sg" {
  name       = "web-servers-sg-${var.flow}"
  network_id = yandex_vpc_network.student.id

  ingress {
    protocol          = "TCP"
    description       = "Запросы ИСКЛЮЧИТЕЛЬНО из группы безопасности балансировщика"
    security_group_id = yandex_vpc_security_group.alb_sg.id
    port              = 80
  }

  ingress {
    protocol          = "TCP"
    description       = "Запросы от ВМ zabbix на получение статуса nginx"
    security_group_id = yandex_vpc_security_group.zabbix_sg.id
    port              = 80
  }

  ingress {
    protocol          = "TCP"
    description       = "Подключение ssh с ВМ bastion"
    security_group_id = yandex_vpc_security_group.bastion_sg.id
    port              = 22
  }

  egress {
    protocol       = "ANY"
    description    = "Исходящий через NAT-шлюз (для скачивания пакетов/обновлений)"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }

  ingress {
    protocol       = "TCP"
    description    = "Для приема входящих запросов от сервера Zabbix (Passive checks)"
    v4_cidr_blocks = [for subnet in local.subnets_config : subnet.v4_cidr_blocks[0]]
    port           = 10050
  }

  egress {
    protocol       = "TCP"
    description    = "Для передачи данных на сервер Zabbix (Active checks)"
    v4_cidr_blocks = [for subnet in local.subnets_config : subnet.v4_cidr_blocks[0]]
    port           = 10051
  }

  egress {
    protocol       = "TCP"
    description    = "Для подключения к Kibana (для загрузки дашбордов)"
    v4_cidr_blocks = [for subnet in local.subnets_config : subnet.v4_cidr_blocks[0]]
    port           = 5601
  }

  egress {
    protocol       = "TCP"
    description    = "Для отправки данных в Elasticsearch"
    v4_cidr_blocks = [for subnet in local.subnets_config : subnet.v4_cidr_blocks[0]]
    port           = 9200
  }
}


// =========================== Группа безопасности для Application load balancer
resource "yandex_vpc_security_group" "alb_sg" {
  name       = "alb-sg-${var.flow}"
  network_id = yandex_vpc_network.student.id

  ingress {
    protocol       = "TCP"
    description    = "Разрешить клиентам подключаться к балансировщику (HTTP)"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 80
  }

  # (Внутренний балансировщик Яндекса проверяет доступность узлов ALB с этих адресов)
  ingress {
    protocol          = "TCP"
    description       = "Для проверки состояния нод самого балансировщика"
    predefined_target = "loadbalancer_healthchecks"
    from_port         = 30000
    to_port           = 32767
  }

  egress {
    protocol       = "TCP"
    description    = "Разрешить балансировщику отправлять запросы на веб-серверы"
    v4_cidr_blocks = [for subnet in local.subnets_config : subnet.v4_cidr_blocks[0]]
    port           = 80 # Порт, на котором слушает приложение
  }

  egress {
    protocol       = "ANY"
    description    = "Разрешить балансировщику отправлять ответы и запросы"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }
}


// =========================== Группа безопасности для ВМ Zabbix server
resource "yandex_vpc_security_group" "zabbix_sg" {
  name       = "zabbix-sg-${var.flow}"
  network_id = yandex_vpc_network.student.id

  ingress {
    protocol       = "TCP"
    description    = "Входящий TCP на порт HTTP с любых адресов"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 80
  }

  ingress {
    protocol          = "TCP"
    description       = "Подключение ssh с ВМ bastion"
    security_group_id = yandex_vpc_security_group.bastion_sg.id
    port              = 22
  }

  egress {
    protocol       = "TCP"
    description    = "Запросы от ВМ zabbix на получение статуса nginx"
    v4_cidr_blocks = [for subnet in local.subnets_config : subnet.v4_cidr_blocks[0]]
    port           = 80
  }

  egress {
    protocol       = "ANY"
    description    = "Исходящий через NAT-шлюз (для скачивания пакетов/обновлений)"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }

  ingress {
    protocol       = "TCP"
    description    = "Для приема входящих запросов от агентов Zabbix (Active checks)"
    v4_cidr_blocks = [for subnet in local.subnets_config : subnet.v4_cidr_blocks[0]]
    port           = 10051
  }

  egress {
    protocol       = "TCP"
    description    = "Для отправки запросов на агенты Zabbix (Passive checks)"
    v4_cidr_blocks = [for subnet in local.subnets_config : subnet.v4_cidr_blocks[0]]
    port           = 10050
  }
}


// =========================== Группа безопасности для ВМ Kibana
resource "yandex_vpc_security_group" "kibana_sg" {
  name       = "kibana-sg-${var.flow}"
  network_id = yandex_vpc_network.student.id

  ingress {
    protocol       = "TCP"
    description    = "Входящий TCP на порт HTTP с любых адресов"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 5601
  }

  ingress {
    protocol       = "TCP"
    description    = "Настройка kibana со стороны filebeat на web-серверах (нужна для загрузки дашбордов)"
    v4_cidr_blocks = [for subnet in local.subnets_config : subnet.v4_cidr_blocks[0]]
    port           = 5601
  }

  egress {
    protocol          = "TCP"
    description       = "Для запросов REST API к Elasticsearch"
    security_group_id = yandex_vpc_security_group.es_sg.id
    port              = 9200
  }

  ingress {
    protocol          = "TCP"
    description       = "Подключение ssh с ВМ bastion"
    security_group_id = yandex_vpc_security_group.bastion_sg.id
    port              = 22
  }

  egress {
    protocol       = "ANY"
    description    = "Исходящий через NAT-шлюз (для скачивания пакетов/обновлений)"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }

  ingress {
    protocol       = "TCP"
    description    = "Для приема входящих запросов от сервера Zabbix (Passive checks)"
    v4_cidr_blocks = [for subnet in local.subnets_config : subnet.v4_cidr_blocks[0]]
    port           = 10050
  }

  egress {
    protocol       = "TCP"
    description    = "Для передачи данных на сервер Zabbix (Active checks)"
    v4_cidr_blocks = [for subnet in local.subnets_config : subnet.v4_cidr_blocks[0]]
    port           = 10051
  }
}


// =========================== Группа безопасности для ВМ Elasticsearch
resource "yandex_vpc_security_group" "es_sg" {
  name       = "es-sg-${var.flow}"
  network_id = yandex_vpc_network.student.id

  ingress {
    protocol       = "TCP"
    description    = "Для настройки со стороны веб-серверов отправки данных в Elasticsearch"
    v4_cidr_blocks = [for subnet in local.subnets_config : subnet.v4_cidr_blocks[0]]
    port           = 9200
  }

  ingress {
    protocol          = "TCP"
    description       = "Подключение ssh с ВМ bastion"
    security_group_id = yandex_vpc_security_group.bastion_sg.id
    port              = 22
  }

  egress {
    protocol       = "ANY"
    description    = "Исходящий через NAT-шлюз (для скачивания пакетов/обновлений)"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }

  ingress {
    protocol       = "TCP"
    description    = "Для приема входящих запросов от сервера Zabbix (Passive checks)"
    v4_cidr_blocks = [for subnet in local.subnets_config : subnet.v4_cidr_blocks[0]]
    port           = 10050
  }

  egress {
    protocol       = "TCP"
    description    = "Для передачи данных на сервер Zabbix (Active checks)"
    v4_cidr_blocks = [for subnet in local.subnets_config : subnet.v4_cidr_blocks[0]]
    port           = 10051
  }
}
