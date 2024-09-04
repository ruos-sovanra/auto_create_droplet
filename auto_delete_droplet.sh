#!/bin/bash

# Function to prompt the user for droplet name
function get_droplet_name() {
    read -p "Enter the droplet name (default: example-droplet): " USER_DROPLET_NAME
    DROPLET_NAME="${USER_DROPLET_NAME:-example-droplet}"
}

# Function to prompt the user for droplet size
function choose_droplet_size() {
    echo "Choose a droplet size:"
    echo "1) s-1vcpu-512mb-10gb"
    echo "2) s-1vcpu-1gb (default)"
    echo "3) s-1vcpu-2gb"
    read -p "Enter your choice (1-3): " SIZE_CHOICE

    case $SIZE_CHOICE in
        1)
            SIZE="s-1vcpu-512mb-10gb"
            ;;
        3)
            SIZE="s-1vcpu-2gb"
            ;;
        *)
            SIZE="s-1vcpu-1gb"
            ;;
    esac
}

# Function to create the droplet and set up the environment
function create_droplet_and_setup() {
    # Set your DigitalOcean API token here or use an environment variable
    API_TOKEN="${DO_API_TOKEN:-dop_v1_28f5de1ef53facbc63357c7cd1fceda204e010ee82bea86fd62e94cfeb4679d5}"

    # Call the function to get the droplet name
    get_droplet_name

    # Call the function to select droplet size
    choose_droplet_size

    # Set the desired configuration for your droplet
    REGION="nyc3"            # Choose your preferred region, e.g., nyc3, sfo3, etc.
    IMAGE="ubuntu-24-04-x64" # Choose your preferred OS image

    # Read the SSH key from the file
    SSH_KEY=$(cat ~/.ssh/id_rsa.pub)
    SSH_KEY_NAME="my-ssh-key"

    # Check if the SSH key already exists
    KEY_EXISTS=$(curl -s -X GET "https://api.digitalocean.com/v2/account/keys" \
        -H "Authorization: Bearer $API_TOKEN" \
        | jq -r --arg key "$SSH_KEY" '.ssh_keys[] | select(.public_key == $key) | .id')

    if [ "$KEY_EXISTS" != "null" ]; then
        SSH_KEY_ID=$KEY_EXISTS
        echo "SSH Key already exists! ID: $SSH_KEY_ID"
    else
        # Upload the SSH key
        RESPONSE=$(curl -s -X POST "https://api.digitalocean.com/v2/account/keys" \
            -H "Authorization: Bearer $API_TOKEN" \
            -H "Content-Type: application/json" \
            -d '{
                "name": "'"$SSH_KEY_NAME"'",
                "public_key": "'"$SSH_KEY"'"
            }')

        # Extract and print the SSH key ID from the response
        SSH_KEY_ID=$(echo $RESPONSE | jq -r '.ssh_key.id')
        if [ "$SSH_KEY_ID" != "null" ]; then
            echo "SSH Key uploaded successfully! ID: $SSH_KEY_ID"
        else
            echo "Failed to upload SSH key. Response: $RESPONSE"
            exit 1
        fi
    fi

    # Create the droplet with the SSH key
    RESPONSE=$(curl -s -X POST "https://api.digitalocean.com/v2/droplets" \
        -H "Authorization: Bearer $API_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{
            "name":"'"$DROPLET_NAME"'",
            "region":"'"$REGION"'",
            "size":"'"$SIZE"'",
            "image":"'"$IMAGE"'",
            "ssh_keys":["'"$SSH_KEY_ID"'"],
            "backups":false,
            "ipv6":true,
            "monitoring":true,
            "tags":["web"]
        }')

    # Extract and print the droplet ID from the response
    DROPLET_ID=$(echo $RESPONSE | jq -r '.droplet.id')
    if [ "$DROPLET_ID" != "null" ]; then
        echo "Droplet created successfully! ID: $DROPLET_ID"
        # Append droplet details to listdroplet.txt
        echo "Droplet ID: $DROPLET_ID, Name: $DROPLET_NAME, Tags: web" >> listdroplet.txt
    else
        echo "Failed to create droplet. Response: $RESPONSE"
        exit 1
    fi

    # Loop to check for the droplet's IP address
    DROPLET_IP=""
    while [ -z "$DROPLET_IP" ] || [ "$DROPLET_IP" == "null" ]; do
        echo "Waiting for droplet IP address..."
        sleep 10
        DROPLET_IP=$(curl -s -X GET "https://api.digitalocean.com/v2/droplets/$DROPLET_ID" \
            -H "Authorization: Bearer $API_TOKEN" \
            | jq -r '.droplet.networks.v4[0].ip_address')
    done

    echo "Droplet IP address: $DROPLET_IP"

    # Wait for the droplet to become accessible
    echo "Waiting for droplet to become accessible..."
    sleep 30

    # SSH into the server and set up Docker and Nginx
    ssh -o StrictHostKeyChecking=no root@$DROPLET_IP << EOF
sudo apt update
sudo apt install -y apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu focal stable"
sudo apt update
sudo apt install -y docker-ce

# Set up Nginx
sudo apt update
sudo apt install -y nginx
sudo ufw allow 'Nginx HTTP'
sudo ufw enable -y
sudo ufw allow 'Nginx HTTPS'
sudo ufw allow 'OpenSSH'

echo "Docker and Nginx have been set up on the server."
EOF
}

# Call the function to create the droplet and set up the environment
create_droplet_and_setup

