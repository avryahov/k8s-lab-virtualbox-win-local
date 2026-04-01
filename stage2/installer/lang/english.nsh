; =============================================================================
; english.nsh — Interface strings in English
; =============================================================================
; Used by: stage2/installer/k8s-lab.nsi
; Language: English (LangId 1033)
; =============================================================================

; --- Install Mode ---
LangString STR_MODE_TITLE      ${LANG_ENGLISH} "Install Mode"
LangString STR_MODE_SUBTITLE   ${LANG_ENGLISH} "Choose how to configure the cluster"
LangString STR_MODE_DESC       ${LANG_ENGLISH} "How do you want to set up the cluster?"
LangString STR_MODE_QUICK      ${LANG_ENGLISH} "Quick install (all default values)"
LangString STR_MODE_QUICK_HINT ${LANG_ENGLISH} "Master: 2 CPU, 2048 MB RAM, 30 GB HDD. Workers: 2 nodes, 2 CPU, 2048 MB RAM. Network: 192.168.56.x"
LangString STR_MODE_ADVANCED   ${LANG_ENGLISH} "Advanced configuration"
LangString STR_MODE_ADVANCED_HINT ${LANG_ENGLISH} "Configure all parameters manually: node resources, network, ports, bridges. More control, but more steps."

; --- General ---
LangString STR_WELCOME_TITLE     ${LANG_ENGLISH} "Kubernetes Cluster Lab"
LangString STR_WELCOME_TEXT      ${LANG_ENGLISH} "This wizard will set up a local Kubernetes cluster on your computer.$\n$\nThe cluster will include:$\n  • 1 control-plane node (master)$\n  • One or more worker nodes$\n$\nRequirements: VirtualBox 7.x and Vagrant 2.4+.$\n$\nClick Next to begin."

; --- Dependency checks ---
LangString STR_DEPS_TITLE        ${LANG_ENGLISH} "Checking Requirements"
LangString STR_DEPS_SUBTITLE     ${LANG_ENGLISH} "Making sure all prerequisites are installed"
LangString STR_DEPS_VAGRANT      ${LANG_ENGLISH} "Vagrant"
LangString STR_DEPS_VBOX         ${LANG_ENGLISH} "VirtualBox"
LangString STR_DEPS_OK           ${LANG_ENGLISH} "✓ found"
LangString STR_DEPS_MISSING      ${LANG_ENGLISH} "✗ not found"
LangString STR_DEPS_WARN_VAGRANT ${LANG_ENGLISH} "Vagrant not found!$\n$\nPlease download and install it from:$\nhttps://developer.hashicorp.com/vagrant/downloads$\n$\nContinue without Vagrant?"
LangString STR_DEPS_WARN_VBOX    ${LANG_ENGLISH} "VirtualBox not found!$\n$\nPlease download and install it from:$\nhttps://www.virtualbox.org/wiki/Downloads$\n$\nContinue without VirtualBox?"
LangString STR_DEPS_HINT         ${LANG_ENGLISH} "If anything is missing — install it and re-run this wizard."

; --- Install directory ---
LangString STR_DIR_TITLE         ${LANG_ENGLISH} "Project Folder"
LangString STR_DIR_SUBTITLE      ${LANG_ENGLISH} "Where should the cluster files be placed?"
LangString STR_DIR_LABEL         ${LANG_ENGLISH} "Folder:"
LangString STR_DIR_BROWSE        ${LANG_ENGLISH} "Browse..."

; --- Master node configuration ---
LangString STR_MASTER_TITLE      ${LANG_ENGLISH} "Master Node Configuration"
LangString STR_MASTER_SUBTITLE   ${LANG_ENGLISH} "Control-plane node parameters"
LangString STR_MASTER_PREFIX     ${LANG_ENGLISH} "VM name prefix"
LangString STR_MASTER_CPU        ${LANG_ENGLISH} "CPUs"
LangString STR_MASTER_RAM        ${LANG_ENGLISH} "RAM (MB)"
LangString STR_MASTER_HDD        ${LANG_ENGLISH} "Virtual disk (GB)"
LangString STR_MASTER_HINT       ${LANG_ENGLISH} "The master node manages the cluster. Recommended: 2+ CPUs and 2048+ MB RAM."

; --- Network configuration ---
LangString STR_NETWORK_TITLE     ${LANG_ENGLISH} "Network Configuration"
LangString STR_NETWORK_SUBTITLE  ${LANG_ENGLISH} "Network connection parameters"
LangString STR_NETWORK_SUBNET    ${LANG_ENGLISH} "Subnet (first 3 octets)"
LangString STR_NETWORK_MASK      ${LANG_ENGLISH} "Subnet mask"
LangString STR_NETWORK_BRIDGE    ${LANG_ENGLISH} "Network adapter (bridge)"
LangString STR_NETWORK_ADAPTER   ${LANG_ENGLISH} "Second adapter"
LangString STR_NETWORK_ADAPTER_NONE ${LANG_ENGLISH} "None"
LangString STR_NETWORK_ADAPTER_BRIDGE ${LANG_ENGLISH} "Bridged"
LangString STR_NETWORK_ADAPTER_NAT ${LANG_ENGLISH} "NAT"
LangString STR_NETWORK_MASTER_PORT ${LANG_ENGLISH} "Master SSH port"
LangString STR_NETWORK_API_PORT  ${LANG_ENGLISH} "API port (kube-apiserver)"
LangString STR_NETWORK_DASH_PORT ${LANG_ENGLISH} "Dashboard port"
LangString STR_NETWORK_HINT      ${LANG_ENGLISH} "Bridged gives VMs direct access to the physical network. NAT isolates VMs within the host."
LangString STR_NETWORK_PORT_WARN ${LANG_ENGLISH} "Port $0 is already in use!$\n$\nChoose a different port?"
LangString STR_NETWORK_PORT_CHECK ${LANG_ENGLISH} "Checking ports..."
LangString STR_NETWORK_PORT_OK   ${LANG_ENGLISH} "All ports are free"
LangString STR_NETWORK_PORT_BUSY ${LANG_ENGLISH} "Port $0 is busy"

; --- Worker node configuration ---
LangString STR_WORKER_TITLE      ${LANG_ENGLISH} "Worker Nodes Configuration"
LangString STR_WORKER_SUBTITLE   ${LANG_ENGLISH} "Worker node parameters"
LangString STR_WORKER_COUNT      ${LANG_ENGLISH} "Number of worker nodes"
LangString STR_WORKER_CPU        ${LANG_ENGLISH} "CPUs per node"
LangString STR_WORKER_RAM        ${LANG_ENGLISH} "RAM per node (MB)"
LangString STR_WORKER_HDD        ${LANG_ENGLISH} "Virtual disk per node (GB)"
LangString STR_WORKER_HINT       ${LANG_ENGLISH} "Worker nodes run containers. Recommended: 2+ CPUs and 2048+ MB RAM per node."

; --- Summary ---
LangString STR_SUMMARY_TITLE     ${LANG_ENGLISH} "Configuration Summary"
LangString STR_SUMMARY_SUBTITLE  ${LANG_ENGLISH} "Review your settings before launching"
LangString STR_SUMMARY_HEADER    ${LANG_ENGLISH} "Cluster to be created:"
LangString STR_SUMMARY_PREFIX    ${LANG_ENGLISH} "VM prefix:"
LangString STR_SUMMARY_MASTER    ${LANG_ENGLISH} "Master:"
LangString STR_SUMMARY_WORKERS   ${LANG_ENGLISH} "Worker nodes:"
LangString STR_SUMMARY_WORKER    ${LANG_ENGLISH} "Each Worker:"
LangString STR_SUMMARY_NETWORK   ${LANG_ENGLISH} "Network:"
LangString STR_SUMMARY_SUBNET    ${LANG_ENGLISH} "Subnet:"
LangString STR_SUMMARY_BRIDGE    ${LANG_ENGLISH} "Bridge:"
LangString STR_SUMMARY_PORTS     ${LANG_ENGLISH} "Ports:"
LangString STR_SUMMARY_DIR       ${LANG_ENGLISH} "Project folder:"
LangString STR_SUMMARY_SMOKE     ${LANG_ENGLISH} "Smoke test:"
LangString STR_SUMMARY_NOTE      ${LANG_ENGLISH} "Installation will take 15–30 minutes (Ubuntu image download + Kubernetes setup)."

; --- Installation ---
LangString STR_INSTALL_TITLE     ${LANG_ENGLISH} "Starting Cluster"
LangString STR_INSTALL_SUBTITLE  ${LANG_ENGLISH} "Please wait while the cluster is being set up..."
LangString STR_INSTALL_COPY      ${LANG_ENGLISH} "Copying project files..."
LangString STR_INSTALL_CONFIG    ${LANG_ENGLISH} "Creating .env configuration..."
LangString STR_INSTALL_KEYS      ${LANG_ENGLISH} "Generating SSH keys..."
LangString STR_INSTALL_VAGRANT_INIT ${LANG_ENGLISH} "Initializing Vagrant..."
LangString STR_INSTALL_VAGRANT_UP ${LANG_ENGLISH} "Starting virtual machines (vagrant up)..."
LangString STR_INSTALL_BOOTSTRAP ${LANG_ENGLISH} "Setting up Kubernetes (bootstrap)..."
LangString STR_INSTALL_NETWORK   ${LANG_ENGLISH} "Configuring network (CNI)..."
LangString STR_INSTALL_DASHBOARD ${LANG_ENGLISH} "Installing Dashboard..."
LangString STR_INSTALL_TOKEN     ${LANG_ENGLISH} "Generating access token..."
LangString STR_INSTALL_DONE      ${LANG_ENGLISH} "Cluster is ready!"

; --- Smoke test ---
LangString STR_SMOKE_TITLE       ${LANG_ENGLISH} "Smoke Testing"
LangString STR_SMOKE_SUBTITLE    ${LANG_ENGLISH} "Cluster health verification"
LangString STR_SMOKE_RUN         ${LANG_ENGLISH} "Run smoke test after installation"
LangString STR_SMOKE_DESC        ${LANG_ENGLISH} "The smoke test will deploy nginx pods, verify networking and services inside the cluster, then show results.$\nThis will take 2–5 minutes after installation completes."
LangString STR_SMOKE_YES         ${LANG_ENGLISH} "Yes, run it"
LangString STR_SMOKE_NO          ${LANG_ENGLISH} "No, skip"

; --- Smoke test results ---
LangString STR_SMOKE_RES_TITLE   ${LANG_ENGLISH} "Smoke Test Results"
LangString STR_SMOKE_RES_SUBTITLE ${LANG_ENGLISH} "Test completed"
LangString STR_SMOKE_RES_RUNNING  ${LANG_ENGLISH} "Running smoke test..."
LangString STR_SMOKE_RES_PASS    ${LANG_ENGLISH} "Smoke test passed successfully!"
LangString STR_SMOKE_RES_FAIL    ${LANG_ENGLISH} "Smoke test failed. Check the logs."
LangString STR_SMOKE_RES_NODES   ${LANG_ENGLISH} "Nodes:"
LangString STR_SMOKE_RES_PODS    ${LANG_ENGLISH} "Pods:"
LangString STR_SMOKE_RES_SVC     ${LANG_ENGLISH} "Services:"
LangString STR_SMOKE_RES_JOB     ${LANG_ENGLISH} "Job check:"

; --- Finish ---
LangString STR_FINISH_TITLE      ${LANG_ENGLISH} "Installation Complete"
LangString STR_FINISH_SUBTITLE   ${LANG_ENGLISH} "Kubernetes cluster is up and running"
LangString STR_FINISH_TEXT       ${LANG_ENGLISH} "Your Kubernetes cluster is up and running!"
LangString STR_FINISH_DASHBOARD  ${LANG_ENGLISH} "Dashboard:"
LangString STR_FINISH_DASHBOARD_URL ${LANG_ENGLISH} "https://localhost:30443"
LangString STR_FINISH_TOKEN      ${LANG_ENGLISH} "Login token:"
LangString STR_FINISH_TOKEN_FILE ${LANG_ENGLISH} "dashboard-token.txt"
LangString STR_FINISH_KUBECONFIG ${LANG_ENGLISH} "kubeconfig:"
LangString STR_FINISH_KUBECONFIG_FILE ${LANG_ENGLISH} "kubeconfig-stage1.yaml"
LangString STR_FINISH_NODES      ${LANG_ENGLISH} "Nodes:"
LangString STR_FINISH_OPEN       ${LANG_ENGLISH} "Open project folder"
LangString STR_FINISH_DOCS       ${LANG_ENGLISH} "Open documentation"

; --- Master Network ---
LangString STR_MASTERNET_TITLE   ${LANG_ENGLISH} "Master Node Network"
LangString STR_MASTERNET_SUBTITLE ${LANG_ENGLISH} "Master node network parameters"
LangString STR_MASTERNET_HINT    ${LANG_ENGLISH} "Bridged gives the master node direct access to the physical network. NAT isolates the VM within the host."

; --- Worker Network Mode ---
LangString STR_WORKERNETMODE_TITLE ${LANG_ENGLISH} "Worker Network Mode"
LangString STR_WORKERNETMODE_SUBTITLE ${LANG_ENGLISH} "How to configure worker node networking?"
LangString STR_WORKERNETMODE_DESC ${LANG_ENGLISH} "Choose how to configure networking for worker nodes:"
LangString STR_WORKERNETMODE_COMMON ${LANG_ENGLISH} "Common network for all worker nodes"
LangString STR_WORKERNETMODE_COMMON_HINT ${LANG_ENGLISH} "One subnet and bridge for all. SSH ports will be assigned automatically (base port + 10 for each node)."
LangString STR_WORKERNETMODE_INDIVIDUAL ${LANG_ENGLISH} "Individual network for each worker node"
LangString STR_WORKERNETMODE_INDIVIDUAL_HINT ${LANG_ENGLISH} "Each node gets its own subnet, bridge, and port. More control, but more configuration steps."

; --- Worker Network ---
LangString STR_WORKERNET_TITLE   ${LANG_ENGLISH} "Worker Nodes Network"
LangString STR_WORKERNET_SUBTITLE ${LANG_ENGLISH} "Network connection parameters"
LangString STR_WORKERNET_SSH_BASE ${LANG_ENGLISH} "Base SSH port"
LangString STR_WORKERNET_SSH_PORT ${LANG_ENGLISH} "SSH port"
LangString STR_WORKERNET_COMMON_HINT ${LANG_ENGLISH} "Each worker node gets IP: base_subnet.11, .12, .13, .14$\nSSH ports: base_port, base+10, base+20, base+30"
LangString STR_WORKERNET_INDIVIDUAL ${LANG_ENGLISH} "Individual settings"

; --- Summary (additional) ---
LangString STR_SUMMARY_MASTER_NET ${LANG_ENGLISH} "Master Network:"
LangString STR_SUMMARY_WORKER_NET ${LANG_ENGLISH} "Worker Network:"

; --- Errors ---
LangString STR_ERR_VAGRANT_FAIL  ${LANG_ENGLISH} "vagrant up failed.$\nCheck the logs in the project folder.$\nFor diagnostics: vagrant status"
LangString STR_ERR_NO_ADMIN      ${LANG_ENGLISH} "Administrator privileges required.$\nPlease run the installer as Administrator."
LangString STR_ERR_INVALID_SUBNET ${LANG_ENGLISH} "Invalid subnet format.$\nEnter the first 3 octets, e.g.: 192.168.56"
LangString STR_ERR_SHORT_PREFIX  ${LANG_ENGLISH} "Prefix too short (minimum 2 characters)."
LangString STR_ERR_CPU_RANGE     ${LANG_ENGLISH} "CPU: 1 to 8."
LangString STR_ERR_RAM_RANGE     ${LANG_ENGLISH} "RAM: 512 to 16384 MB."
LangString STR_ERR_WORKER_COUNT_RANGE ${LANG_ENGLISH} "Worker count: 1 to 4."
LangString STR_ERR_PORT_RANGE    ${LANG_ENGLISH} "Port: 1024 to 65535."

; --- Use defaults checkbox ---
LangString STR_USE_DEFAULTS      ${LANG_ENGLISH} "Use default values"

; --- Summary tree ---
LangString STR_SUMMARY_TREE_TITLE    ${LANG_ENGLISH} "Cluster Tree"
LangString STR_SUMMARY_TREE_MASTER   ${LANG_ENGLISH} "Master Node"
LangString STR_SUMMARY_TREE_WORKER   ${LANG_ENGLISH} "Worker Node"
LangString STR_SUMMARY_TREE_CPU      ${LANG_ENGLISH} "CPU"
LangString STR_SUMMARY_TREE_RAM      ${LANG_ENGLISH} "RAM"
LangString STR_SUMMARY_TREE_HDD      ${LANG_ENGLISH} "HDD"
LangString STR_SUMMARY_TREE_NETWORK  ${LANG_ENGLISH} "Network"
LangString STR_SUMMARY_TREE_PORTS    ${LANG_ENGLISH} "Ports"
LangString STR_SUMMARY_TREE_BRIDGE   ${LANG_ENGLISH} "Bridge"
