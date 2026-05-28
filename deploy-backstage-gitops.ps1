param(
  [string]$RepoUrl = "https://github.com/REPLACE_ME/DEVOPS-BACKSTAGE.git",
  [string]$BackstageNamespace = "backstage",
  [string]$ArgoNamespace = "argocd"
)

$ErrorActionPreference = "Stop"

function Require-Command {
  param([string]$Name)
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Required command '$Name' was not found on PATH."
  }
}

Require-Command "kubectl"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$ArgoDir = Join-Path $Root "gitops\argocd"
$RbacFile = Join-Path $ArgoDir "argocd-rbac.yaml"
$AppFile = Join-Path $ArgoDir "backstage-app.yaml"
$TempAppFile = Join-Path $env:TEMP "backstage-app.generated.yaml"

Write-Host "Applying ArgoCD RBAC for the backstage read-only API user..."
kubectl apply -f $RbacFile

Write-Host ""
Write-Host "Generate the ArgoCD JWT token with:"
Write-Host "  argocd account generate-token --account backstage"
Write-Host ""

if (-not (Get-Command "argocd" -ErrorAction SilentlyContinue)) {
  Write-Host "The argocd CLI is not on PATH. Install it or run the token command from a shell where it is available."
}

$Token = Read-Host "Paste the generated ArgoCD JWT token"
if ([string]::IsNullOrWhiteSpace($Token)) {
  throw "No token was provided."
}

Write-Host "Creating namespace '$BackstageNamespace'..."
kubectl create namespace $BackstageNamespace --dry-run=client -o yaml | kubectl apply -f -

Write-Host "Creating/updating Kubernetes Secret 'backstage-argocd-token'..."
kubectl create secret generic backstage-argocd-token `
  --from-literal=ARGOCD_AUTH_TOKEN=$Token `
  -n $BackstageNamespace `
  --dry-run=client `
  -o yaml | kubectl apply -f -

Write-Host "Preparing ArgoCD Application manifest with repoURL '$RepoUrl'..."
(Get-Content $AppFile -Raw).Replace("https://github.com/REPLACE_ME/DEVOPS-BACKSTAGE.git", $RepoUrl) | Set-Content -Path $TempAppFile -Encoding utf8

Write-Host "Applying Backstage ArgoCD Application..."
kubectl apply -f $TempAppFile -n $ArgoNamespace

Write-Host ""
Write-Host "Backstage GitOps deployment has been requested through ArgoCD."
Write-Host "When the Backstage service is available, this script will start a port-forward:"
Write-Host "  http://localhost:7007"
Write-Host ""

kubectl wait --for=condition=available deployment/backstage -n $BackstageNamespace --timeout=300s
kubectl port-forward svc/backstage 7007:7007 -n $BackstageNamespace

