from __future__ import annotations

import base64
import json
import os
import tempfile

import boto3
import structlog
from botocore.signers import RequestSigner
from kubernetes import client as k8s_client
from strands import tool

logger = structlog.get_logger()

_cluster_name = os.environ.get("EKS_CLUSTER_NAME", "")
_region = os.environ.get("AWS_REGION", "ap-northeast-1")

_cluster_endpoint: str | None = None
_ca_cert_path: str | None = None


def _ensure_cluster_info() -> None:
    global _cluster_endpoint, _ca_cert_path
    if _cluster_endpoint:
        return

    eks = boto3.client("eks", region_name=_region)
    cluster = eks.describe_cluster(name=_cluster_name)["cluster"]
    _cluster_endpoint = cluster["endpoint"]

    ca_data = base64.b64decode(cluster["certificateAuthority"]["data"])
    f = tempfile.NamedTemporaryFile(delete=False, suffix=".crt")
    f.write(ca_data)
    f.close()
    _ca_cert_path = f.name

    logger.info("EKS cluster info cached", cluster=_cluster_name, endpoint=_cluster_endpoint)


def _get_token() -> str:
    session = boto3.session.Session()
    sts = session.client("sts", region_name=_region)
    signer = RequestSigner(
        sts.meta.service_model.service_id, _region, "sts", "v4",
        session.get_credentials(), session.events,
    )
    url = signer.generate_presigned_url(
        {
            "method": "GET",
            "url": f"https://sts.{_region}.amazonaws.com/?Action=GetCallerIdentity&Version=2011-06-15",
            "body": {},
            "headers": {"x-k8s-aws-id": _cluster_name},
            "context": {},
        },
        region_name=_region,
        expires_in=900,
        operation_name="",
    )
    return "k8s-aws-v1." + base64.urlsafe_b64encode(url.encode()).decode().rstrip("=")


def _api_client() -> k8s_client.ApiClient:
    _ensure_cluster_info()
    config = k8s_client.Configuration()
    config.host = _cluster_endpoint
    config.verify_ssl = True
    config.ssl_ca_cert = _ca_cert_path
    config.api_key = {"authorization": f"Bearer {_get_token()}"}
    return k8s_client.ApiClient(config)


@tool
def k8s_get_pods(namespace: str = "") -> str:
    """List pods in the EKS cluster. Leave namespace empty to list across all namespaces."""
    v1 = k8s_client.CoreV1Api(_api_client())
    pods = v1.list_pod_for_all_namespaces() if not namespace else v1.list_namespaced_pod(namespace)

    results = []
    for pod in pods.items:
        restarts = sum(cs.restart_count for cs in (pod.status.container_statuses or []))
        results.append({
            "namespace": pod.metadata.namespace,
            "name": pod.metadata.name,
            "status": pod.status.phase,
            "restarts": restarts,
            "node": pod.spec.node_name,
            "created": str(pod.metadata.creation_timestamp),
        })
    return json.dumps(results, ensure_ascii=False)


@tool
def k8s_get_deployments(namespace: str = "") -> str:
    """List deployments in the EKS cluster. Leave namespace empty to list across all namespaces."""
    apps = k8s_client.AppsV1Api(_api_client())
    deps = (
        apps.list_deployment_for_all_namespaces()
        if not namespace
        else apps.list_namespaced_deployment(namespace)
    )

    results = []
    for d in deps.items:
        results.append({
            "namespace": d.metadata.namespace,
            "name": d.metadata.name,
            "replicas": d.spec.replicas,
            "ready": d.status.ready_replicas or 0,
            "available": d.status.available_replicas or 0,
            "image": d.spec.template.spec.containers[0].image if d.spec.template.spec.containers else None,
            "created": str(d.metadata.creation_timestamp),
        })
    return json.dumps(results, ensure_ascii=False)


@tool
def k8s_get_pod_logs(pod_name: str, namespace: str = "default", tail_lines: int = 100) -> str:
    """Get logs from a pod. Returns the last tail_lines lines."""
    v1 = k8s_client.CoreV1Api(_api_client())
    return v1.read_namespaced_pod_log(pod_name, namespace, tail_lines=tail_lines)


@tool
def k8s_describe_pod(pod_name: str, namespace: str = "default") -> str:
    """Get detailed information about a specific pod including conditions and container statuses."""
    v1 = k8s_client.CoreV1Api(_api_client())
    pod = v1.read_namespaced_pod(pod_name, namespace)

    containers = []
    for cs in pod.status.container_statuses or []:
        state = "unknown"
        if cs.state.running:
            state = "running"
        elif cs.state.waiting:
            state = f"waiting: {cs.state.waiting.reason}"
        elif cs.state.terminated:
            state = f"terminated: {cs.state.terminated.reason}"
        containers.append({
            "name": cs.name,
            "ready": cs.ready,
            "state": state,
            "restarts": cs.restart_count,
            "image": cs.image,
        })

    conditions = [
        {"type": c.type, "status": c.status, "reason": c.reason, "message": c.message}
        for c in (pod.status.conditions or [])
    ]

    result = {
        "namespace": pod.metadata.namespace,
        "name": pod.metadata.name,
        "status": pod.status.phase,
        "node": pod.spec.node_name,
        "ip": pod.status.pod_ip,
        "created": str(pod.metadata.creation_timestamp),
        "labels": pod.metadata.labels,
        "containers": containers,
        "conditions": conditions,
    }
    return json.dumps(result, ensure_ascii=False)


@tool
def k8s_get_events(namespace: str = "", limit: int = 30) -> str:
    """Get recent Kubernetes events. Useful for troubleshooting pod scheduling and startup issues."""
    v1 = k8s_client.CoreV1Api(_api_client())
    events = (
        v1.list_event_for_all_namespaces(limit=limit)
        if not namespace
        else v1.list_namespaced_event(namespace, limit=limit)
    )

    results = []
    for e in events.items:
        results.append({
            "namespace": e.metadata.namespace,
            "type": e.type,
            "reason": e.reason,
            "object": f"{e.involved_object.kind}/{e.involved_object.name}",
            "message": e.message,
            "count": e.count,
            "last_seen": str(e.last_timestamp),
        })
    return json.dumps(results, ensure_ascii=False)


@tool
def k8s_get_services(namespace: str = "") -> str:
    """List services in the EKS cluster."""
    v1 = k8s_client.CoreV1Api(_api_client())
    svcs = (
        v1.list_service_for_all_namespaces()
        if not namespace
        else v1.list_namespaced_service(namespace)
    )

    results = []
    for s in svcs.items:
        results.append({
            "namespace": s.metadata.namespace,
            "name": s.metadata.name,
            "type": s.spec.type,
            "cluster_ip": s.spec.cluster_ip,
            "ports": [
                {"port": p.port, "target_port": str(p.target_port), "protocol": p.protocol}
                for p in (s.spec.ports or [])
            ],
        })
    return json.dumps(results, ensure_ascii=False)


@tool
def k8s_get_nodes() -> str:
    """List nodes in the EKS cluster with resource status."""
    v1 = k8s_client.CoreV1Api(_api_client())
    nodes = v1.list_node()

    results = []
    for n in nodes.items:
        conditions = {c.type: c.status for c in (n.status.conditions or [])}
        results.append({
            "name": n.metadata.name,
            "ready": conditions.get("Ready", "Unknown"),
            "instance_type": n.metadata.labels.get("node.kubernetes.io/instance-type", ""),
            "zone": n.metadata.labels.get("topology.kubernetes.io/zone", ""),
            "capacity_cpu": n.status.capacity.get("cpu", ""),
            "capacity_memory": n.status.capacity.get("memory", ""),
            "created": str(n.metadata.creation_timestamp),
        })
    return json.dumps(results, ensure_ascii=False)


k8s_tools = [
    k8s_get_pods,
    k8s_get_deployments,
    k8s_get_pod_logs,
    k8s_describe_pod,
    k8s_get_events,
    k8s_get_services,
    k8s_get_nodes,
]
