; =============================================================================
; english.nsh — Interface strings in English
; =============================================================================
; Used by: stage2/installer/k8s-lab.nsi
; Language: English (LangId 1033)
; =============================================================================

; --- General ---
LangString STR_WELCOME_TITLE     ${LANG_ENGLISH} "Kubernetes Cluster Lab"
LangString STR_WELCOME_TEXT      ${LANG_ENGLISH} "This wizard will set up a local Kubernetes cluster on your computer.$\n$\nThe cluster will include:$\n  • 1 control-plane node (master)$\n  • One or more worker nodes$\n$\nRequirements: VirtualBox 7.x and Vagrant 2.4+.$\n$\nClick Next to begin."

LangString STR_LICENSE_TITLE     ${LANG_ENGLISH} "License Agreement"
LangString STR_LICENSE_TEXT      ${LANG_ENGLISH} "This project is distributed under the MIT License. Free to use, including for educational purposes."

; --- Dependency checks ---
LangString STR_DEPS_TITLE        ${LANG_ENGLISH} "Checking Requirements"
LangString STR_DEPS_SUBTITLE     ${LANG_ENGLISH} "Making sure all prerequisites are installed"
LangString STR_DEPS_VAGRANT      ${LANG_ENGLISH} "Vagrant"
LangString STR_DEPS_VBOX         ${LANG_ENGLISH} "VirtualBox"
LangString STR_DEPS_OK           ${LANG_ENGLISH} "✓ found"
LangString STR_DEPS_MISSING      ${LANG_ENGLISH} "✗ not found"
LangString STR_DEPS_WARN_VAGRANT ${LANG_ENGLISH} "Vagrant not found!$\n$\nPlease download and install it from:$\nhttps://developer.hashicorp.com/vagrant/downloads$\n$\nThen re-run this installer."
LangString STR_DEPS_WARN_VBOX    ${LANG_ENGLISH} "VirtualBox not found!$\n$\nPlease download and install it from:$\nhttps://www.virtualbox.org/wiki/Downloads$\n$\nThen re-run this installer."
LangString STR_DEPS_HINT         ${LANG_ENGLISH} "If anything is missing — install it and re-run this wizard."

; --- Cluster configuration ---
LangString STR_CONFIG_TITLE      ${LANG_ENGLISH} "Cluster Configuration"
LangString STR_CONFIG_SUBTITLE   ${LANG_ENGLISH} "Set cluster parameters (or leave defaults)"
LangString STR_CONFIG_PREFIX     ${LANG_ENGLISH} "VM name prefix (e.g.: mylab-k8s)"
LangString STR_CONFIG_WORKERS    ${LANG_ENGLISH} "Number of worker nodes"
LangString STR_CONFIG_CPU        ${LANG_ENGLISH} "CPUs per VM"
LangString STR_CONFIG_RAM        ${LANG_ENGLISH} "RAM per VM (MB)"
LangString STR_CONFIG_SUBNET     ${LANG_ENGLISH} "Subnet (first 3 octets, e.g.: 192.168.56)"
LangString STR_CONFIG_TIP        ${LANG_ENGLISH} "Tip: leave defaults if you are not sure what to change"

; --- Install directory ---
LangString STR_DIR_TITLE         ${LANG_ENGLISH} "Project Folder"
LangString STR_DIR_SUBTITLE      ${LANG_ENGLISH} "Where should the cluster files be placed?"
LangString STR_DIR_LABEL         ${LANG_ENGLISH} "Folder:"
LangString STR_DIR_BROWSE        ${LANG_ENGLISH} "Browse..."

; --- Summary ---
LangString STR_SUMMARY_TITLE     ${LANG_ENGLISH} "Configuration Summary"
LangString STR_SUMMARY_SUBTITLE  ${LANG_ENGLISH} "Review your settings before launching"
LangString STR_SUMMARY_HEADER    ${LANG_ENGLISH} "Cluster to be created:"
LangString STR_SUMMARY_PREFIX    ${LANG_ENGLISH} "VM prefix:"
LangString STR_SUMMARY_WORKERS   ${LANG_ENGLISH} "Worker nodes:"
LangString STR_SUMMARY_CPU       ${LANG_ENGLISH} "CPUs per VM:"
LangString STR_SUMMARY_RAM       ${LANG_ENGLISH} "RAM per VM:"
LangString STR_SUMMARY_SUBNET    ${LANG_ENGLISH} "Subnet:"
LangString STR_SUMMARY_DIR       ${LANG_ENGLISH} "Project folder:"
LangString STR_SUMMARY_NOTE      ${LANG_ENGLISH} "Installation will take 15–30 minutes (Ubuntu image download + Kubernetes setup)."

; --- Installation ---
LangString STR_INSTALL_TITLE     ${LANG_ENGLISH} "Starting Cluster"
LangString STR_INSTALL_SUBTITLE  ${LANG_ENGLISH} "Please wait while the cluster is being set up..."
LangString STR_INSTALL_COPY      ${LANG_ENGLISH} "Copying files..."
LangString STR_INSTALL_CONFIG    ${LANG_ENGLISH} "Creating .env configuration..."
LangString STR_INSTALL_KEYS      ${LANG_ENGLISH} "Generating SSH keys..."
LangString STR_INSTALL_VAGRANT   ${LANG_ENGLISH} "Running vagrant up (this will take 15–30 minutes)..."
LangString STR_INSTALL_DONE      ${LANG_ENGLISH} "Cluster is ready!"

; --- Finish ---
LangString STR_FINISH_TITLE      ${LANG_ENGLISH} "Installation Complete"
LangString STR_FINISH_TEXT       ${LANG_ENGLISH} "Your Kubernetes cluster is up and running!$\n$\nDashboard is available at:$\nhttps://localhost:30443$\n$\nLogin token is in dashboard-token.txt$\nin your project folder."
LangString STR_FINISH_OPEN       ${LANG_ENGLISH} "Open project folder"
LangString STR_FINISH_DOCS       ${LANG_ENGLISH} "Open documentation"

; --- Errors ---
LangString STR_ERR_VAGRANT_FAIL  ${LANG_ENGLISH} "vagrant up failed.$\nCheck the logs in the project folder.$\nFor diagnostics: vagrant status"
LangString STR_ERR_NO_ADMIN      ${LANG_ENGLISH} "Administrator privileges required.$\nPlease run the installer as Administrator."
