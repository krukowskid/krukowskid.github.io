locals {
  is_linux = length(regexall("^[a-zA-Z]:", abspath(path.root))) == 0

  dns_name = regex("^(?:https?://)?(?:[^@\\n]+@)?([^:/\\n]+)", trimspace(var.dns_name))[0]

  linux_command = <<-EOT
    timeout_seconds=${var.timeout_seconds}
    sleep_seconds=${var.sleep_seconds}
    while [ $timeout_seconds -gt 0 ]; do
      ip=$(getent hosts "${local.dns_name}" | awk '{ print $1 }')
      timeout_seconds=$((timeout_seconds - sleep_seconds))
      if [ "$ip" = "${var.ip_address}" ]; then
        for attempt in $(seq 1 ${var.successful_attempts}); do
          ip=$(getent hosts "${local.dns_name}" | awk '{ print $1 }')
          if [ "$ip" != "${var.ip_address}" ]; then
            break
          fi
          if [ $attempt -eq ${var.successful_attempts} ]; then
            sleep $sleep_seconds
            exit 0
          fi
          sleep 1
        done
      fi
      sleep $sleep_seconds
    done
    exit 1
  EOT

  windows_command = <<-EOT
      $timeoutSeconds = ${var.timeout_seconds}
      $sleepSeconds = ${var.sleep_seconds}
        Do {
          Clear-DnsClientCache
          $ip = ((Resolve-DNSName -Name "${local.dns_name}" -DnsOnly) | Where-Object {$_.Type -eq "A"}).IPAddress
          [int]$timeoutSeconds = [int]$timeoutSeconds - [int]$sleepSeconds
          if ($ip -eq "${var.ip_address}") {
            for ($attempt = 1; $attempt -le ${var.successful_attempts}; $attempt++) {
              Clear-DnsClientCache
              $ip = ((Resolve-DNSName -Name "${local.dns_name}" -DnsOnly) | Where-Object {$_.Type -eq "A"}).IPAddress
              if ($ip -ne "${var.ip_address}") {
                break
              }
              if ($attempt -eq ${var.successful_attempts}) {
                Start-Sleep -Seconds $sleepSeconds
                exit 0
              }
              Start-Sleep -Seconds 1
            }
          }
          Start-Sleep -Seconds $sleepSeconds
        } Until (0 -gt $timeoutSeconds)
        exit 1
    EOT
}
