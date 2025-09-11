resource "null_resource" "this" {
  triggers = var.triggers
  provisioner "local-exec" {
    interpreter = local.is_linux ? [] : ["PowerShell", "-Command", ""]
    command     = local.is_linux ? replace(local.linux_command, "\r\n", "\n") : local.windows_command
  }
}
