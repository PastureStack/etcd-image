#!/bin/bash
set -euo pipefail

candidate_image=${ETCD_IMAGE:-pasturestack/etcd-image:v3.7.2}
baseline_image=${ETCD_BASELINE_IMAGE:-pasturestack/etcd-image-baseline:v3.6.14}
init_image=${ETCD_INIT_IMAGE:-ubuntu:26.04@sha256:678c6550cc43645e08669028bc177f50be4e7c5b8cca677067b1914d4afc7a03}
evidence_dir=${ETCD_IMAGE_EVIDENCE_DIR:-dist/data-lifecycle}
run_id=${GITHUB_RUN_ID:-local}
suffix="${run_id}-$$"
member_name=pasturestack-lifecycle
container_name="pasturestack-etcd-lifecycle-${suffix}"
data_volume="pasturestack-etcd-data-${suffix}"
restore_volume="pasturestack-etcd-restore-${suffix}"

mkdir -p "${evidence_dir}"

cleanup() {
    docker rm -f "${container_name}" >/dev/null 2>&1 || true
    docker volume rm -f "${data_volume}" "${restore_volume}" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

initialize_volume() {
    local volume_name=$1
    docker volume create "${volume_name}" >/dev/null
    docker run --rm --network none --user 0:0 \
        --entrypoint /usr/bin/chown \
        -v "${volume_name}:/data" \
        "${init_image}" 65532:65532 /data
}

start_member() {
    local image=$1
    local volume_name=$2
    local data_dir=$3
    docker run --detach --network none --name "${container_name}" \
        -v "${volume_name}:/var/lib/etcd" \
        "${image}" \
        --name="${member_name}" \
        --data-dir="${data_dir}" \
        --listen-client-urls=http://127.0.0.1:2379 \
        --advertise-client-urls=http://127.0.0.1:2379 \
        --listen-peer-urls=http://127.0.0.1:2380 \
        --initial-advertise-peer-urls=http://127.0.0.1:2380 \
        --initial-cluster="${member_name}=http://127.0.0.1:2380" \
        --initial-cluster-state=new >/dev/null
}

stop_member() {
    docker rm -f "${container_name}" >/dev/null
}

wait_healthy() {
    local healthy=0
    for _ in $(seq 1 60); do
        if docker exec "${container_name}" \
            /usr/local/bin/etcdctl --endpoints=http://127.0.0.1:2379 \
            endpoint health >/dev/null 2>&1; then
            healthy=1
            break
        fi
        sleep 1
    done
    if [ "${healthy}" -ne 1 ]; then
        docker logs "${container_name}" >&2 || true
        echo ETCD_IMAGE_MEMBER_NOT_HEALTHY >&2
        exit 1
    fi
}

wait_for_log() {
    local expected=$1
    local evidence_file=$2
    local found=0
    for _ in $(seq 1 60); do
        docker logs "${container_name}" > "${evidence_file}" 2>&1 || true
        if grep -Fq "${expected}" "${evidence_file}"; then
            found=1
            break
        fi
        sleep 1
    done
    if [ "${found}" -ne 1 ]; then
        cat "${evidence_file}" >&2 || true
        echo "ETCD_IMAGE_EXPECTED_LOG_NOT_FOUND expected=${expected}" >&2
        exit 1
    fi
}

etcdctl() {
    docker exec "${container_name}" \
        /usr/local/bin/etcdctl --endpoints=http://127.0.0.1:2379 "$@"
}

etcdutl() {
    docker exec "${container_name}" /usr/local/bin/etcdutl "$@"
}

canonical_data() {
    etcdctl get '' --from-key --write-out=json | \
        jq -c '[.kvs[]? | {key:.key,value:.value}] | sort_by(.key)'
}

data_sha256() {
    canonical_data | sha256sum | awk '{print $1}'
}

data_count() {
    etcdctl get '' --from-key --write-out=json | jq -r '.count'
}

initialize_volume "${data_volume}"
initialize_volume "${restore_volume}"

start_member "${baseline_image}" "${data_volume}" /var/lib/etcd/default.etcd
wait_healthy
for index in $(seq -w 1 100); do
    etcdctl put "pasturestack/key-${index}" "value-${index}" >/dev/null
done
baseline_count=$(data_count)
baseline_sha256=$(data_sha256)
test "${baseline_count}" -eq 100
etcdctl snapshot save /var/lib/etcd/baseline.snapshot >/dev/null
etcdutl --write-out=json snapshot status /var/lib/etcd/baseline.snapshot \
    > "${evidence_dir}/baseline-snapshot-status.json"
stop_member

start_member "${candidate_image}" "${data_volume}" /var/lib/etcd/default.etcd
wait_healthy
candidate_count=$(data_count)
candidate_sha256=$(data_sha256)
test "${candidate_count}" -eq 100
test "${candidate_sha256}" = "${baseline_sha256}"
etcdctl put pasturestack/post-upgrade retained-after-reviewed-downgrade >/dev/null
etcdctl downgrade validate 3.6 > "${evidence_dir}/downgrade-validate.txt"
etcdctl downgrade enable 3.6 > "${evidence_dir}/downgrade-enable.txt"
wait_for_log 'The server is ready to downgrade' \
    "${evidence_dir}/candidate-downgrade-ready.log"
post_upgrade_count=$(data_count)
test "${post_upgrade_count}" -eq 101
stop_member

start_member "${baseline_image}" "${data_volume}" /var/lib/etcd/default.etcd
wait_healthy
wait_for_log 'the cluster has been downgraded' \
    "${evidence_dir}/baseline-downgrade-complete.log"
rollback_count=$(data_count)
rollback_sha256=$(data_sha256)
test "${rollback_count}" -eq 101
test "$(etcdctl get pasturestack/post-upgrade --print-value-only)" = retained-after-reviewed-downgrade
stop_member

docker run --rm --network none \
    --entrypoint /usr/local/bin/etcdutl \
    -v "${data_volume}:/source:ro" \
    -v "${restore_volume}:/restore" \
    "${candidate_image}" snapshot restore /source/baseline.snapshot \
    --data-dir=/restore/default.etcd \
    > "${evidence_dir}/snapshot-restore.txt"

start_member "${candidate_image}" "${restore_volume}" /var/lib/etcd/default.etcd
wait_healthy
restore_count=$(data_count)
restore_sha256=$(data_sha256)
test "${restore_count}" -eq 100
test "${restore_sha256}" = "${baseline_sha256}"
test -z "$(etcdctl get pasturestack/post-upgrade --print-value-only)"
etcdctl endpoint status --write-out=json > "${evidence_dir}/restored-endpoint-status.json"
stop_member

cat > "${evidence_dir}/result.env" <<EOF
status=passed
baseline_version=3.6.14
candidate_version=3.7.2
baseline_key_count=${baseline_count}
candidate_key_count=${candidate_count}
rollback_key_count=${rollback_count}
restore_key_count=${restore_count}
baseline_sha256=${baseline_sha256}
candidate_sha256=${candidate_sha256}
rollback_sha256=${rollback_sha256}
restore_sha256=${restore_sha256}
downgrade_target=3.6
snapshot_restore=passed
EOF

grep -Fx status=passed "${evidence_dir}/result.env"
grep -Fx candidate_version=3.7.2 "${evidence_dir}/result.env"
