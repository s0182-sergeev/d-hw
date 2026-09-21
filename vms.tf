// Использовать образ Ubuntu 24.04
data "yandex_compute_image" "ubuntu_image_name" {
  family = "ubuntu-2404-lts"
}

// Константы для конфигурирования ВМ
locals {
  vms_config = {
    "bastion" = {
      zone              = yandex_vpc_subnet.snet["subnet-a"].zone
      subnet_id         = yandex_vpc_subnet.snet["subnet-a"].id
      security_group_id = yandex_vpc_security_group.bastion_sg.id
      nat               = true
      memory            = 2
    }
    "web-a" = {
      zone              = yandex_vpc_subnet.snet["subnet-a"].zone
      subnet_id         = yandex_vpc_subnet.snet["subnet-a"].id
      security_group_id = yandex_vpc_security_group.web-servers-sg.id
      nat               = false
      memory            = 2
    }
    "web-b" = {
      zone              = yandex_vpc_subnet.snet["subnet-b"].zone
      subnet_id         = yandex_vpc_subnet.snet["subnet-b"].id
      security_group_id = yandex_vpc_security_group.web-servers-sg.id
      nat               = false
      memory            = 2
    }
    "zabbix" = {
      zone              = yandex_vpc_subnet.snet["subnet-a"].zone
      subnet_id         = yandex_vpc_subnet.snet["subnet-a"].id
      security_group_id = yandex_vpc_security_group.zabbix_sg.id
      nat               = true
      memory            = 2
    }
    "es" = {
      zone              = yandex_vpc_subnet.snet["subnet-a"].zone
      subnet_id         = yandex_vpc_subnet.snet["subnet-a"].id
      security_group_id = yandex_vpc_security_group.es_sg.id
      nat               = false
      memory            = 4
    }
    "kibana" = {
      zone              = yandex_vpc_subnet.snet["subnet-a"].zone
      subnet_id         = yandex_vpc_subnet.snet["subnet-a"].id
      security_group_id = yandex_vpc_security_group.kibana_sg.id
      nat               = true
      memory            = 4
    }
  }
}

// Создать ВМ
resource "yandex_compute_instance" "vm" {
  for_each = local.vms_config

  name        = each.key // VM name in the cloud console
  hostname    = each.key // generates the FQDN hostname; without hostname, a random name will be generated!
  platform_id = "standard-v3"
  zone        = each.value.zone // VM zone must match subnet zone!

  resources {
    cores         = 2
    memory        = each.value.memory
    core_fraction = 20
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu_image_name.image_id
      type     = "network-hdd"
      size     = 10
    }
  }

  metadata = {
    serial-port-enable = 1
    ssh-keys           = "ubuntu:${file("~/.ssh/id_ed30032026.pub")}"
  }

  // прерываемая ВМ
  scheduling_policy { preemptible = true }

  // разрешно измененять свойства ВМ после создания
  //allow_stopping_for_update = true

  network_interface {
    subnet_id          = each.value.subnet_id // VM zone must match subnet zone!
    nat                = each.value.nat
    security_group_ids = [each.value.security_group_id]
  }
}

output "bastion_public_ip" {
  value = try(yandex_compute_instance.vm["bastion"].network_interface.0.nat_ip_address, "")
}

output "bastion_private_ip" {
  value = try(yandex_compute_instance.vm["bastion"].network_interface.0.ip_address, "")
}

output "web-a_private_ip" {
  value = try(yandex_compute_instance.vm["web-a"].network_interface.0.ip_address, "")
}

output "web-b_private_ip" {
  value = try(yandex_compute_instance.vm["web-b"].network_interface.0.ip_address, "")
}

output "zabbix_public_ip" {
  value = try(yandex_compute_instance.vm["zabbix"].network_interface.0.nat_ip_address, "")
}

output "zabbix_private_ip" {
  value = try(yandex_compute_instance.vm["zabbix"].network_interface.0.ip_address, "")
}

output "es_private_ip" {
  value = try(yandex_compute_instance.vm["es"].network_interface.0.ip_address, "")
}

output "kibana_public_ip" {
  value = try(yandex_compute_instance.vm["kibana"].network_interface.0.nat_ip_address, "")
}

output "kibana_private_ip" {
  value = try(yandex_compute_instance.vm["kibana"].network_interface.0.ip_address, "")
}

resource "local_file" "zabbix_server_private_ip" {
  content  = try(yandex_compute_instance.vm["zabbix"].network_interface.0.ip_address, "")
  filename = "${path.module}/zabbix_server_private_ip.txt"
}

resource "local_file" "zabbix_server_public_ip" {
  content  = try(yandex_compute_instance.vm["zabbix"].network_interface.0.nat_ip_address, "")
  filename = "${path.module}/zabbix_server_public_ip.txt"
}

resource "local_file" "es_server_private_ip" {
  content  = try(yandex_compute_instance.vm["es"].network_interface.0.ip_address, "")
  filename = "${path.module}/es_server_private_ip.txt"
}

resource "local_file" "zabbix_server_password" {
  content  = var.zabbix_password
  filename = "${path.module}/zabbix_server_password.txt"
}

resource "local_file" "zabbix_server_password_hash" {
  content  = var.zabbix_server_password_hash
  filename = "${path.module}/zabbix_server_password_hash.txt"
}

resource "local_file" "zabbix_server_db_password" {
  content  = var.zabbix_server_db_password
  filename = "${path.module}/zabbix_server_db_password.txt"
}
