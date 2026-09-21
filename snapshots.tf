
resource "yandex_compute_snapshot_schedule" "daily_snapshot_schedule1" {
  name        = "fops-daily-seven-days-retention-${var.flow}"
  description = "Ежедневный бэкап загрузочных дисков в 3:45 МСК (7 дней хранение)"

  schedule_policy {
    expression = "45 0 * * *"
  }

  # Время жизни снапшота — 7 дней (168 часов)
  retention_period = "168h"

  # Обходим все ВМ в единой структуре for_each и забираем их загрузочные диски
  disk_ids = [for k, instance in yandex_compute_instance.vm : instance.boot_disk.0.disk_id]

  snapshot_spec {
    description = "Автоматический снапшот по расписанию"
    labels = {
      environment = "${var.flow}"
      managed-by  = "terraform"
    }
  }
}
