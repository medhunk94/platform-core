# Dependency-Track is deployed via Helm on the kind cluster.
# See helm/values.yaml for configuration.
#
# Install:
#   helm install dependency-track dependencytrack/dependency-track \
#     -n dependency-track --create-namespace \
#     -f helm/values.yaml
#
# Access UI:
#   kubectl port-forward svc/dependency-track-frontend 8082:80 -n dependency-track
