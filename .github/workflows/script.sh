#!/bin/bash

# Checking if the script received any argument
if [ $# -eq 0 ]; then
    echo "No arguments provided"
    echo "[create|delete]"
    exit 1
fi

# Retrieve the operation from the script argument
operation=$1

# Handling the operation
if [ "$operation" = "create" ]; then
    echo "Checking if uffizzi cluster ${UFFIZZI_CLUSTER} already exists"    
    if docker run --rm \
        --env UFFIZZI_SERVER \
        --env REQUEST_TOKEN=${ACTIONS_ID_TOKEN_REQUEST_TOKEN} \
        --env REQUEST_TOKEN_URL=${ACTIONS_ID_TOKEN_REQUEST_URL} \
        ${UFFIZZI_IMAGE} cluster list | grep --quiet ${UFFIZZI_CLUSTER}
    # If it already exists, fetch the `kubeconfig` to connect to it.
    then
        echo "Cluster already existsUpdating kubeconfig to point to ${UFFIZZI_CLUSTER}"
        docker run --rm --env UFFIZZI_SERVER \
            --env REQUEST_TOKEN=${ACTIONS_ID_TOKEN_REQUEST_TOKEN} \
            --env REQUEST_TOKEN_URL=${ACTIONS_ID_TOKEN_REQUEST_URL} \
            --mount type=bind,source="$(pwd)",target=/home \
        ${UFFIZZI_IMAGE} cluster update-kubeconfig \
            --name=${UFFIZZI_CLUSTER} --kubeconfig="/home/kubeconfig"
    else 
        echo "Creating ..."
        docker run --rm --env UFFIZZI_SERVER \
            --env REQUEST_TOKEN=${ACTIONS_ID_TOKEN_REQUEST_TOKEN} \
            --env REQUEST_TOKEN_URL=${ACTIONS_ID_TOKEN_REQUEST_URL} \
            --mount type=bind,source="$(pwd)",target=/home \
        ${UFFIZZI_IMAGE} cluster create \
            --name=${UFFIZZI_CLUSTER} --kubeconfig="/home/kubeconfig"
    fi
elif [ "$operation" = "delete" ]; then
    # Insert delete logic here
    echo "Deleting..."
else
    # Default case if none of the above cases match
    echo "Invalid operation. Please provide either 'create' or 'delete'"
    exit 1
fi

exit 0