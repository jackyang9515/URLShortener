#!/bin/bash
set -e

STACK_NAME="URLShortenerService"
HOSTS=""
HARRAY=()
host_num=0
MASTER="10.128.1.106"

input="./nodes"
while read -r line
do
    HOSTS+="$line "
    HARRAY+=($line)
    ((host_num+=1))
done < "$input"

echo $HOSTS

start-stack() {
    DOCKER_USERNAME="aoleony2"
    DOCKER_PASSWORD="8jApZZ75E@tNfbB"

    # Login to Docker Hub
    echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin
    cp nodes monitor/app/nodes
    
    cd monitor
    docker build -t aoleony2/monitor:v1 .
    cd ..
    docker build -t aoleony2/urlshortner:v1 .
    docker push aoleony2/urlshortner:v1

    sudo docker stack deploy -c docker-compose.yml $STACK_NAME
}

stop-stack() {
    sudo docker stack rm $STACK_NAME
    # echo "your_password" | sudo -S rm -rf /home/student/csc409_a2/a2group45/volumes/redis/data/appendonlydir
}

start-swarm() {
    echo "Initializing swarm..."
    docker swarm init --advertise-addr ${HARRAY[0]}

    token=$(docker swarm join-token worker | grep -o 'SWMTKN[^ ]*')
    joinWorker="docker swarm join --token $token 10.128.1.106:2377"
    
    echo "Joining swarm on worker nodes..."
    for i in "${HARRAY[@]:1}"
    do
        ssh $i $joinWorker
    done
    # SSH leave and join on the other nodes
}

stop-swarm() {
    for i in "${HARRAY[@]}"
    do
        ssh $i "docker swarm leave --force" || true 
    done
}

start-cass() {
    echo "Starting Cassandra..."
    bash startCluster ${HOSTS} || true
    docker start cassandra-node
    docker exec cassandra-node cqlsh -f /tmp/schema/create_keyspace.cql
    docker exec cassandra-node cqlsh -f /tmp/schema/create_bitly.cql
}

stop-cass() {
    echo "Stopping Cassandra..."
    bash stopCluster ${HOSTS}
    docker stop cassandra-node
}

remove-node() {
    # Check if sufficient arguments are provided
    if [ $# -lt 2 ]; then
        echo "Usage: remove-node <IP> <HOSTNAME>"
        return 1
    fi

    IP=$1
    HOSTNAME=$2

    echo "Leaving swarm for node <${IP}> <${HOSTNAME}..."
    
    # Attempt to leave the swarm on the remote node
    ssh "$IP" "docker swarm leave --force" || true
    
    # Remove the node from the 'nodes' file
    sed -i "/$IP/d" nodes

    # Update the service scale to reflect the new number of hosts
    ((host_num--))
    docker service scale URLShortenerService_web=$host_num

    # Remove the host from the backend
    curl -X DELETE "http://localhost:5000/?host=$IP"

    sleep 10

    NODE_ID=$(docker node ls | awk -v host="$HOSTNAME" '$2 == host {print $1}')
    
    if [ -n "$NODE_ID" ]; then
        docker node rm "$NODE_ID"
        echo "Node $HOSTNAME (ID: $NODE_ID) removed from swarm."
    else
        echo "Node with hostname $HOSTNAME not found in swarm manager."
    fi
    ssh student@$IP "docker exec -it cassandra-node nodetool decommission; docker stop cassandra-node; docker rm cassandra-node;"
    remove-cass $IP
    echo "Cassandra node on host ${HOSTNAME} is removed\n"
}

add-node() {
    # Check if sufficient arguments are provided
    if [ $# -lt 1 ]; then
        echo "Usage: add-node <IP>"
        return 1
    fi

    IP=$1
    
    workerJoin=`docker swarm join-token worker | grep token`
    
    if grep -Fxq "$IP" nodes; then
        echo "Node already exists in swarm"
        return 1
    fi

    echo "Adding node $IP to Swarm..."
    ssh $IP "$workerJoin"
    if [ $? -ne 0 ]; then
        echo "Failed to add node $IP to Swarm. Exiting."
        return 1
    fi

    # Add node to `nodes` file
    echo $IP >> nodes    

    echo "Scaling URL Shortener Service"
    ((host_num++))
    docker service scale URLShortenerService_web=$host_num
    curl -X PUT "http://localhost:5000/?host=$IP"

    echo "adding node ${IP} to Cassandra Cluster..."
    add-cass $IP
}

add-cass() {
    NEW_NODE=$1
    HOST_ID=$(docker exec -it cassandra-node nodetool status | grep "$1" | awk '{print $7}')

    if [ -n "$HOST_ID" ]; then
        echo "Node with IP $NEW_NODE is already part of the cluster with Host ID $HOST_ID."
        return 0
    fi

    COMMAND="docker run --name cassandra-node -d \
            -v /home/student/repo_a2group77/volumes/cassandra/data:/var/lib/cassandra \
            -v /home/student/repo_a2group77/volumes/cassandra/target:/tmp/schema \
            -e CASSANDRA_BROADCAST_ADDRESS=$NEW_NODE \
            -p 7000:7000 \
            -p 9042:9042 \
            -e CASSANDRA_SEEDS=$MASTER cassandra"

    ssh student@$NEW_NODE "$COMMAND"

    # Wait for the node to initialize
    echo "Waiting for Cassandra to initialize on $NEW_NODE..."
    sleep 30
    docker exec -it cassandra-node nodetool status

    echo "Verifying if the node $NEW_NODE has joined the cluster..."
    NEW_HOST_ID=$(docker exec -it cassandra-node nodetool status | grep "$NEW_NODE" | awk '{print $7}')
    if [ -z "$NEW_HOST_ID" ]; then
        echo "Failed to add $NEW_NODE to the cluster. Check the Cassandra logs on the new node for details."
        return 1
    fi

    echo "Node $NEW_NODE successfully added to the Cassandra cluster with Host ID $NEW_HOST_ID."
    return 0
}

remove-cass() {
    # Find the Host ID for the specified IP
    HOST_ID=$(docker exec -it cassandra-node nodetool status | grep "$1" | awk '{print $7}')

    if [ -z "$HOST_ID" ]; then
        echo "Node with IP $1 not found in cluster."
        exit 1
    fi

    echo "Node with IP $1 has Host ID $HOST_ID."

    # Remove the node
    echo "Removing the node from the cluster..."
    docker exec -it cassandra-node nodetool removenode $HOST_ID

    if [ $? -eq 0 ]; then
        echo "Node $1 with Host ID $HOST_ID has been removed from the cluster."
    else
        echo "Failed to remove the node. Check logs for details."
        exit 1
    fi
}

case "$1" in
    start)    start-cass; start-swarm; start-stack;;
    stop)     stop-stack; stop-cass; stop-swarm;;
    start-cass) start-cass;;
    stop-cass) stop-cass;;
    start-swarm) start-swarm;;
    stop-swarm) stop-swarm;;
    start-stack) start-stack;;
    stop-stack) stop-stack;;
    add-node)    add-node "${@:2}";;
    remove-node) remove-node "${@:2}";;
esac