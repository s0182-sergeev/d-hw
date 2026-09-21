
// Создать файл hosts.ini на управляющем хосте в текущем каталоге
resource "local_file" "inventory" {
  content  = <<-XYZ
    [balancer]
    ${try(yandex_alb_load_balancer.balancer1.listener[0].endpoint[0].address[0].external_ipv4_address[0].address, "")}

    [bastion]
    ${try(yandex_compute_instance.vm["bastion"].network_interface.0.nat_ip_address, "")}
    # ssh ubuntu@${try(yandex_compute_instance.vm["bastion"].network_interface.0.nat_ip_address, "")}
    # ${try(yandex_compute_instance.vm["bastion"].network_interface.0.ip_address, "")}

    [web_servers]
    ${try(yandex_compute_instance.vm["web-a"].hostname, "")}
    # ssh ubuntu@web-a -J ubuntu@${try(yandex_compute_instance.vm["bastion"].network_interface.0.nat_ip_address, "")}
    # ${try(yandex_compute_instance.vm["web-a"].network_interface.0.ip_address, "")}

    ${try(yandex_compute_instance.vm["web-b"].hostname, "")}
    # ssh ubuntu@web-b -J ubuntu@${try(yandex_compute_instance.vm["bastion"].network_interface.0.nat_ip_address, "")}
    # ${try(yandex_compute_instance.vm["web-b"].network_interface.0.ip_address, "")}

    [web_servers:vars]
    ansible_ssh_common_args='-o ProxyCommand="ssh -p 22 -W %h:%p -q ubuntu@${try(yandex_compute_instance.vm["bastion"].network_interface.0.nat_ip_address, "")}"'

    [zabbix_servers]
    ${try(yandex_compute_instance.vm["zabbix"].hostname, "")}
    # ssh ubuntu@zabbix -J ubuntu@${try(yandex_compute_instance.vm["bastion"].network_interface.0.nat_ip_address, "")}
    # http://${try(yandex_compute_instance.vm["zabbix"].network_interface.0.nat_ip_address, "")}/zabbix		(user Admin)
    # ${try(yandex_compute_instance.vm["zabbix"].network_interface.0.ip_address, "")}

    [zabbix_servers:vars]
    ansible_ssh_common_args='-o ProxyCommand="ssh -p 22 -W %h:%p -q ubuntu@${try(yandex_compute_instance.vm["bastion"].network_interface.0.nat_ip_address, "")}"'

    [elastic_servers]
    ${try(yandex_compute_instance.vm["es"].hostname, "")}
    # ssh ubuntu@es -J ubuntu@${try(yandex_compute_instance.vm["bastion"].network_interface.0.nat_ip_address, "")}
    # curl -X GET http://${try(yandex_compute_instance.vm["es"].network_interface.0.ip_address, "")}:9200
    # ${try(yandex_compute_instance.vm["es"].network_interface.0.ip_address, "")}

    [elastic_servers:vars]
    ansible_ssh_common_args='-o ProxyCommand="ssh -p 22 -W %h:%p -q ubuntu@${try(yandex_compute_instance.vm["bastion"].network_interface.0.nat_ip_address, "")}"'

    [kibana_servers]
    ${try(yandex_compute_instance.vm["kibana"].hostname, "")}
    # ssh ubuntu@kibana -J ubuntu@${try(yandex_compute_instance.vm["bastion"].network_interface.0.nat_ip_address, "")}
    # http://${try(yandex_compute_instance.vm["kibana"].network_interface.0.nat_ip_address, "")}:5601/		(user elastic)
    # ${try(yandex_compute_instance.vm["kibana"].network_interface.0.ip_address, "")}

    [kibana_servers:vars]
    ansible_ssh_common_args='-o ProxyCommand="ssh -p 22 -W %h:%p -q ubuntu@${try(yandex_compute_instance.vm["bastion"].network_interface.0.nat_ip_address, "")}"'
    XYZ
  filename = "./hosts.ini"
}
