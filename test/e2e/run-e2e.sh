#!/bin/bash -e

script_path="$(dirname -- "${BASH_SOURCE[0]}")"

main() {
    echo "Running E2E tests" >&2
    # shellcheck disable=SC1091
    source "${script_path}/vars.sh"

    local github_org="${GH_ORG:?A GitHub org where the https://github.com/redhat-appstudio-qe/konflux-ci-sample repo is present/forked should be provided}"
    local github_token="${GH_TOKEN:?A GitHub token should be provided}"
    local quay_dockerconfig="${QUAY_DOCKERCONFIGJSON:?quay.io credentials in .dockerconfig format should be provided}"
    local catalog_revision="${RELEASE_SERVICE_CATALOG_REVISION:?RELEASE_SERVICE_CATALOG_REVISION must be set in vars.sh or env}"
    local release_catalog_ta_quay_token="${RELEASE_CATALOG_TA_QUAY_TOKEN:-}"

    # Docker network mode: macOS does not support --network=host.
    # On macOS, connect to the k3d Docker network for cluster access.
    local docker_network_args
    if [[ "$(uname)" == "Darwin" ]]; then
        local cluster_name="${KIND_CLUSTER:-konflux}"
        docker_network_args="--network=k3d-${cluster_name}"
        echo "macOS detected: using Docker network k3d-${cluster_name}" >&2
    else
        docker_network_args="--network=host"
    fi

    # shellcheck disable=SC2086
    docker run \
        ${docker_network_args} \
        -v ~/.kube/config:/kube/config \
        --env KUBECONFIG=/kube/config \
        -e GITHUB_TOKEN="$github_token" \
        -e QUAY_TOKEN="$(base64 <<< "$quay_dockerconfig")" \
        -e MY_GITHUB_ORG="$github_org" \
        -e E2E_APPLICATIONS_NAMESPACE=user-ns2 \
        -e TEST_ENVIRONMENT=upstream \
        -e RELEASE_SERVICE_CATALOG_REVISION="$catalog_revision" \
        -e RELEASE_CATALOG_TA_QUAY_TOKEN="$release_catalog_ta_quay_token" \
        "$E2E_TEST_IMAGE" \
        /bin/bash -c "ginkgo -v --label-filter=upstream-konflux --focus=\"Test local\" /konflux-e2e/konflux-e2e.test"
}


if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
