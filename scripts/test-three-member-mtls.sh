#!/bin/bash
set -euo pipefail

candidate_image=${ETCD_IMAGE:-pasturestack/etcd-image:v3.7.2}
init_image=${ETCD_INIT_IMAGE:-ubuntu:26.04@sha256:678c6550cc43645e08669028bc177f50be4e7c5b8cca677067b1914d4afc7a03}
evidence_dir=${ETCD_IMAGE_QUORUM_EVIDENCE_DIR:-dist/quorum-mtls}
run_id=${GITHUB_RUN_ID:-local}
suffix="${run_id}-$$"
network="pasturestack-etcd-quorum-${suffix}"
cert_volume="pasturestack-etcd-certs-${suffix}"
cert_source=$(mktemp -d "${RUNNER_TEMP:-/tmp}/pasturestack-etcd-certs.XXXXXX")
member_names=(member1 member2 member3 member4)
container_prefix="pasturestack-etcd-quorum-${suffix}"
initial_cluster='member1=https://etcd1:2380,member2=https://etcd2:2380,member3=https://etcd3:2380'
replacement_cluster='member1=https://etcd1:2380,member2=https://etcd2:2380,member4=https://etcd4:2380'

mkdir -p "${evidence_dir}"

container_name() {
    printf '%s-%s' "${container_prefix}" "$1"
}

data_volume() {
    printf 'pasturestack-etcd-quorum-data-%s-%s' "${suffix}" "$1"
}

cleanup() {
    local member
    for member in "${member_names[@]}"; do
        docker logs "$(container_name "${member}")" \
            > "${evidence_dir}/${member}.log" 2>&1 || true
        docker rm -f "$(container_name "${member}")" >/dev/null 2>&1 || true
        docker volume rm -f "$(data_volume "${member}")" >/dev/null 2>&1 || true
    done
    docker volume rm -f "${cert_volume}" >/dev/null 2>&1 || true
    docker network rm "${network}" >/dev/null 2>&1 || true
    rm -rf -- "${cert_source}"
}
trap cleanup EXIT INT TERM

generate_ca() {
    local prefix=$1
    local common_name=$2
    openssl req -x509 -newkey rsa:3072 -nodes -sha256 -days 1 \
        -subj "/CN=${common_name}" \
        -addext 'basicConstraints=critical,CA:TRUE,pathlen:0' \
        -addext 'keyUsage=critical,keyCertSign,cRLSign' \
        -keyout "${cert_source}/${prefix}.key" \
        -out "${cert_source}/${prefix}.crt" >/dev/null 2>&1
    chmod 0600 "${cert_source}/${prefix}.key"
}

generate_certificate() {
    local name=$1
    local common_name=$2
    local ca_prefix=$3
    local serial=$4
    local extensions=$5
    local config="${cert_source}/${name}.ext"

    openssl req -new -newkey rsa:3072 -nodes -sha256 \
        -subj "/CN=${common_name}" \
        -keyout "${cert_source}/${name}.key" \
        -out "${cert_source}/${name}.csr" >/dev/null 2>&1
    printf '%s\n' "${extensions}" > "${config}"
    openssl x509 -req -sha256 -days 1 -set_serial "${serial}" \
        -in "${cert_source}/${name}.csr" \
        -CA "${cert_source}/${ca_prefix}.crt" \
        -CAkey "${cert_source}/${ca_prefix}.key" \
        -extfile "${config}" \
        -out "${cert_source}/${name}.crt" >/dev/null 2>&1
    chmod 0600 "${cert_source}/${name}.key"
    rm -f "${cert_source}/${name}.csr" "${config}"
}

record_certificate() {
    local name=$1
    {
        echo "certificate=${name}"
        openssl x509 -in "${cert_source}/${name}.crt" -noout \
            -subject -issuer -serial -dates -fingerprint -sha256
        openssl x509 -in "${cert_source}/${name}.crt" -noout -ext subjectAltName 2>/dev/null || true
        openssl x509 -in "${cert_source}/${name}.crt" -noout -ext extendedKeyUsage 2>/dev/null || true
    } >> "${evidence_dir}/certificate-inventory.txt"
}

initialize_volume() {
    local volume_name=$1
    docker volume create "${volume_name}" >/dev/null
    docker run --rm --network none --user 0:0 \
        --entrypoint /usr/bin/chown \
        -v "${volume_name}:/data" \
        "${init_image}" 65532:65532 /data
}

prepare_certificates() {
    openssl version > "${evidence_dir}/openssl-version.txt"
    generate_ca ca 'PastureStack disposable etcd quorum test CA'
    generate_ca rogue-ca 'PastureStack disposable rejected test CA'

    local index=1
    local member
    for member in "${member_names[@]}"; do
        generate_certificate "${member}" "${member}" ca "${index}" \
            "basicConstraints=critical,CA:FALSE
subjectAltName=DNS:${member/member/etcd},DNS:${member},DNS:localhost,IP:127.0.0.1
extendedKeyUsage=serverAuth,clientAuth
keyUsage=critical,digitalSignature,keyEncipherment"
        index=$((index + 1))
    done
    generate_certificate client quorum-test-client ca 100 \
        'basicConstraints=critical,CA:FALSE
extendedKeyUsage=clientAuth
keyUsage=critical,digitalSignature,keyEncipherment'
    generate_certificate rogue-client rejected-client rogue-ca 200 \
        'basicConstraints=critical,CA:FALSE
extendedKeyUsage=clientAuth
keyUsage=critical,digitalSignature,keyEncipherment'

    : > "${evidence_dir}/certificate-inventory.txt"
    record_certificate ca
    record_certificate member1
    record_certificate member2
    record_certificate member3
    record_certificate member4
    record_certificate client
    record_certificate rogue-ca
    record_certificate rogue-client

    docker volume create "${cert_volume}" >/dev/null
    docker run --rm --network none --user 0:0 \
        --entrypoint /bin/bash \
        -v "${cert_source}:/source:ro" \
        -v "${cert_volume}:/certs" \
        "${init_image}" -c '
            set -euo pipefail
            cp /source/*.crt /source/member*.key /source/client.key /source/rogue-client.key /certs/
            chown -R 65532:65532 /certs
            chmod 0755 /certs
            chmod 0644 /certs/*.crt
            chmod 0600 /certs/*.key
            test ! -e /certs/ca.key
            test ! -e /certs/rogue-ca.key
        '
}

start_member() {
    local member=$1
    local cluster=$2
    local state=$3
    local endpoint=${member/member/etcd}

    docker run --detach \
        --name "$(container_name "${member}")" \
        --network "${network}" \
        --network-alias "${endpoint}" \
        -v "$(data_volume "${member}"):/var/lib/etcd" \
        -v "${cert_volume}:/certs:ro" \
        "${candidate_image}" \
        --name="${member}" \
        --data-dir=/var/lib/etcd/default.etcd \
        --listen-client-urls=https://0.0.0.0:2379 \
        --advertise-client-urls="https://${endpoint}:2379" \
        --listen-peer-urls=https://0.0.0.0:2380 \
        --initial-advertise-peer-urls="https://${endpoint}:2380" \
        --initial-cluster="${cluster}" \
        --initial-cluster-state="${state}" \
        --client-cert-auth=true \
        --trusted-ca-file=/certs/ca.crt \
        --cert-file="/certs/${member}.crt" \
        --key-file="/certs/${member}.key" \
        --peer-client-cert-auth=true \
        --peer-trusted-ca-file=/certs/ca.crt \
        --peer-cert-file="/certs/${member}.crt" \
        --peer-key-file="/certs/${member}.key" >/dev/null
}

control_exec_from() {
    local source_member=$1
    shift
    docker exec "$(container_name "${source_member}")" \
        /usr/local/bin/etcdctl \
        --dial-timeout=2s \
        --command-timeout=8s \
        --cacert=/certs/ca.crt \
        --cert=/certs/client.crt \
        --key=/certs/client.key \
        "$@"
}

control_exec() {
    control_exec_from member1 "$@"
}

etcdctl() {
    control_exec --endpoints=https://etcd1:2379,https://etcd2:2379,https://etcd3:2379 "$@"
}

replacement_etcdctl() {
    control_exec --endpoints=https://etcd1:2379,https://etcd2:2379,https://etcd4:2379 "$@"
}

wait_endpoints_from() {
    local source_member=$1
    local endpoints=$2
    local attempts=${3:-90}
    local healthy=0
    for _ in $(seq 1 "${attempts}"); do
        if control_exec_from "${source_member}" --endpoints="${endpoints}" \
            endpoint health >/dev/null 2>&1; then
            healthy=1
            break
        fi
        sleep 1
    done
    if [ "${healthy}" -ne 1 ]; then
        echo "ETCD_IMAGE_QUORUM_ENDPOINTS_NOT_HEALTHY endpoints=${endpoints}" >&2
        return 1
    fi
}

wait_endpoints() {
    wait_endpoints_from member1 "$@"
}

wait_endpoint_status_from() {
    local source_member=$1
    local endpoints=$2
    local attempts=${3:-90}
    for _ in $(seq 1 "${attempts}"); do
        if control_exec_from "${source_member}" --endpoints="${endpoints}" \
            endpoint status >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    echo "ETCD_IMAGE_ENDPOINT_STATUS_UNAVAILABLE endpoints=${endpoints}" >&2
    return 1
}

canonical_data() {
    local command=$1
    "${command}" get '' --from-key --write-out=json | \
        jq -c '[.kvs[]? | {key:.key,value:.value}] | sort_by(.key)'
}

data_count() {
    local command=$1
    "${command}" get '' --from-key --write-out=json | jq -r '.count'
}

data_sha256() {
    local command=$1
    canonical_data "${command}" | sha256sum | awk '{print $1}'
}

assert_hashes_equal() {
    local command=$1
    local evidence_file=$2
    if ! "${command}" endpoint hashkv --cluster --write-out=json \
        > "${evidence_file}"; then
        return 1
    fi
    jq -e '
        length == 3 and
        all(.[]; (.Endpoint | type) == "string") and
        all(.[]; (.HashKV.hash | type) == "number") and
        ([.[].HashKV.hash] | unique | length == 1)
    ' "${evidence_file}" >/dev/null
}

wait_learner_caught_up() {
    local evidence_file=$1
    local attempts=${2:-90}
    for _ in $(seq 1 "${attempts}"); do
        if control_exec_from member1 \
            --endpoints=https://etcd1:2379,https://etcd2:2379,https://etcd4:2379 \
            endpoint status --write-out=json > "${evidence_file}" && \
            jq -e '
                length == 3 and
                ([.[] | select(.Status.isLearner == true)] | length) == 1 and
                ([.[].Status.raftIndex] | min) == ([.[].Status.raftIndex] | max) and
                ([.[].Status.raftAppliedIndex] | min) ==
                    ([.[].Status.raftAppliedIndex] | max) and
                all(.[]; ((.Status.errors // []) | length) == 0)
            ' "${evidence_file}" >/dev/null; then
            return 0
        fi
        sleep 1
    done
    echo ETCD_IMAGE_LEARNER_RAFT_DID_NOT_CONVERGE >&2
    return 1
}

prepare_certificates
docker network create --internal "${network}" >/dev/null
for member in "${member_names[@]}"; do
    initialize_volume "$(data_volume "${member}")"
done

start_member member1 "${initial_cluster}" new
start_member member2 "${initial_cluster}" new
start_member member3 "${initial_cluster}" new
wait_endpoints 'https://etcd1:2379,https://etcd2:2379,https://etcd3:2379'

etcdctl endpoint status --cluster --write-out=json > "${evidence_dir}/initial-endpoint-status.json"
etcdctl member list --write-out=json > "${evidence_dir}/initial-member-list.json"
jq -e '
    (.members | length) == 3 and
    ([.members[].name] | sort) == ["member1", "member2", "member3"]
' "${evidence_dir}/initial-member-list.json" >/dev/null

if docker exec "$(container_name member1)" /usr/local/bin/etcdctl \
    --dial-timeout=2s --command-timeout=5s \
    --endpoints=https://etcd1:2379 \
    --cacert=/certs/ca.crt endpoint health \
    > "${evidence_dir}/missing-client-certificate.txt" 2>&1; then
    echo ETCD_IMAGE_MTLS_ACCEPTED_MISSING_CLIENT_CERTIFICATE >&2
    exit 1
fi

if docker exec "$(container_name member1)" /usr/local/bin/etcdctl \
    --dial-timeout=2s --command-timeout=5s \
    --endpoints=https://etcd1:2379 \
    --cacert=/certs/ca.crt \
    --cert=/certs/rogue-client.crt \
    --key=/certs/rogue-client.key endpoint health \
    > "${evidence_dir}/rejected-client-certificate.txt" 2>&1; then
    echo ETCD_IMAGE_MTLS_ACCEPTED_ROGUE_CLIENT_CERTIFICATE >&2
    exit 1
fi

for index in $(seq -w 1 100); do
    etcdctl put "pasturestack/quorum-key-${index}" "value-${index}" >/dev/null
done
initial_count=$(data_count etcdctl)
initial_sha256=$(data_sha256 etcdctl)
test "${initial_count}" -eq 100
assert_hashes_equal etcdctl "${evidence_dir}/initial-hashkv.json"

docker stop "$(container_name member3)" >/dev/null
wait_endpoints 'https://etcd1:2379,https://etcd2:2379'
control_exec --endpoints=https://etcd1:2379,https://etcd2:2379 \
    put pasturestack/one-member-down quorum-preserved >/dev/null
test "$(control_exec --endpoints=https://etcd1:2379,https://etcd2:2379 \
    get pasturestack/one-member-down --print-value-only)" = quorum-preserved
control_exec --endpoints=https://etcd1:2379,https://etcd2:2379 \
    endpoint status --write-out=json > "${evidence_dir}/one-member-down-status.json"

docker stop "$(container_name member2)" >/dev/null
if control_exec --endpoints=https://etcd1:2379 \
    put pasturestack/lost-quorum must-not-commit \
    > "${evidence_dir}/lost-quorum-write.txt" 2>&1; then
    echo ETCD_IMAGE_QUORUM_LOSS_WRITE_UNEXPECTEDLY_SUCCEEDED >&2
    exit 1
fi
test -z "$(control_exec --endpoints=https://etcd1:2379 \
    get pasturestack/lost-quorum --consistency=s --print-value-only)"

docker stop "$(container_name member1)" >/dev/null
docker start "$(container_name member2)" "$(container_name member3)" >/dev/null
wait_endpoints_from member2 'https://etcd2:2379,https://etcd3:2379'
test -z "$(control_exec_from member2 --endpoints=https://etcd2:2379,https://etcd3:2379 \
    get pasturestack/lost-quorum --print-value-only)"
control_exec_from member2 --endpoints=https://etcd2:2379,https://etcd3:2379 \
    put pasturestack/quorum-recovered recovered >/dev/null
docker start "$(container_name member1)" >/dev/null
wait_endpoints_from member2 'https://etcd1:2379,https://etcd2:2379,https://etcd3:2379'
test -z "$(control_exec_from member2 \
    --endpoints=https://etcd1:2379,https://etcd2:2379,https://etcd3:2379 \
    get pasturestack/lost-quorum --print-value-only)"

docker stop "$(container_name member3)" >/dev/null
wait_endpoints 'https://etcd1:2379,https://etcd2:2379'

control_exec --endpoints=https://etcd1:2379,https://etcd2:2379 \
    member list --write-out=simple > "${evidence_dir}/member-list-before-replacement.txt"
member3_id=$(awk -F, '$3 ~ /member3/ {gsub(/^ +| +$/, "", $1); print $1}' \
    "${evidence_dir}/member-list-before-replacement.txt")
test -n "${member3_id}"
control_exec --endpoints=https://etcd1:2379,https://etcd2:2379 \
    member remove "${member3_id}" > "${evidence_dir}/member-remove.txt"
docker logs "$(container_name member3)" \
    > "${evidence_dir}/member3-before-replacement.log" 2>&1 || true
docker rm "$(container_name member3)" >/dev/null
docker volume rm -f "$(data_volume member3)" >/dev/null

member_add_succeeded=0
: > "${evidence_dir}/member-add-attempts.txt"
for attempt in $(seq 1 30); do
    if member_add_output=$(control_exec \
        --endpoints=https://etcd1:2379,https://etcd2:2379 \
        member add member4 --peer-urls=https://etcd4:2380 --learner \
        2>> "${evidence_dir}/member-add-attempts.txt"); then
        printf '%s\n' "${member_add_output}" > "${evidence_dir}/member-add.txt"
        printf 'successful_attempt=%s\n' "${attempt}" \
            >> "${evidence_dir}/member-add-attempts.txt"
        member_add_succeeded=1
        break
    fi
    if control_exec --endpoints=https://etcd1:2379,https://etcd2:2379 \
        member list --write-out=simple \
        > "${evidence_dir}/member-add-recovery-list.txt" \
        2>> "${evidence_dir}/member-add-attempts.txt" && \
        grep -Fq 'https://etcd4:2380' \
        "${evidence_dir}/member-add-recovery-list.txt"; then
        printf '%s\n' 'member4 learner was committed before the client error' \
            > "${evidence_dir}/member-add.txt"
        printf 'committed_after_client_error_attempt=%s\n' "${attempt}" \
            >> "${evidence_dir}/member-add-attempts.txt"
        member_add_succeeded=1
        break
    fi
    printf 'failed_attempt=%s\n' "${attempt}" \
        >> "${evidence_dir}/member-add-attempts.txt"
    sleep 1
done
if [ "${member_add_succeeded}" -ne 1 ]; then
    echo ETCD_IMAGE_LEARNER_ADD_FAILED_AFTER_HEALTH_WINDOW >&2
    exit 1
fi

start_member member4 "${replacement_cluster}" existing
wait_endpoints 'https://etcd1:2379,https://etcd2:2379'
wait_endpoint_status_from member1 'https://etcd4:2379'
learner_published=0
for _ in $(seq 1 90); do
    if control_exec --endpoints=https://etcd1:2379,https://etcd2:2379 \
        member list --write-out=json \
        > "${evidence_dir}/replacement-learner-member-list.json" && \
        jq -e '
            (.members | length) == 3 and
            ([.members[].name] | sort) == ["member1", "member2", "member4"] and
            any(.members[]; .name == "member4" and .isLearner == true)
        ' "${evidence_dir}/replacement-learner-member-list.json" >/dev/null; then
        learner_published=1
        break
    fi
    sleep 1
done
if [ "${learner_published}" -ne 1 ]; then
    echo ETCD_IMAGE_LEARNER_NOT_PUBLISHED >&2
    exit 1
fi
wait_learner_caught_up \
    "${evidence_dir}/replacement-learner-endpoint-status.json"
control_exec --endpoints=https://etcd1:2379,https://etcd2:2379 \
    member list --write-out=simple \
    > "${evidence_dir}/member-list-before-promotion.txt"
member4_id=$(awk -F, '$3 ~ /member4/ {gsub(/^ +| +$/, "", $1); print $1}' \
    "${evidence_dir}/member-list-before-promotion.txt")
test -n "${member4_id}"
control_exec --endpoints=https://etcd1:2379,https://etcd2:2379 \
    member promote "${member4_id}" \
    > "${evidence_dir}/member-promote.txt"
wait_endpoints 'https://etcd1:2379,https://etcd2:2379,https://etcd4:2379'

replacement_etcdctl member list --write-out=json > "${evidence_dir}/replacement-member-list.json"
jq -e '
    (.members | length) == 3 and
    ([.members[].name] | sort) == ["member1", "member2", "member4"] and
    all(.members[]; (.isLearner // false) == false)
' "${evidence_dir}/replacement-member-list.json" >/dev/null
replacement_etcdctl put pasturestack/member-replacement replacement-complete >/dev/null
assert_hashes_equal replacement_etcdctl "${evidence_dir}/post-replacement-hashkv.json"

docker network disconnect -f "${network}" "$(container_name member4)"
wait_endpoints 'https://etcd1:2379,https://etcd2:2379'
control_exec --endpoints=https://etcd1:2379,https://etcd2:2379 \
    put pasturestack/network-partition quorum-preserved >/dev/null
docker network connect --alias etcd4 "${network}" "$(container_name member4)"
wait_endpoints 'https://etcd1:2379,https://etcd2:2379,https://etcd4:2379'
replacement_etcdctl endpoint status --cluster --write-out=json \
    > "${evidence_dir}/post-partition-endpoint-status.json"
assert_hashes_equal replacement_etcdctl "${evidence_dir}/post-partition-hashkv.json"

final_count=$(data_count replacement_etcdctl)
final_sha256=$(data_sha256 replacement_etcdctl)
test "${final_count}" -eq 104
test -z "$(replacement_etcdctl get pasturestack/lost-quorum --print-value-only)"
test "$(replacement_etcdctl get pasturestack/one-member-down --print-value-only)" = quorum-preserved
test "$(replacement_etcdctl get pasturestack/quorum-recovered --print-value-only)" = recovered
test "$(replacement_etcdctl get pasturestack/member-replacement --print-value-only)" = replacement-complete
test "$(replacement_etcdctl get pasturestack/network-partition --print-value-only)" = quorum-preserved

cat > "${evidence_dir}/result.env" <<EOF
status=passed
candidate_version=3.7.2
cluster_size_initial=3
cluster_size_final=3
client_mtls=passed
missing_client_certificate_rejected=passed
rogue_client_certificate_rejected=passed
one_member_failure=passed
quorum_loss_write_rejected=passed
quorum_recovery=passed
member_replacement=passed
replacement_learner_catchup=passed
replacement_promoted=passed
network_partition=passed
lost_quorum_key_absent=passed
lost_quorum_write_unapplied_before_recovery=passed
initial_key_count=${initial_count}
final_key_count=${final_count}
initial_sha256=${initial_sha256}
final_sha256=${final_sha256}
EOF

grep -Fx status=passed "${evidence_dir}/result.env"
grep -Fx client_mtls=passed "${evidence_dir}/result.env"
grep -Fx quorum_loss_write_rejected=passed "${evidence_dir}/result.env"
grep -Fx member_replacement=passed "${evidence_dir}/result.env"
grep -Fx network_partition=passed "${evidence_dir}/result.env"
