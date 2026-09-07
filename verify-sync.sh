#!/bin/bash
# Run this from the same directory as main.tf, BEFORE terraform plan/apply.
# Checks every file touched by the auth.gavoksolutions.com integration and
# the eks module v21 rename fix, so any leftover stale copy shows up in one
# pass instead of one terraform error at a time.

fail=0

check() {
  local file="$1" pattern="$2" label="$3"
  if [ ! -f "$file" ]; then
    echo "MISSING FILE: $file"
    fail=1
  elif grep -qE "$pattern" "$file"; then
    echo "OK      $file : $label"
  else
    echo "STALE   $file : $label"
    fail=1
  fi
}

check_absent() {
  local file="$1" pattern="$2" label="$3"
  if [ -f "$file" ] && grep -qE "$pattern" "$file"; then
    echo "STALE   $file : $label (should be gone)"
    fail=1
  elif [ -f "$file" ]; then
    echo "OK      $file : $label"
  fi
}

echo "== migration job made non-blocking =="
check     "modules/app/main.tf" 'wait_for_completion\s*=\s*false'    'db_migration no longer gates the whole apply'

echo
echo "== root variables.tf =="
check     "variables.tf" 'variable "zone_name"'                       'declares zone_name'
check     "variables.tf" 'variable "acm_subject_alternative_names"'   'declares acm_subject_alternative_names'
check     "variables.tf" 'default *= *"auth\.gavoksolutions\.com"'    'domain_name default set'
check     "variables.tf" 'default *= *false'                          'has at least one false default (create_hosted_zone)'

echo
echo "== ingress_hostname graceful-null fix =="
check     "modules/app/outputs.tf" 'try\(kubernetes_ingress_v1\.app\.status'  'ingress_hostname wrapped in try(), not a hard reference'
check     "main.tf" 'count\s*=\s*module\.app\.ingress_hostname'               'aws_route53_record.app skips cleanly via count instead of erroring'

echo
echo "== root main.tf =="
check     "main.tf" 'zone_name *= *var\.zone_name'                    'dns_tls block wires zone_name'
check     "main.tf" 'record_name *= *var\.domain_name'                'dns_tls block wires record_name'
if [ -f "main.tf" ]; then
  dns_tls_block=$(awk '/module "dns_tls" {/,/^}/' main.tf)
  if echo "$dns_tls_block" | grep -qE '^\s*domain_name\s*=\s*var\.domain_name\s*$'; then
    echo "STALE   main.tf : dns_tls block still has old single domain_name arg (should be gone)"
    fail=1
  else
    echo "OK      main.tf : old single domain_name arg to dns_tls (should be gone)"
  fi
fi

echo
echo "== modules/dns-tls/variables.tf =="
check     "modules/dns-tls/variables.tf" 'variable "zone_name"'               'declares zone_name'
check     "modules/dns-tls/variables.tf" 'variable "record_name"'             'declares record_name'
check     "modules/dns-tls/variables.tf" 'variable "subject_alternative_names"' 'declares subject_alternative_names'
check_absent "modules/dns-tls/variables.tf" 'variable "domain_name"'          'old domain_name variable'

echo
echo "== modules/dns-tls/main.tf =="
check     "modules/dns-tls/main.tf" 'var\.zone_name'                  'uses var.zone_name'
check     "modules/dns-tls/main.tf" 'var\.record_name'                'uses var.record_name'
check_absent "modules/dns-tls/main.tf" 'var\.domain_name'             'old var.domain_name reference'

echo
echo "== modules/eks/main.tf (v21 rename fix) =="
check     "modules/eks/main.tf" '^\s*name\s*=\s*var\.cluster_name'    'uses name= (not cluster_name=)'
check     "modules/eks/main.tf" 'kubernetes_version\s*=\s*var\.cluster_version' 'uses kubernetes_version='
check     "modules/eks/main.tf" '^\s*endpoint_public_access\s*=\s*true' 'uses endpoint_public_access='
check_absent "modules/eks/main.tf" 'cluster_endpoint_public_access'   'old cluster_endpoint_public_access'
check     "modules/eks/main.tf" 'addons\s*=\s*\{'                     'declares addons (vpc-cni/kube-proxy/coredns)'
check     "modules/eks/main.tf" 'vpc-cni'                              'addons block includes vpc-cni'
check     "modules/eks/main.tf" 'resource "aws_eks_addon" "ebs_csi"'   'ebs-csi addon declared as its own resource (not inside addons{})'
check_absent "modules/eks/main.tf" 'aws-ebs-csi-driver\s*=\s*\{'       'ebs-csi nested inside the addons{} block (causes the undeclared-module error)'
check     "modules/eks/main.tf" 'attach_ebs_csi_policy\s*=\s*true'     'ebs_csi_irsa role declared'
check     "modules/eks/main.tf" 'kubernetes_storage_class_v1'          'default gp3 StorageClass declared'
check     "modules/eks/versions.tf" 'hashicorp/kubernetes'             'versions.tf includes the kubernetes provider'

echo
echo "== modules/alb-controller/main.tf (IngressClass collision fix) =="
check     "modules/alb-controller/main.tf" 'createIngressClassResource'  'disables the chart-created IngressClass'
check     "modules/alb-controller/main.tf" 'keepTLSSecret'               'reuses the webhook TLS cert across upgrades'

echo
echo "== providers.tf (helm provider v3 rewrite) =="
check     "providers.tf" 'kubernetes\s*=\s*\{'                        'helm provider uses kubernetes = { (object attribute)'
check_absent "providers.tf" '^\s*kubernetes\s*\{\s*$'                 'old kubernetes {} block'

echo
echo "== modules/alb-controller/main.tf (helm provider v3 rewrite) =="
check     "modules/alb-controller/main.tf" 'set\s*=\s*\['             'uses set = [ ... ] list'
check_absent "modules/alb-controller/main.tf" '^\s*set\s*\{\s*$'      'old repeatable set {} blocks'

echo
echo "== modules/cert-manager/main.tf (helm provider v3 rewrite) =="
check     "modules/cert-manager/main.tf" 'set\s*=\s*\['               'uses set = [ ... ] list'
check_absent "modules/cert-manager/main.tf" '^\s*set\s*\{\s*$'        'old repeatable set {} blocks'

echo
if [ "$fail" -eq 0 ]; then
  echo "All checked files are current. Safe to run terraform plan."
else
  echo "One or more files above are STALE or MISSING — replace those specific files before re-running terraform."
fi
