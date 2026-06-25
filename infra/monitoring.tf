locals {
  monitoring_dir = abspath("${path.module}/../monitoring")
}

resource "docker_image" "prometheus" {
  name         = "prom/prometheus:v2.48.0"
  keep_locally = false
}

resource "docker_container" "prometheus" {
  name    = "prometheus"
  image   = docker_image.prometheus.image_id
  restart = "unless-stopped"

  networks_advanced {
    name = docker_network.cicd.name
  }

  ports {
    internal = 9090
    external = 9090
  }

  volumes {
    host_path      = "${local.monitoring_dir}/prometheus.yml"
    container_path = "/etc/prometheus/prometheus.yml"
    read_only      = true
  }

  volumes {
    host_path      = "${local.monitoring_dir}/alerts.yml"
    container_path = "/etc/prometheus/alerts.yml"
    read_only      = true
  }

  command = [
    "--config.file=/etc/prometheus/prometheus.yml",
    "--storage.tsdb.path=/prometheus",
    "--web.enable-lifecycle",
  ]
}

resource "docker_image" "grafana" {
  name         = "grafana/grafana:10.2.0"
  keep_locally = false
}

resource "docker_container" "grafana" {
  name    = "grafana"
  image   = docker_image.grafana.image_id
  restart = "unless-stopped"

  networks_advanced {
    name = docker_network.cicd.name
  }

  ports {
    internal = 3000
    external = 3000
  }

  env = [
    "GF_SECURITY_ADMIN_USER=admin",
    "GF_SECURITY_ADMIN_PASSWORD=admin",
    "GF_USERS_ALLOW_SIGN_UP=false",
  ]

  depends_on = [docker_container.prometheus]
}
