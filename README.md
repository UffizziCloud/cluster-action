# Uffizzi Ephemeral Cluster Environments (Virtualized Kubernetes)

Deploy Uffizzi Ephemeral Cluster Environments (uClusters) for every pull request.

Similar to the concept of virtual machines, Uffizzi ephemeral clusters are virtualized instances of Kubernetes clusters running on top of a host cluster. Uffizzi virtual clusters provide all the same functionality of real Kubernetes clusters, while being more convenient and efficient.

Uffizzi integrates as a step in your GitHub Actions pipeline to manage on-demand, ephemeral test environments for every feature branch/pull request. Ephemeral Cluster Environments are deployed on [Uffizzi Cloud](https://uffizzi.com) (SaaS) or your own installation of [Uffizzi Enterprise](https://www.uffizzi.com//pricing) or [open-source Uffizzi](https://github.com/UffizziCloud/uffizzi_app).

## Using the Action (recommended usage)

If you wish to use this action by itself outside of the reusable workflow described above, you can. The action can create or delete uClusters.

### Inputs

#### `server`

(Optional) `https://app.uffizzi.com/` or the URL of your Uffizzi installation.

#### `cluster-name`

(Required) The name of the cluster spun up by the `uffizzi cluster create` command.

#### `image`

(Optional) Uffizzi CLI Image. Default value is "uffizzi/cli:v2".

#### `kubeconfig`

(Optional) Path to kubeconfig file.

#### `action`

(Optional) Specify whether to create or delete a cluster. Default value is "create".

#### `k8s-version`

(Optionoal) Version of the kubernetes cluster to be created. Only works with "create" action.

## Reusable Workflow (alternate usage)

We've published a [Reusable Workflow](https://docs.github.com/en/actions/using-workflows/reusing-workflows#calling-a-reusable-workflow) for your GitHub Actions. This can handle creating, updating, and deleting Uffizzi Ephemeral Cluster Environments. It will also publish instructions for connecting to your cluster in a comment to your pull requests. 

### Example usage

```yaml
- name: Create cluster
  id: create-cluster
  if: ${{ env.UFFIZZI_ACTION == 'create' }} || ${{ env.UFFIZZI_ACTION == 'update' }}
  uses: UffizziCloud/cluster-action@reusable
  with:
    action: create
    cluster-name: pr-$PR_NUMBER
    k8s-manifest-file: ${{ inputs.k8s-manifest-cache-path }}
    server: ${{ inputs.server }}
```

### Workflow Calling Example

In this example, three images (`vote`, `result`, and `worker`) are built and published to a temporary image registry exclusively for pull request events. The details of the built image is then updated within the Kubernetes manifest using `Kustomize`. By following this process, the Uffizzi Cluster is created, and the Kubernetes manifests from the repository are applied.

For more information see [Uffizzi Quickstart for K8s](https://github.com/UffizziCloud/quickstart-k8s/).

```yaml
name: Uffizzi Cluster Example

on:
  pull_request:
    types: [opened,reopened,synchronize,closed]

permissions:
  id-token: write

jobs:      
  build-vote:
    name: Build and Push `vote`
    runs-on: ubuntu-latest
    if: ${{ github.event_name != 'pull_request' || github.event.action != 'closed' }}
    outputs:
      tags: ${{ steps.meta.outputs.tags }}
    steps:
      - name: Checkout git repo
        uses: actions/checkout@v3
      - name: Generate UUID image name
        id: uuid
        run: echo "UUID_VOTE=$(uuidgen)" >> $GITHUB_ENV
      - name: Docker metadata
        id: meta
        uses: docker/metadata-action@v4
        with:
          # An anonymous, emphemeral registry built on ttl.sh
          images: registry.uffizzi.com/${{ env.UUID_VOTE }}
          tags: type=raw,value=24h
      - name: Build and Push Image to Uffizzi Ephemeral Registry
        uses: docker/build-push-action@v3
        with:
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          context: ./vote

  build-worker:
    name: Build and Push `worker`
    runs-on: ubuntu-latest
    if: ${{ github.event_name != 'pull_request' || github.event.action != 'closed' }}
    outputs:
      tags: ${{ steps.meta.outputs.tags }}
    steps:
      - name: Checkout git repo
        uses: actions/checkout@v3
      - name: Generate UUID image name
        id: uuid
        run: echo "UUID_WORKER=$(uuidgen)" >> $GITHUB_ENV
      - name: Docker metadata
        id: meta
        uses: docker/metadata-action@v4
        with:
          # An anonymous, emphemeral registry built on ttl.sh
          images: registry.uffizzi.com/${{ env.UUID_WORKER }}
          tags: type=raw,value=24h
      - name: Build and Push Image to Uffizzi Ephemeral Registry
        uses: docker/build-push-action@v3
        with:
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          context: ./worker

  build-result:
    name: Build and Push `result`
    runs-on: ubuntu-latest
    if: ${{ github.event_name != 'pull_request' || github.event.action != 'closed' }}
    outputs:
      tags: ${{ steps.meta.outputs.tags }}
    steps:
      - name: Checkout git repo
        uses: actions/checkout@v3
      - name: Generate UUID image name
        id: uuid
        run: echo "UUID_RESULT=$(uuidgen)" >> $GITHUB_ENV
      - name: Docker metadata
        id: meta
        uses: docker/metadata-action@v4
        with:
          # An anonymous, emphemeral registry built on ttl.sh
          images: registry.uffizzi.com/${{ env.UUID_RESULT }}
          tags: type=raw,value=24h
      - name: Build and Push Image to Uffizzi Ephemeral Registry
        uses: docker/build-push-action@v3
        with:
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          context: ./result

  cluster-setup:
    name: Setup ucluster
    uses: UffizziCloud/cluster-action/.github/workflows/reusable.yaml@main
    permissions:
      contents: read
      pull-requests: write
      id-token: write

  apply-manifests: 
    runs-on: ubuntu-latest
    needs:
      - build-vote
      - build-worker
      - build-result
      - cluster-setup
    steps:
      - name: Checkout
        uses: actions/checkout@v3

      - name: Download artifact
        uses: actions/download-artifact@v3
        with:
          name: my-artifact

      - name: Kustomize and apply
        run: |

          kustomize edit set image vote-image=${{ needs.build-vote.outputs.tags }}
          kustomize edit set image result-image=${{ needs.build-result.outputs.tags }}
          kustomize edit set image worker-image=${{ needs.build-worker.outputs.tags }}

          kustomize build . | kubectl apply --kubeconfig kubeconfig -f -

          if kubectl get ingress vote-${{ github.event.number }} --kubeconfig kubeconfig >/dev/null 2>&1; then
            echo "Ingress vote-${{ github.event.number }} already exists"

          else
            kubectl create ingress vote-${{ github.event.number }} \
              --class=nginx \
              --rule="pr-${{ github.event.number }}-vote.app.qa-gke.uffizzi.com/*=vote:5000" \
              --kubeconfig kubeconfig
          fi

          if kubectl get ingress result-${{ github.event.number }} --kubeconfig kubeconfig >/dev/null 2>&1; then
            echo "Ingress result-${{ github.event.number }} already exists"

          else     
            kubectl create ingress result-${{ github.event.number }} \
              --class=nginx \
              --rule="pr-${{ github.event.number }}-result.app.qa-gke.uffizzi.com/*=result:5001" \
              --kubeconfig kubeconfig
          fi

          echo "Access the vote endpoint at \`pr-${{ github.event.number }}-vote.app.qa-gke.uffizzi.com\`." | tee --append $GITHUB_STEP_SUMMARY
          echo "Access the result endpoint at \`pr-${{ github.event.number }}-result.app.qa-gke.uffizzi.com\`." | tee --append $GITHUB_STEP_SUMMARY
```

### Reusable Workflow Inputs

#### `username`

(Optional) Uffizzi username for login, usually an email address.

#### `server`

(Optional) Uffizzi server URL. Default value is "https://app.uffizzi.com".

#### `project`

(Optional) Uffizzi project name. Default value is "default".

#### `pr-number`

(Optional) GitHub Pull Request Number

#### `git-ref`

(Optional) Branch or other git reference to checkout

#### `healthcheck-url-path`

(Optional) URL Path to the Uffizzi Cluster URL where healthcheck would be performed. The URL Path has to start with a '/'.

#### `description`

(Optional) Text string added to comment on pull request issue. Default value is "What is Uffizzi? [Learn more](https://www.uffizzi.com)".

#### `environment`

(Optional) Custom environment for the deployed cluster. Default value is "uffizzi".

#### `image`

(Optional) Uffizzi CLI Image. Default value is "uffizzi/cli:v2".

<!-- 
## Uffizzi Accounts

If you're using the reusable workflow with [Uffizzi Cloud](https://uffizzi.com), an account and project will be created from your GitHub user and repository information when the workflow runs. If you're self-hosting open-source Uffizzi, you will need to create a Uffizzi user and project before running the workflow, then set `username`, `password`, and `project` inputs, where `project` is the Uffizzi project slug.

### Example usage Uffizzi Cloud

```yaml
uses: UffizziCloud/preview-action@v2
with:
  compose-file: 'docker-compose.uffizzi.yaml'
  server: 'https://app.uffizzi.com'
secrets:
  access-token: ${{ secrets.GITHUB_TOKEN }}
  url-username: admin
  url-password: ${{ secrets.URL_PASSWORD }}
permissions:
  contents: read
  pull-requests: write
  id-token: write
```

### Example usage self-hosted

```yaml
uses: UffizziCloud/preview-action@v2
with:
  compose-file: 'docker-compose.uffizzi.yaml'
  server: 'https://uffizzi.example.com'
  username: 'j.doe@example.com'
  password: ${{ secrets.UFFIZZI_PASSWORD }}
  project: 'default'
permissions:
  contents: read
  pull-requests: write
  id-token: write
``` -->

<!-- ## Using this Preview Action itself (not recommended)

If you wish to use this action by itself outside of the reusable workflow described above, you can. It will only create new previews, not update nor delete them.

### Inputs

#### `compose-file`

(Required) Path to a compose file within your repository

#### `server`

(Required) `https://app.uffizzi.com/` or the URL of your Uffizzi installation

#### `username`

(Self-hosted only) Uffizzi username

#### `password`

(Self-hosted only) Your Uffizzi password, specified as a GitHub Secret

#### `project`

(Self-hosted only) Uffizzi project slug

#### `access-token`

(Optional) The value of the `${{ secrets.GITHUB_TOKEN }}`. Used to avoid hitting the Github request rate limit.

#### `ghcr-username` and `ghcr-access-token` -->

<!-- Your GitHub username and the value of a [Github personal access token](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token) with access to the `read:packages` scope.

This option is provided as a convenience to get started quickly. For sensitive repositories, we recommend instead connecting your Uffizzi account to GHCR via the web interface or by executing `uffizzi connect ghcr` from a trusted environment.

#### `dockerhub-username` and `dockerhub-password`

Your DockerHub username and password.

### `acr-registry-url`, `acr-username`, and `acr-password`

Your Azure Container Registry url, username and password.

### `aws-registry-url`, `aws-access-key-id`, and `aws-secret-access-key`

Your Amazon Web Services registry url, access key id and secret access key.

### `gcloud-service-key`

Your Google Cloud service key.

### `docker-registry-url`, `docker-registry-username`, and `docker-registry-password`

Your custom docker registry url, username and password. -->
<!-- 
## Example usage

```yaml
uses: UffizziCloud/preview-action@v2
with:
  compose-file: 'docker-compose.uffizzi.yaml'
  username: 'admin@uffizzi.com'
  server: 'https://app.uffizzi.com'
  project: 'default'
  password: ${{ secrets.UFFIZZI_PASSWORD }}
permissions:
  contents: read
  pull-requests: write
  id-token: write
```

## If you don't have a Uffizzi account

If you don't have a Uffizzi account, leave the username, password and project inputs blank. Uffizzi will create a Uffizzi account based on the information about the current repository and Github user.

Example usage without an account:

```yaml
uses: UffizziCloud/preview-action@v2
with:
  compose-file: 'docker-compose.uffizzi.yaml'
  server: 'https://app.uffizzi.com'
permissions:
  contents: read
  pull-requests: write
  id-token: write
``` -->
