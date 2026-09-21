
# Создать целевую группу ВМ
resource "yandex_alb_target_group" "tg_group1" {
  name = "fops-target-group1-${var.flow}"

  # Цикл по ВМ
  dynamic "target" {
    for_each = {
      for k, v in yandex_compute_instance.vm : k => v
      if startswith(v.name, "web-")
    }

    content {
      subnet_id  = one(target.value.network_interface).subnet_id
      ip_address = one(target.value.network_interface).ip_address
    }
  }
}

resource "yandex_alb_backend_group" "be_group1" {
  name = "fops-backend-group1-${var.flow}"

  http_backend {
    name             = "fops-http-backend-group1-${var.flow}"
    weight           = 1
    port             = 80
    target_group_ids = [yandex_alb_target_group.tg_group1.id]

    load_balancing_config {
      panic_threshold = 50
    }

    healthcheck {
      timeout             = "1s"
      interval            = "2s"
      healthy_threshold   = 2
      unhealthy_threshold = 2
      http_healthcheck {
        path = "/"
      }
    }
  }
}

resource "yandex_alb_http_router" "http_router1" {
  name = "fops-http-router1-${var.flow}"
}

resource "yandex_alb_virtual_host" "v_host1" {
  name           = "fops-virtual-host1-${var.flow}"
  http_router_id = yandex_alb_http_router.http_router1.id

  route {
    name = "fops-route1-${var.flow}"
    http_route {
      http_route_action {
        backend_group_id = yandex_alb_backend_group.be_group1.id
        timeout          = "60s"
      }
    }
  }
}

// Создать L7-балансировщик
resource "yandex_alb_load_balancer" "balancer1" {
  name               = "fops-load-balancer1-${var.flow}"
  network_id         = yandex_vpc_network.student.id
  security_group_ids = [yandex_vpc_security_group.alb_sg.id]

  allocation_policy {
    location {
      subnet_id       = yandex_vpc_subnet.snet["subnet-a"].id
      zone_id         = yandex_vpc_subnet.snet["subnet-a"].zone
      disable_traffic = false
    }
    location {
      subnet_id       = yandex_vpc_subnet.snet["subnet-b"].id
      zone_id         = yandex_vpc_subnet.snet["subnet-b"].zone
      disable_traffic = false
    }
  }

  listener {
    name = "fops-listener1-${var.flow}"
    endpoint {
      address {
        external_ipv4_address {
          # Автоматически выделяет публичный IP для балансировщика
        }
      }
      ports = [80]
    }
    http {
      handler {
        http_router_id = yandex_alb_http_router.http_router1.id
      }
    }
  }
}

output "balancer_public_ip" {
  description = "IP address of the application load balancer listener"
  value       = tolist(yandex_alb_load_balancer.balancer1.listener[0].endpoint[0].address[0].external_ipv4_address)[0].address
}
