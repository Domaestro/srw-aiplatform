# Ansible-сценарии развёртывания платформы

Сценарии разворачивают полный MVP-прототип защищённой платформы на одной хост-машине, оборачивая bash-скрипты из `../prototype/scripts/` в идемпотентные Ansible-роли. Один проход `ansible-playbook playbooks/site.yaml` приводит хост от чистого Ubuntu 24.04 + Docker до полностью работающего кластера (k3d + cert-manager + MinIO + PostgreSQL + MLflow + Istio + Keycloak + oauth2-proxy + Argo Workflows + Training Operator + kube-prometheus-stack).

## Структура

```
ansible/
├── ansible.cfg                  # отключение host_key_checking и др. для local-exec
├── inventories/local/hosts.yaml # один хост = localhost (connection=local)
├── group_vars/all/main.yaml     # общие переменные (версии чартов, пути)
├── playbooks/site.yaml          # главный playbook (run all roles in order)
├── playbooks/teardown.yaml      # обратное действие — удалить кластер
└── roles/
    ├── prereqs/                 # установка k3d и helm
    ├── cluster/                 # создание k3d-кластера + apply audit-policy/PSA-config
    ├── base/                    # namespaces + ResourceQuota + LimitRange + NetworkPolicy default-deny + RBAC ClusterRoles
    ├── cert_manager/            # cert-manager + local CA
    ├── minio/                   # MinIO standalone + buckets + TLS
    ├── postgresql/              # PostgreSQL для MLflow + Keycloak
    ├── minio_users/             # service-user mlflow-svc в MinIO + secret в mlflow ns
    ├── mlflow/                  # MLflow Tracking server
    ├── istio/                   # Istio control plane + ingress gateway + Gateway resource + wildcard cert
    ├── keycloak/                # Keycloak 26 + realm aiplatform + 3 пользователя/3 роли + OIDC client
    ├── oauth2_proxy/            # oauth2-proxy перед MLflow + VirtualService + CoreDNS override
    ├── argo_workflows/          # Argo Workflows server + controller + ServiceAccount в team-demo
    ├── training_operator/       # Training Operator (PyTorchJob/TFJob/XGBoostJob CRDs)
    └── monitoring/              # kube-prometheus-stack (Prometheus + Grafana + node-exporter + KSM)
```

## Запуск

### Полный bootstrap (с нуля)

```bash
cd ansible
ansible-playbook -i inventories/local/hosts.yaml playbooks/site.yaml
```

Один проход на чистом хосте~---~около 10–15 минут (большая часть~---~pull образов).

### Повторный запуск (idempotent)

```bash
ansible-playbook -i inventories/local/hosts.yaml playbooks/site.yaml
```

Все роли idempotent: при отсутствии изменений ничего не пересоздаётся, секреты не ротируются.

### Удалить только один компонент

```bash
ansible-playbook -i inventories/local/hosts.yaml playbooks/site.yaml --tags mlflow
```

### Полный teardown

```bash
ansible-playbook -i inventories/local/hosts.yaml playbooks/teardown.yaml
```

Удаляет k3d-кластер. Локальные секреты в `prototype/.local/secrets/` сохраняются~---~при повторном bootstrap будут переиспользованы.

## Зависимости

- Ansible 2.16+ (на хосте уже установлен)
- Python 3.10+
- Docker 24+ (на хосте уже установлен)
- Достаточно RAM (16+ ГБ) и места на диске (10+ ГБ)
