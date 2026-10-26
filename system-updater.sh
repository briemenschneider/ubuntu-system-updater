#!/bin/bash

# ==============================================================================
# UNIFIED UBUNTU SYSTEM & SERVICE AUTOMATION MAINTENANCE SCRIPT
# ==============================================================================
# This script is designed to run non-interactively via a root crontab.
# It automatically maintains:
#   1. System packages, OS security updates, and apt-managed libraries (Python/Node)
#   2. Docker images and container cleanup
#   3. GitHub Actions self-hosted runners (running as systemd services)
# ==============================================================================

# Tell apt-get to suppress all interactive prompts and accept default configurations.
# This prevents the script from hanging indefinitely waiting for user input.
export DEBIAN_FRONTEND=noninteractive

# Record the start time of the maintenance cycle in the logs
echo "========================================================================"
echo "=== MAINTENANCE START: $(date) ==="
echo "========================================================================"

# ------------------------------------------------------------------------------
# SECTION 1: OS PACKAGES, SECURITY PATCHES, AND SYSTEM LIBRARIES
# ------------------------------------------------------------------------------
echo ""
echo "--> [1/3] Step: Updating Apt Repositories and Packages..."

# Sync local package indexes with remote repositories to find newer available versions
apt-get update -y

# Upgrade existing packages (handles security patches and minor version bumps)
apt-get upgrade -y

# Perform a smart upgrade that handles changing dependencies in newer package versions
apt-get dist-upgrade -y

# Clean up orphaned packages that were installed as dependencies but are no longer needed
apt-get autoremove -y

# Clear out the local repository cache of downloaded package files (.deb) to reclaim disk space
apt-get autoclean -y


# ------------------------------------------------------------------------------
# SECTION 2: DOCKER INFRASTRUCTURE & RESOURCE CLEANUP
# ------------------------------------------------------------------------------
echo ""
echo "--> [2/3] Step: Checking for Docker Infrastructure..."

# Verify if Docker is installed on the host before running Docker commands
if command -v docker &> /dev/null; then
    
    # Check if there are any running containers on the system
    if [ "$(docker ps -q)" ]; then
        echo "    Pulling updated base images for all actively running containers..."
        
        # 1. 'docker ps' finds images currently powering live containers
        # 2. 'sort -u' filters out duplicate image names to optimize traffic
        # 3. 'xargs' passes each image string sequentially to a 'docker pull' statement
        docker ps --format "{{.Image}}" | sort -u | xargs -I {} docker pull {}
    else
        echo "    No running Docker containers found. Skipping image pull."
    fi
    
    echo "    Pruning unused Docker resources..."
    # Safely purges stopped containers, unused networks, and dangling/unused build images.
    # The '--volumes' flag ensures orphaned, unattached volumes are swept up as well.
    docker system prune -a -f --volumes

else
    echo "    Docker is not installed on this host. Skipping Docker updates."
fi


# ------------------------------------------------------------------------------
# SECTION 3: GITHUB ACTIONS SELF-HOSTED RUNNERS (SYSTEMD)
# ------------------------------------------------------------------------------
echo ""
echo "--> [3/3] Step: Managing GitHub Actions Systemd Services..."

# Scan systemd configurations to capture all active or inactive runner service file names
# GitHub runners typically register with a naming convention like 'actions.runner.*.service'
RUNNER_SERVICES=$(systemctl list-unit-files --type=service | grep -E "actions\.runner" | awk '{print $1}')

if [ ! -z "$RUNNER_SERVICES" ]; then
    for SERVICE in $RUNNER_SERVICES; do
        echo "    Evaluating service: $SERVICE"
        
        # Check the service's log journal to make sure it isn't currently processing a job.
        # This scans the last 20 log lines for the token 'Running job:' to protect workflows.
        if journalctl -u "$SERVICE" -n 20 --no-pager | grep -q "Running job:"; then
            echo "    [WARNING] $SERVICE is currently busy processing a CI/CD job! Skipping restart to protect workflow."
        else
            echo "    $SERVICE is idle. Restarting to inherit updated system paths and clear memory..."
            # Bouncing the service forces it to immediately verify core runner updates from GitHub.
            systemctl restart "$SERVICE"
        fi
    done
else
    echo "    No actions.runner systemd services detected on this machine."
fi


# Record the completion timestamp of the maintenance cycle
echo ""
echo "========================================================================"
echo "=== MAINTENANCE FINISHED: $(date) ==="
echo "========================================================================"
