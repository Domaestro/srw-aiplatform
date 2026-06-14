"""End-to-end smoke test for the MLflow + MinIO + PostgreSQL pipeline.

Logs a parameter, a metric, and a small artifact to MLflow. The artifact ends up in
the mlflow-artifacts bucket on MinIO; metadata is stored in the postgres backend.

Run from a pod inside the mlflow namespace (so NetworkPolicy lets it reach MLflow
and MinIO). The platform CA is mounted at /etc/ssl/aiplatform/ca.crt.
"""
import os
import sys

import mlflow


def main() -> int:
    mlflow.set_tracking_uri(os.environ["MLFLOW_TRACKING_URI"])
    mlflow.set_experiment("smoke")

    with mlflow.start_run() as run:
        mlflow.log_param("backend", "postgresql")
        mlflow.log_param("artifact_store", "minio-s3")
        mlflow.log_metric("rmse", 0.123)
        mlflow.log_metric("accuracy", 0.97)

        artifact_path = "/tmp/smoke.txt"
        with open(artifact_path, "w", encoding="utf-8") as f:
            f.write("e2e smoke artifact for Iter 3\n")
        mlflow.log_artifact(artifact_path)

        print(f"run_id={run.info.run_id}")
        print(f"artifact_uri={run.info.artifact_uri}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
