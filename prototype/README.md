# Прототип защищённой платформы для разработки и обучения моделей ИИ

Прототип MVP по архитектуре, разработанной в этапе №1 НИР.

## Профиль развертывания

- **Кластер:** k3d (k3s в Docker), 1 control-plane + 2 worker узла
- **Service mesh:** Istio (profile=demo, минимальные ресурсы)
- **ML-ядро:** Kubeflow Pipelines + Notebooks + Training Operator
- **Identity:** Keycloak + oauth2-proxy (OIDC)
- **Хранилища:** MinIO (S3-совместимое), PostgreSQL (backend MLflow)
- **Трекинг/реестр моделей:** MLflow
- **Мониторинг:** Prometheus + Grafana
- **TLS:** cert-manager + локальный self-signed CA

## Базовые меры безопасности (закладываются с Iter 1)

- Pod Security Admission = `restricted` для всех пользовательских namespace
- NetworkPolicy default-deny + явные allow-правила
- ResourceQuota и LimitRange на каждый namespace
- Kubernetes RBAC с разделением ролей (Platform Admin / Project Admin / Data Scientist / Viewer)
- Аудит-лог Kubernetes
- TLS на всех ingress и mTLS между сервисами (Istio strict)
- Шифрование MinIO на диске
- Запрет привилегированных контейнеров, hostPath, hostNetwork

## Структура

```
prototype/
├── k3d/                  # конфиг кластера k3d
├── k8s/
│   ├── base/             # базовые манифесты (namespaces, quotas)
│   └── security/         # NetworkPolicy, PSA, RBAC
├── charts/               # values для Helm-чартов сторонних компонентов
├── scripts/              # bootstrap/teardown/проверочные скрипты
├── pipelines/            # примеры ML-пайплайнов для демо
└── README.md
```

## Быстрый старт

```bash
# 1. Установить пререквизиты (k3d, helm)
./scripts/00_install_prereqs.sh

# 2. Поднять кластер
./scripts/01_create_cluster.sh

# 3. Применить базовые манифесты безопасности
./scripts/02_apply_base.sh
```

Дальнейшие шаги добавляются по мере реализации итераций.

## Требования к ресурсам

| Компонент        | RAM (req)  | RAM (limit) |
|------------------|------------|-------------|
| k3d control      | ~500 МБ    | 1 ГБ        |
| Istio (demo)     | ~600 МБ    | 1.5 ГБ      |
| Kubeflow (min)   | ~3 ГБ      | 5 ГБ        |
| Keycloak         | ~500 МБ    | 1 ГБ        |
| MLflow + PG      | ~400 МБ    | 1 ГБ        |
| MinIO            | ~300 МБ    | 1 ГБ        |
| Prometheus       | ~600 МБ    | 1.5 ГБ      |
| **Итого**        | **~6 ГБ**  | **~12 ГБ**  |

На 16 ГБ хост-системе с ~10 ГБ свободной RAM прототип должен работать с некоторым запасом.
