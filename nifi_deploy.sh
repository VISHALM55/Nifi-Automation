#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status

# Function to handle errors
handle_error() {
    echo "Error occurred in script at line: $1"
    exit 1
}
trap 'handle_error $LINENO' ERR

# Function to check if certificate files exist
check_certificate_files() {
    if [ ! -f "truststore.pkcs12" ] || [ ! -f "keystore.pkcs12" ]; then
        echo "Error: Certificate files (truststore.pkcs12 or keystore.pkcs12) not found in the current directory."
        exit 1
    fi
}

# Function to create volumes
create_volume() {
    volume_name=$1
    if ! docker volume create "$volume_name"; then
        echo "Failed to create volume: $volume_name"
        exit 1
    fi
}

# Step 1: Create volumes
create_volume nifi_database_repository
create_volume nifi_flowfile_repository
create_volume nifi_content_repository
create_volume nifi_provenance_repository
create_volume nifi_state
create_volume nifi_logs
create_volume nifi_conf
create_volume certs

echo "Volumes created successfully"

# Function to validate input
validate_input() {
    if [[ -z "$1" ]]; then
        echo "Error: Input cannot be empty."
        exit 1
    fi
}

# Function to validate input for NIFI_WEB_HTTPS_PORT
validate_nifi_web_port() {
    if ! [[ "$1" =~ ^[0-9]+$ ]]; then
        echo "Error: NIFI_WEB_HTTPS_PORT should contain only numbers."
        exit 1
    fi
}

# Function to validate input for NIFI_WEB_PROXY_HOST
validate_nifi_web_host() {
    if ! [[ "$1" =~ ^[[:alnum:]]+$ ]]; then
        echo "Error: NIFI_WEB_PROXY_HOST should contain only alphanumeric characters and numbers."
        exit 1
    fi
}
# Function to validate input for NIFI_WEB_HOST
validate_nifi_localhost() {
    if [[ "$1" != "localhost" && "$1" != "0.0.0.0" ]]; then
        echo "Error: NIFI_WEB_PROXY_HOST should be either 'localhost' or '0.0.0.0'."
        exit 1
    fi
}


# Function to check if container exists and prompt user to delete
check_existing_container() {
    container_name=$1
    if docker ps -a --format '{{.Names}}' | grep -q "^$container_name$"; then
        read -p "Container $container_name already exists. Do you want to delete it? (y/n): " delete_container
        if [[ $delete_container == "y" ]]; then
            docker rm -f $container_name
        else
            echo "Exiting the process."
            exit 1
        fi
    fi
}

# Step 2: Check for existing container
check_existing_container nifi

# Function to run NiFi HTTP container
run_nifi_http_container() {
        # Prompt user for NIFI_WEB_HTTPS_PORT
    read -p "Enter the HTTPS port for NiFi (default is 8443): " nifi_web_http_port
    validate_nifi_web_port "$nifi_web_http_port"
    nifi_web_http_port=${nifi_web_http_port:-8443}

    # Prompt user for NIFI_WEB_PROXY_HOST
    read -p "Enter the NiFi web proxy host (e.g., localhost or 0.0.0.0): " nifi_web_host
    validate_nifi_localhost "$nifi_web_host"

    read -p "SINGLE_USER_CREDENTIALS_USERNAME: " username
    validate_input "$username"
    read -p "SINGLE_USER_CREDENTIALS_PASSWORD: " password
    validate_input "$password"
    docker run --name nifi \
      -p $nifi_web_http_port:$nifi_web_http_port \
      -p 5050:5050 \
      -p 0.0.0.0:5051:5051 \
      -p 5052:5052 \
      -d \
      -v nifi_database_repository:/opt/nifi/nifi-current/database_repository \
      -v nifi_flowfile_repository:/opt/nifi/nifi-current/flowfile_repository \
      -v nifi_content_repository:/opt/nifi/nifi-current/content_repository \
      -v nifi_provenance_repository:/opt/nifi/nifi-current/provenance_repository \
      -v nifi_state:/opt/nifi/nifi-current/state \
      -v nifi_logs:/opt/nifi/nifi-current/logs \
      -v nifi_conf:/opt/nifi/nifi-current/conf \
      -e SINGLE_USER_CREDENTIALS_USERNAME=$username \
      -e SINGLE_USER_CREDENTIALS_PASSWORD=$password \
      apache/nifi:latest
}

# Function to run NiFi HTTPS container
run_nifi_https_container() {
    # Step 3: Build Dockerfile
    cat << EOF > Dockerfile
FROM apache/nifi:latest

USER root

# Set environment variables
ENV NIFI_WEB_HTTPS_PORT=$nifi_web_https_port
ENV NIFI_WEB_PROXY_HOST=$nifi_web_proxy_host
ENV NIFI_SECURITY_USER_AUTHORIZER=single-user-authorizer
ENV NIFI_SECURITY_USER_LOGIN_IDENTITY_PROVIDER=single-user-provider
ENV SINGLE_USER_CREDENTIALS_USERNAME=$username
ENV SINGLE_USER_CREDENTIALS_PASSWORD=$password
ENV INITIAL_ADMIN_IDENTITY=CN=admin,OU=NIFI
ENV AUTH=tls
ENV TRUSTSTORE_PATH=/opt/certs/truststore.pkcs12
ENV TRUSTSTORE_PASSWORD=iphone21
ENV TRUSTSTORE_TYPE=PKCS12
ENV KEYSTORE_PATH=/opt/certs/keystore.pkcs12
ENV KEYSTORE_TYPE=PKCS12
ENV KEYSTORE_PASSWORD=iphone21

# Copy truststore and keystore files to container
COPY truststore.pkcs12 /opt/certs/truststore.pkcs12
COPY keystore.pkcs12 /opt/certs/keystore.pkcs12

RUN chmod +x /opt/certs/truststore.pkcs12
RUN chmod +x /opt/certs/keystore.pkcs12

# Expose NiFi HTTPS port
EXPOSE $nifi_web_https_port

# Start NiFi
CMD ["./opt/nifi/nifi-current/bin/nifi.sh", "start"]
EOF

    echo "NIFI_WEB_HTTPS_PORT=$nifi_web_https_port"
    echo "NIFI_WEB_PROXY_HOST=$nifi_web_proxy_host"
    echo "SINGLE_USER_CREDENTIALS_USERNAME=$username"
    echo "SINGLE_USER_CREDENTIALS_PASSWORD=$password"
    
    # Step 4: Build Docker image
    if ! docker build -t nifi .; then
        echo "Failed to build Docker image."
        exit 1
    fi

    # Step 5: Run Docker container
    if ! docker run --name nifi-v0.1 \
      -p $nifi_web_https_port:$nifi_web_https_port \
      -p 5050:5050 \
      -v nifi_database_repository:/opt/nifi/nifi-current/database_repository \
      -v nifi_flowfile_repository:/opt/nifi/nifi-current/flowfile_repository \
      -v nifi_content_repository:/opt/nifi/nifi-current/content_repository \
      -v nifi_provenance_repository:/opt/nifi/nifi-current/provenance_repository \
      -v nifi_state:/opt/nifi/nifi-current/state \
      -v nifi_logs:/opt/nifi/nifi-current/logs \
      -v nifi_conf:/opt/nifi/nifi-current/conf \
      -d \
      -e SINGLE_USER_CREDENTIALS_USERNAME=$username \
      -e SINGLE_USER_CREDENTIALS_PASSWORD=$password \
      nifi; then
        echo "Failed to run Docker container."
        exit 1
    fi
}
# Prompt user for deploy destination
read -p "Deploy Destination: (localhost) or (server): " deploy_destination

if [[ "$deploy_destination" == "localhost" ]]; then
    echo "Running on localhost, skipping certificate check."

    # Run NiFi container without certificates
    run_nifi_http_container
elif [[ "$deploy_destination" == "server" ]]; then
    # Step 3: Check for certificate files
    check_certificate_files

    # Prompt user for NIFI_WEB_HTTPS_PORT
    read -p "Enter the HTTPS port for NiFi (default is 8443): " nifi_web_https_port
    validate_nifi_web_port "$nifi_web_https_port"
    nifi_web_https_port=${nifi_web_https_port:-8443}

    # Prompt user for NIFI_WEB_PROXY_HOST
    read -p "Enter the NiFi web proxy host (e.g., dataio.paramwallet.com:8443): " nifi_web_proxy_host
    validate_nifi_web_host "$nifi_web_proxy_host"

    read -p "SINGLE_USER_CREDENTIALS_USERNAME: " username
    validate_input "$username"
    read -p "SINGLE_USER_CREDENTIALS_PASSWORD: " password
    validate_input "$password"

    # Run NiFi container with certificates
    run_nifi_https_container
else
    echo "Invalid deploy destination. Exiting..."
    exit 1
fi
