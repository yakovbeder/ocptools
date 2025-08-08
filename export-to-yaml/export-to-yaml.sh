#!/bin/bash

# Script: export-to-yaml-v2.sh
# Description: Enhanced export of Kubernetes/OpenShift resources to clean YAML format
# Author: OpenShift Tools
# Version: 3.0
# Features: Multi-resource export, dry-run mode, backup functionality, progress tracking

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Global variables
SCRIPT_VERSION="3.0"
VERBOSE=false
DRY_RUN=false
BACKUP_DIR=""
QUIET=false

# Function to print colored output
print_status() {
    [[ "$QUIET" != true ]] && echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    [[ "$QUIET" != true ]] && echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

print_debug() {
    [[ "$VERBOSE" == true ]] && echo -e "${BLUE}[DEBUG]${NC} $1"
}

print_success() {
    [[ "$QUIET" != true ]] && echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 <resource> <name> [options]

Arguments:
  resource    Kubernetes resource type (e.g., secret, configmap, deployment)
  name        Name of the resource (use 'all' for all resources of type)

Options:
  -n, --namespace <namespace>    Specify namespace (default: current context)
  -o, --output <file>            Output file (default: stdout)
  -f, --force                    Overwrite output file if it exists
  -v, --verbose                  Enable verbose output
  -q, --quiet                    Suppress non-error output
  -d, --dry-run                  Show what would be done without doing it
  -b, --backup <dir>             Create backup before overwriting
  -k, --keep-labels              Keep metadata.labels (default: remove)
  -a, --keep-annotations         Keep metadata.annotations (default: remove)
  -h, --help                     Show this help message
  --version                      Show version information

Examples:
  $0 secret my-secret
  $0 configmap my-config -n my-namespace
  $0 deployment my-app -o my-app.yaml
  $0 pvc my-pvc -n storage -o my-pvc.yaml -f
  $0 secret all -n my-namespace -o secrets.yaml
  $0 deployment all -n default -o deployments.yaml -b ./backups

Advanced Features:
  - Export all resources of a type: $0 secret all -n my-namespace
  - Dry run mode: $0 deployment my-app -d
  - Backup before overwrite: $0 configmap my-config -o config.yaml -b ./backups
  - Keep specific metadata: $0 secret my-secret -k -a

EOF
}

# Function to show version
show_version() {
    echo "export-to-yaml.sh version $SCRIPT_VERSION"
    echo "Enhanced Kubernetes/OpenShift resource export tool"
}

# Function to check dependencies
check_dependencies() {
    local missing_deps=()
    
    if ! command -v oc &> /dev/null; then
        missing_deps+=("oc")
    fi
    
    if ! command -v yq &> /dev/null; then
        missing_deps+=("yq")
    else
        # Check yq version (need 4.x)
        local yq_version
        yq_version=$(yq --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)
        if [[ -z "$yq_version" ]] || [[ "${yq_version%%.*}" -lt 4 ]]; then
            print_error "yq version 4.x is required. Current version: $yq_version"
            exit 1
        fi
        print_debug "yq version: $yq_version"
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_error "Missing required dependencies: ${missing_deps[*]}"
        print_status "Please install: ${missing_deps[*]}"
        exit 1
    fi
}

# Function to check if resource exists
check_resource_exists() {
    local resource="$1"
    local name="$2"
    local namespace="$3"
    
    local oc_cmd="oc get $resource $name"
    if [[ -n "$namespace" ]]; then
        oc_cmd="$oc_cmd -n $namespace"
    fi
    
    if ! $oc_cmd &>/dev/null; then
        print_error "Resource '$resource/$name' not found"
        if [[ -n "$namespace" ]]; then
            print_error "Namespace: $namespace"
        fi
        exit 1
    fi
}

# Function to get all resources of a type
get_all_resources() {
    local resource="$1"
    local namespace="$2"
    
    local oc_cmd="oc get $resource -o name"
    if [[ -n "$namespace" ]]; then
        oc_cmd="$oc_cmd -n $namespace"
    fi
    
    $oc_cmd | sed "s/^${resource}\///"
}

# Function to create backup
create_backup() {
    local file="$1"
    local backup_dir="$2"
    
    if [[ ! -f "$file" ]]; then
        return 0
    fi
    
    if [[ ! -d "$backup_dir" ]]; then
        mkdir -p "$backup_dir"
        print_debug "Created backup directory: $backup_dir"
    fi
    
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_file="$backup_dir/$(basename "$file").backup.$timestamp"
    
    cp "$file" "$backup_file"
    print_status "Backup created: $backup_file"
}

# Function to clean YAML with configurable options
clean_yaml() {
    local input="$1"
    local keep_labels="$2"
    local keep_annotations="$3"
    
    local yq_expr="del("
    
    # Always remove these fields
    yq_expr+="
        .metadata.creationTimestamp,
        .metadata.namespace,
        .metadata.finalizers,
        .metadata.resourceVersion,
        .metadata.uid,
        .metadata.managedFields,
        .metadata.ownerReferences,
        .status,
        .metadata.generation"
    
    # Conditionally remove labels and annotations
    if [[ "$keep_labels" != true ]]; then
        yq_expr+=", .metadata.labels"
    fi
    
    if [[ "$keep_annotations" != true ]]; then
        yq_expr+=", .metadata.annotations"
    fi
    
    yq_expr+=") | .metadata.name = .metadata.name | .metadata.namespace = null"
    
    yq eval "$yq_expr" "$input"
}

# Function to export single resource
export_resource() {
    local resource="$1"
    local name="$2"
    local namespace="$3"
    local output_file="$4"
    local keep_labels="$5"
    local keep_annotations="$6"
    
    print_status "Exporting $resource/$name"
    if [[ -n "$namespace" ]]; then
        print_status "Namespace: $namespace"
    fi
    
    # Build oc command
    local oc_cmd="oc get $resource $name -o yaml"
    if [[ -n "$namespace" ]]; then
        oc_cmd="$oc_cmd -n $namespace"
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        print_debug "Would run: $oc_cmd"
        if [[ -n "$output_file" ]]; then
            print_debug "Would output to: $output_file"
        fi
        return 0
    fi
    
    # Export and clean the resource
    if [[ -n "$output_file" ]]; then
        if [[ "$output_file" == "-" ]]; then
            $oc_cmd | clean_yaml - "$keep_labels" "$keep_annotations"
        else
            print_status "Output file: $output_file"
            $oc_cmd | clean_yaml - "$keep_labels" "$keep_annotations" > "$output_file"
            print_success "Resource exported successfully to $output_file"
        fi
    else
        $oc_cmd | clean_yaml - "$keep_labels" "$keep_annotations"
    fi
}

# Function to export multiple resources
export_multiple_resources() {
    local resource="$1"
    local namespace="$2"
    local output_file="$3"
    local keep_labels="$4"
    local keep_annotations="$5"
    
    local resources
    resources=$(get_all_resources "$resource" "$namespace")
    
    if [[ -z "$resources" ]]; then
        print_warning "No $resource resources found"
        if [[ -n "$namespace" ]]; then
            print_warning "Namespace: $namespace"
        fi
        return 0
    fi
    
    local count=$(echo "$resources" | wc -l)
    print_status "Found $count $resource resources"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "$resources" | while read -r name; do
            print_debug "Would export: $resource/$name"
        done
        return 0
    fi
    
    local temp_file
    temp_file=$(mktemp)
    
    local exported_count=0
    echo "$resources" | while read -r name; do
        print_debug "Exporting $resource/$name ($((++exported_count))/$count)"
        
        local oc_cmd="oc get $resource $name -o yaml"
        if [[ -n "$namespace" ]]; then
            oc_cmd="$oc_cmd -n $namespace"
        fi
        
        # Add separator between resources
        if [[ $exported_count -gt 1 ]]; then
            echo "---" >> "$temp_file"
        fi
        
        $oc_cmd | clean_yaml - "$keep_labels" "$keep_annotations" >> "$temp_file"
    done
    
    if [[ -n "$output_file" ]]; then
        mv "$temp_file" "$output_file"
        print_success "Exported $count resources to $output_file"
    else
        cat "$temp_file"
        rm "$temp_file"
    fi
}

# Parse command line arguments
RESOURCE=""
NAME=""
NAMESPACE=""
OUTPUT_FILE=""
FORCE=false
KEEP_LABELS=false
KEEP_ANNOTATIONS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -q|--quiet)
            QUIET=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -b|--backup)
            BACKUP_DIR="$2"
            shift 2
            ;;
        -k|--keep-labels)
            KEEP_LABELS=true
            shift
            ;;
        -a|--keep-annotations)
            KEEP_ANNOTATIONS=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        --version)
            show_version
            exit 0
            ;;
        -*)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
        *)
            if [[ -z "$RESOURCE" ]]; then
                RESOURCE="$1"
            elif [[ -z "$NAME" ]]; then
                NAME="$1"
            else
                print_error "Too many arguments"
                show_usage
                exit 1
            fi
            shift
            ;;
    esac
done

# Validate required arguments
if [[ -z "$RESOURCE" || -z "$NAME" ]]; then
    print_error "Missing required arguments"
    show_usage
    exit 1
fi

# Check dependencies
check_dependencies

# Check if output file exists and handle backup/force
if [[ -n "$OUTPUT_FILE" && "$OUTPUT_FILE" != "-" && -f "$OUTPUT_FILE" ]]; then
    if [[ "$FORCE" != true ]]; then
        print_error "Output file '$OUTPUT_FILE' already exists. Use -f to overwrite."
        exit 1
    fi
    
    if [[ -n "$BACKUP_DIR" ]]; then
        create_backup "$OUTPUT_FILE" "$BACKUP_DIR"
    fi
fi

# Handle 'all' resources export
if [[ "$NAME" == "all" ]]; then
    export_multiple_resources "$RESOURCE" "$NAMESPACE" "$OUTPUT_FILE" "$KEEP_LABELS" "$KEEP_ANNOTATIONS"
else
    # Check if resource exists for single resource export
    check_resource_exists "$RESOURCE" "$NAME" "$NAMESPACE"
    export_resource "$RESOURCE" "$NAME" "$NAMESPACE" "$OUTPUT_FILE" "$KEEP_LABELS" "$KEEP_ANNOTATIONS"
fi
