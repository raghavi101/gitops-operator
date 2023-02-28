#!/bin/bash

USERNAME="rshirur"
IMAGENAME="gitops-operator-image"
IMAGETAG="20230222"
IMG=quay.io/$USERNAME/$IMAGENAME:$IMAGETAG

CONTROLLER_GEN = $(shell pwd)/bin/controller-gen
KUSTOMIZE = $(shell pwd)/bin/kustomize
CRD_OPTIONS = "crd:trivialVersions=true,preserveUnknownFields=false"

VERSION="v0.4.1"
REPO="sigs.k8s.io/controller-tools/cmd/controller-gen@$VERSION"

## Build docker image with the manager.
# test : manifests generate fmt vet ## Run unit tests.
	# go test `go list ./... | grep -v test` -coverprofile cover.out
# docker build -t ${IMG} .
# docker push ${IMG}

# MANIFEST
# $(call go-get-tool,$(CONTROLLER_GEN),sigs.k8s.io/controller-tools/cmd/controller-gen@v0.4.1)
go get -u $REPO
go build -o "$(go env GOPATH)/bin/$CONTROLLER_GEN" "$REPO"

#$(CONTROLLER_GEN) $(CRD_OPTIONS) rbac:roleName=manager-role webhook paths="./..." output:crd:artifacts:config=config/crd/bases
$CONTROLLER_GEN $CRD_OPTIONS rbac:roleName=manager-role webhook paths="./..." output:crd:artifacts:config=config/crd/bases

# GENERATE
#$(call go-get-tool,$(CONTROLLER_GEN),sigs.k8s.io/controller-tools/cmd/controller-gen@v0.4.1)
go get -u $REPO
go build -o "$(go env GOPATH)/bin/$CONTROLLER_GEN" "$REPO"

#$(CONTROLLER_GEN) object:headerFile="hack/boilerplate.go.txt" paths="./..."
$CONTROLLER_GEN object:headerFile="hack/boilerplate.go.txt" paths="./..."

go fmt ./...
go vet ./...

# go test `go list ./... | grep -v test` -coverprofile cover.out

# List all packages in the current directory and subdirectories
PACKAGES=$(go list ./...)

# Exclude test packages from the list
NON_TEST_PACKAGES=$(echo $PACKAGES | grep -v '/test$')

# Run `go test` on non-test packages and generate a coverage profile
go test -coverprofile=cover.out $NON_TEST_PACKAGES

# Build and push using docker 
docker build -t ${IMG} .
docker push ${IMG}

echo -e "Apply ImageContentSourcePolicy CR"
oc apply -f - << EOD
apiVersion: operator.openshift.io/v1alpha1 
kind: ImageContentSourcePolicy 
metadata: 
  name: brew-registry 
spec: 
  repositoryDigestMirrors: 
  - mirrors: 
    - brew.registry.redhat.io 
    source: registry.redhat.io 
  - mirrors: 
    - brew.registry.redhat.io 
    source: registry.stage.redhat.io 
  - mirrors: 
    - brew.registry.redhat.io 
    source: registry-proxy.engineering.redhat.com
EOD

oldauth=$(mktemp)
newauth=$(mktemp)

# Get current information
oc get secrets pull-secret -n openshift-config -o template='{{index .data ".dockerconfigjson"}}' | base64 -d > ${oldauth}

# Get Brew registry credentials
brew_secret=$(jq '.auths."brew.registry.redhat.io".auth' ${HOME}/.docker/config.json | tr -d '"')

# Append the key:value to the JSON file
jq --arg secret ${brew_secret} '.auths |= . + {"brew.registry.redhat.io":{"auth":$secret}}' ${oldauth} > ${newauth}

# Update the pull-secret information in OCP
oc set data secret pull-secret -n openshift-config --from-file=.dockerconfigjson=${newauth}

# Cleanup
rm -f ${oldauth} ${newauth}

# make deploy
# manifests kustomize ## Deploy controller to the K8s cluster specified in ~/.kube/config.
# 	cd config/manager && $(KUSTOMIZE) edit set image controller=${IMG}
# 	$(KUSTOMIZE) build config/default | kubectl apply -f -

# MANIFEST
# $(call go-get-tool,$(CONTROLLER_GEN),sigs.k8s.io/controller-tools/cmd/controller-gen@v0.4.1)
go get -u $REPO
go build -o "$(go env GOPATH)/bin/$CONTROLLER_GEN" "$REPO"

#$(CONTROLLER_GEN) $(CRD_OPTIONS) rbac:roleName=manager-role webhook paths="./..." output:crd:artifacts:config=config/crd/bases
$CONTROLLER_GEN $CRD_OPTIONS rbac:roleName=manager-role webhook paths="./..." output:crd:artifacts:config=config/crd/bases

# KUSTOMIZE
# $(call go-get-tool,$(KUSTOMIZE),sigs.k8s.io/kustomize/kustomize/v4@v4.5.2)
# Define the function that installs Go tools
function go-get-tool {
    # Check if the tool is already installed
    if ! command -v "$2" &> /dev/null; then
        # If not, install the tool
        GO111MODULE=on go get "$1"
    fi
}

# Call the function to install Kustomize
KUSTOMIZE_VERSION="v4.5.2"
KUSTOMIZE_REPO="sigs.k8s.io/kustomize/kustomize/v4@$KUSTOMIZE_VERSION"
go-get-tool "$KUSTOMIZE_REPO" "$KUSTOMIZE"

# cd config/manager && $(KUSTOMIZE) edit set image controller=${IMG}
# 	$(KUSTOMIZE) build config/default | kubectl apply -f - ${IMG}

# Change to the config/manager directory
cd config/manager

# Set the image for the controller in the Kustomize config
$KUSTOMIZE edit set image controller=$IMG

# Build the Kustomize configuration and apply it to the cluster
$KUSTOMIZE build config/default | kubectl apply -f -