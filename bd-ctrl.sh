#!/bin/bash
# bd-ctrl.sh by MSTCY0916
# Version: 0.19
# Date: 2025-07-15
# License: MIT License
# This script manages the installation, upgrade, uninstallation, and cleanup of Black Duck on MicroK8s using Helm.
# It checks for prerequisites, manages the Black Duck deployment, and handles the associated Kubernetes resources.

# Variables
# Note: The variables below are set to default values, you can change them as per your requirements.
# BD_RN: Black Duck Release Name
BD_RN="test"
# BD_NS: Black Duck Namespace
BD_NS="bd"
# BD_NodePort: NodePort for Black Duck
BD_NodePort=30443
# AL_NodePort: NodePort for Black Duck Alert
AL_NodePort=31443

function bd_initialize() {
	# Check if MicroK8s is 		installed
	if [ -z "$(which microk8s)" ]; then
		echo "MicroK8s is not installed. Please install MicroK8s first. Please refer to the official MicroK8s documentation for installation instructions."
		exit 1
	fi
	# Check if MicroK8s is running
	microk8s status &> /dev/null
	if [ $? != "0" ]; then
		echo "MicroK8s is not running. Please start MicroK8s first using 'microk8s start'."
		exit 1
	fi
	# Check if Helm3 addon is enabled
	microk8s status -a helm3 | grep "enabled" &> /dev/null
	if [ $? != "0" ]; then
		echo "Helm3 addin is enabled in MicroK8s. Please enbled it using 'microk8s enable helm3'."
		exit 1
	fi
	# Check if the dns addon is enabled
	microk8s status -a dns | grep "enabled" &> /dev/null
	if [ $? != "0" ]; then
		echo "DNS addon is not enabled in MicroK8s. Please enable it using 'microk8s enable dns'."
		exit 1
	fi
	# Check if the hostpath-storage addon is enabled
	microk8s status -a hostpath-storage | grep "enabled" &> /dev/null
	if [ $? != "0" ]; then
		echo "Hostpath-storage addon is not enabled in MicroK8s. Please enable it using 'microk8s enable hostpath-storage'."
		exit 1
	fi
	# Check if the hostpath-storage
	microk8s kubectl get storageclass microk8s-hostpath &> /dev/null
	if [ $? != "0" ]; then
		echo "Storage class 'microk8s-hostpath' not found. Please ensure it is created."
		exit 1
	fi
	# Check if the namespace exists, if not create it
	microk8s kubectl get ns ${BD_NS} &> /dev/null
	if [ $? != "0" ]; then
		microk8s kubectl create ns ${BD_NS}
		echo "Namespace ${BD_NS} created."
	fi
	# Check if the Helm repository is added
	microk8s helm3 repo list -o yaml | grep bds_repo &> /dev/null
	if [ $? != "0" ]; then
		# Add the Black Duck Helm repository
		# Note: The repository URL is subject to change, please verify the latest URL from the official Black Duck documentation.
		microk8s helm3 repo add bds_repo https://repo.blackduck.com/cloudnative
		# Check if the directory for the Helm chart exists, if not create it
		if [ ! -d "bds_repo" ]; then
			mkdir bds_repo		
			# Pull the Black Duck Helm chart
			microk8s helm3 pull bds_repo/blackduck --untar --untardir bds_repo
		fi
		echo "Black Duck Helm repository added successfully."
	fi
}
function bd_install() {
	bd_initialize
	# Check if the deployment already exists
	microk8s helm3 status ${BD_RN} --namespace ${BD_NS} &> /dev/null
	if [ $? != "0" ]; then
		echo "Installing ${BD_RN} in namespace ${BD_NS}..."
		# Install the Black Duck Helm chart
		microk8s helm3 install ${BD_RN} bds_repo/blackduck --namespace ${BD_NS} \
			--set postgres.isExternal=false \
			--set storageClass=microk8s-hostpath \
			--set exposedNodePort=${BD_NodePort} \
			-f bds_repo/blackduck/sizes-gen05/10sph.yaml
		if [ $? != "0" ]; then
			echo "Failed to install ${BD_RN}. Please check the logs."
			exit 1
		fi
		echo "Black Duck installed successfully in namespace ${BD_NS}. Access it at http://<your-node-ip>:${NodePort}/"
	else
		echo "Already installed ${BD_RN}"
		exit 1
	fi
}
function bd_upgrade() {
	bd_initialize
	# Check if the Helm repository is updated
	microk8s helm3 repo update bds_repo
	if [ $? != "0" ]; then
		echo "Failed to update the Helm repository. Please check the logs."
		exit 1
	fi
	# Check if the directory for the Helm chart exists.
	if [ ! -d "bds_repo" ]; then
		echo "Directory 'bds_repo' not found."
		exit 1
	else
		microk8s helm3 pull bds_repo/blackduck --untar --untardir bds_repo
		if [ $? != "0" ]; then
			echo "Failed to pull the Black Duck Helm chart. Please check the logs."
			exit 1
		fi
		echo "Black Duck Helm chart pulled successfully."
	fi	
	# Check if the deployment exists
	# If it exists, upgrade it
	microk8s helm3 status ${BD_RN} --namespace ${BD_NS} &> /dev/null
	if [ $? != "0" ]; then	
		echo "Not found ${BD_RN}. Please install first."
		exit 1
	else
		microk8s helm3 upgrade ${BD_RN} bds_repo/blackduck --namespace ${BD_NS} --reuse-values
		if [ $? != "0" ]; then
			echo "Failed to upgrade ${BD_RN}. Please check the logs."
			exit 1
		fi
	fi
	echo "Upgraded ${BD_RN} successfully in namespace ${BD_NS}."
}
function bd_uninstall() {
	bd_initialize
	# Check if the release exists for Black Duck Alert
	microk8s helm3 status ${BD_RN}-blackduck-alert bds_repo/blackduck-alert --namespace ${BD_NS} &> /dev/null
	if [ $? = "0" ]; then
		microk8s helm3 uninstall ${BD_RN}-blackduck-alert --namespace ${BD_NS}
		echo "Uninstalled Black Duck Alert from namespace ${BD_NS}."
	fi
	# Check if the release exists for Black Duck
	microk8s helm3 status ${BD_RN} --namespace ${BD_NS} &> /dev/null
	if [ $? = "0" ]; then
		# Uninstall the Black Duck Helm chart	
		microk8s helm3 uninstall ${BD_RN} --namespace ${BD_NS}
		if [ $? = "0" ]; then
			microk8s kubectl delete secret ${BD_RN}-blackduck-db-creds -n ${BD_NS} 2> /dev/null
			microk8s kubectl delete configmap ${BD_RN}-blackduck-db-config -n ${BD_NS} 2> /dev/null	
		else
			echo "Failed to uninstall ${BD_RN}. Please check the logs."
		fi
		microk8s kubectl delete ns ${BD_NS} 2> /dev/null
		if [ $? = "0" ]; then
			echo "Deleted namespace ${BD_NS}."
		else
			echo "Failed to delete namespace ${BD_NS}. Please check the logs."
		fi	
	else
		echo "Not found ${BD_RN}. Nothing to uninstall."
		exit 1	
	fi
}
# This line below is for personal use, have not tested it yet.
# Start/Stop the Black Duck service
function bd_start() {
	microk8s helm3 status ${BD_RN} --namespace ${BD_NS} &> /dev/null
	if [ $? = "0" ]; then
		microk8s kubectl scale --replicas=1 -n ${BD_NS} deployments --selector app=blackduck
		#microk8s kubectl scale deployment ${BD_RN}-blackduck-authentication --replicas=1 -n ${BD_NS}
		#microk8s kubectl scale deployment ${BD_RN}-blackduck-bomengine --replicas=1 -n ${BD_NS}
		#microk8s kubectl scale deployment ${BD_RN}-blackduck-matchengine --replicas=1 -n ${BD_NS}
		#microk8s kubectl scale deployment ${BD_RN}-blackduck-jobrunner --replicas=1 -n ${BD_NS}
		#microk8s kubectl scale deployment ${BD_RN}-blackduck-scan --replicas=1 -n ${BD_NS}
		#microk8s kubectl scale deployment ${BD_RN}-blackduck-webapp-logstash --replicas=1 -n ${BD_NS}
		echo "Black Duck service started."
	else
		echo "Not found ${BD_RN}."
		exit 1
	fi
}
function bd_stop() {
	microk8s helm3 status ${BD_RN} --namespace ${BD_NS} &> /dev/null
	if [ $? = "0" ]; then
		microk8s kubectl scale --replicas=0 -n ${BD_NS} deployments --selector app=blackduck
		#microk8s kubectl scale deployment ${BD_RN}-blackduck-authentication --replicas=0 -n ${BD_NS}
		#microk8s kubectl scale deployment ${BD_RN}-blackduck-bomengine --replicas=0 -n ${BD_NS}
		#microk8s kubectl scale deployment ${BD_RN}-blackduck-matchengine --replicas=0 -n ${BD_NS}
		#microk8s kubectl scale deployment ${BD_RN}-blackduck-jobrunner --replicas=0 -n ${BD_NS}
		#microk8s kubectl scale deployment ${BD_RN}-blackduck-scan --replicas=0 -n ${BD_NS}
		#microk8s kubectl scale deployment ${BD_RN}-blackduck-webapp-logstash --replicas=0 -n ${BD_NS}
		echo "Black Duck service stopped."
	else
		echo "Not found ${BD_RN}."
		exit 1
	fi
}

# Optionally, Backup and restore the database
# This can be implemented using pg_dump and pg_restore commands for PostgreSQL.
# Note: Ensure that the database is not running when performing backup or restore operations.
# Note: This script assumes that the Black Duck Helm chart is compatible with the current version of MicroK8s and Kubernetes.
# Note: This script may not be able to handle the backup and restore of the database in the following cases:
# - The PostgreSQL pod is not running or is inaccessible.
# - The user does not have sufficient permissions to execute backup/restore commands.
# - The database schema or version is incompatible with the backup/restore process.
function bd_backup() {
	echo "Backing up the Black Duck database..."
	#bd_stop
	# This function can be implemented to backup the database using pg_dump
	microk8s kubectl exec -n ${BD_NS} --stdin --tty $(microk8s kubectl get pods -n ${BD_NS} -o name | grep ${BD_RN}-blackduck-postgres) -- pg_dump --clean -U postgres -Fp bds_hub > bds_hub.dump
	if [ $? != "0" ]; then
		echo "Failed to backup the database."
		exit 1
	fi
	echo "Database backup completed successfully. The database dump is saved as bds_hub.dump"
	#bd_start

}
function bd_restore() {
	#bd_stop
	# This function can be implemented to restore the database using pg_restore
	echo "Restore the Black Duck database..."
	if [ ! -f bds_hub.dump ]; then
		echo "Backup file bds_hub.dump not found."
		exit 1
	fi	
	# Restore the database from the dump file
	microk8s kubectl exec -i -n ${BD_NS} --stdin $(microk8s kubectl get pods -n ${BD_NS} -o name | grep ${BD_RN}-blackduck-postgres) -- psql -d bds_hub -U postgres < bds_hub.dump > psql.out 2>&1
	if [ $? = "0" ]; then
		echo "Database restored successfully."
	else
		echo "Failed to restore the database."
	fi
	#bd_start
}
function bd_status() {
	# Check the status of the Black Duck deployment
	microk8s helm3 status ${BD_RN} --namespace ${BD_NS} &> /dev/null
	if [ $? = "0" ]; then
		echo "${BD_RN} is running in namespace ${BD_NS}."
		microk8s kubectl get pods -n ${BD_NS}
	else
		echo "${BD_RN} is not running in namespace ${BD_NS}."
	fi
}
function bd_logs() {
	# Check the logs of the Black Duck deployment
	microk8s helm3 status ${BD_RN} --namespace ${BD_NS} &> /dev/null
	if [ $? = "0" ]; then
		echo "Fetching logs for ${BD_RN} in namespace ${BD_NS}..."
		microk8s kubectl logs -n ${BD_NS} $(microk8s kubectl get pods -n ${BD_NS} -o name | grep ${BD_RN}-blackduck) --all-containers=true
	else
		echo "${BD_RN} is not running in namespace ${BD_NS}."
	fi
}
# Enable the Black Duck Binary Scanner feature
function bd_binary() {
	microk8s helm3 status ${BD_RN} --namespace ${BD_NS} &> /dev/null
	if [ $? != "0" ]; then
		echo "${BD_RN} is not running in namespace ${BD_NS}. Please install or upgrade it first."
		exit 1
	fi
	# Check if the binary is available
	microk8s helm3 upgrade ${BD_RN} bds_repo/blackduck --namespace ${BD_NS} \
		--set enableBinaryScanner=true \
		--reuse-values
	if [ $? != "0" ]; then
		echo "Failed to enable binary for ${BD_RN}. Please check the logs."
		exit 1
	fi
	echo "Binary scanner enabled successfully for ${BD_RN} in namespace ${BD_NS}."
}
# Enable the Black Duck Integration feature
function bd_integration() {
	# Check the status of the Black Duck deployment
	microk8s helm3 status ${BD_RN} --namespace ${BD_NS} &> /dev/null
	if [ $? != "0" ]; then
		echo "${BD_RN} is not running in namespace ${BD_NS}. Please install or upgrade it first."
		exit 1
	fi
	# Upgrade the Black Duck Helm chart to enable integration
	microk8s helm3 upgrade ${BD_RN} bds_repo/blackduck --namespace ${BD_NS} \
		--set enableIntegration=true \
		--reuse-values
	if [ $? != "0" ]; then
		echo "Failed to enable integration for ${BD_RN}. Please check the logs."
		exit 1	
	fi
	echo "Integration enabled successfully for ${BD_RN} in namespace ${BD_NS}."
}
# Enable the Black Duck Alert feature
function al_install() {
	# Check the status of the Black Duck deployment
	microk8s helm3 status ${BD_RN} --namespace ${BD_NS} &> /dev/null
	if [ $? != "0" ]; then
		echo "${BD_RN} is not running in namespace ${BD_NS}. Please install or upgrade it first."
		exit 1
	fi
	# Upgrade the Black Duck Helm chart to enable alert
	microk8s helm3 upgrade ${BD_RN} bds_repo/blackduck --namespace ${BD_NS} \
		--set enableAlert=true \
		--set alertName=${BD_RN}-blackduck-alert \
		--set alertNamespace=${BD_NS} \
		--reuse-values
	if [ $? != "0" ]; then
		echo "Failed to enable alert for ${BD_RN}. Please check the logs."
		exit 1	
	fi
	microk8s helm status ${BD_RN}-blackduck-alert --namespace ${BD_NS} &> /dev/null
	if [ $? != "0" ]; then
		# Install the Black Duck Alert Helm chart
		microk8s helm3 install ${BD_RN}-blackduck-alert bds_repo/blackduck-alert --namespace ${BD_NS} \
			--set deployAlertWithBlackduck=true \
			--set exposedNodePort=${AL_NodePort} \
			--set blackDuckName=${BD_RN} \
			--set blackDuckNamespace=${BD_NS}
		if [ $? != "0" ]; then
			echo "Failed to install Black Duck Alert. Please check the logs."
			exit 1
		fi
	fi
	echo "Black Duck Alert installed successfully in namespace ${BD_NS}. Access it at http://<your-node-ip>:${AL_NodePort}/alert"
}
# Uninstall the Black Duck Alert.
function al_uninstall() {
	# Check if the Black Duck Alert release exists
	microk8s helm3 status ${BD_RN}-blackduck-alert --namespace ${BD_NS} &> /dev/null
	if [ $? != "0" ]; then
		echo "Black Duck Alert is not installed in namespace ${BD_NS}."
		exit 1
	else
		# Uninstall the Black Duck Alert Helm chart
		microk8s helm3 uninstall ${BD_RN}-blackduck-alert --namespace ${BD_NS}
		if [ $? != "0" ]; then
			echo "Failed to uninstall Black Duck Alert. Please check the logs."
			exit 1
		else
			echo "Black Duck Alert uninstalled successfully from namespace ${BD_NS}."
		fi
	fi
	microk8s helm3 status ${BD_RN} --namespace ${BD_NS} &> /dev/null
	if [ $? = "0" ]; then
		# Upgrade the Black Duck Helm chart to disable alert
		microk8s helm3 upgrade ${BD_RN} bds_repo/blackduck --namespace ${BD_NS} \
			--set enableAlert=false \
			--reuse-values
		if [ $? != "0" ]; then
			echo "Failed to disable alert for ${BD_RN}. Please check the logs."
			exit 1
		fi
	fi
}
# Clean up all resources related to Black Duck
# This function will uninstall Black Duck, remove the Helm repository, and delete the namespace.
# It will also remove the backup files and any other resources created during the installation.
# Note: This function will not disable the addons or reset MicroK8s.
# Uncomment the lines below if you want to disable addons and reset MicroK8s.
function bd_clean() {
	bd_uninstall
	microk8s helm3 repo remove bds_repo
	rm -rf bds_repo
	rm -f bds_hub.dump
	rm -f psql.out
	echo "Cleaned up all resources related to ${BD_RN}."
	# Uncomment the following lines if you want to disable addons and reset MicroK8s manually.
	#microk8s disable dns
	#microk8s disable hostpath-storage
	#sudo microk8s reset
	#microk8s enable dns
	#microk8s enable hostpath-storage
}
# Main script execution
if [ "$1" = "install" ]; then
	bd_install
elif [ "$1" = "upgrade" ]; then
	bd_upgrade
elif [ "$1" = "uninstall" ]; then
	bd_uninstall
elif [ "$1" = "clean" ]; then
	bd_clean
elif [ "$1" = "start" ]; then
	bd_start
elif [ "$1" = "stop" ]; then
	bd_stop
elif [ "$1" = "backup" ]; then
	bd_backup
elif [ "$1" = "restore" ]; then
	bd_restore
elif [ "$1" = "binary" ]; then
	bd_binary
elif [ "$1" = "integration" ]; then
	bd_integration
elif [ "$1" = "alert" ]; then
	al_install
elif [ "$1" = "status" ]; then
	bd_status
elif [ "$1" = "log" ]; then
	bd_logs
else
	echo "Usage: ./bd-ctrl.sh [install/upgrade/uninstall]"
	exit 1
fi
# End of script