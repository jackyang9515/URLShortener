# URLShortener

## Introduction

URLShortener is a distributed database system that is capable of handling data storage requests of URLs. Implemented using Cassandra as its database, Redis as its caching system, Docker as its load balancer and Python as our main application, it stores URLs as pairs, and uses the shortened version as the retrieval key.

## Technical Overview

Below is a graph we made for the overall architecture of the system:

<img src=./img/architecture.png alt="Custom Size 3"/>

Suppose client1 and client2 sends request through the Docker Swarm Load Balancer, it would distribute incoming traffic to the backend URL shortener service running on different nodes. These services act as the main application servers that process requests, and can be scaled horizontally to handle increasing traffic.Since Redis can handle requests much more rapidly than Cassandra, it functions as the caching layer for the system. Cassandra acts as the primary database for persistent storage of the URLs, and there is also a separate monitoring system that tracks the health and performance of all components in the system, used to ensure uptime and detect issues.

## Database

Our core database, the keyspace and the table are implemented using Cassandra. We have 4 hosts, each loaded with Cassandra. Our keyspace’s replication factor is 2, meaning that each piece of data will have two copies in our system. In case one host fails, we can still retrieve the data from the other host. Since we only have 4 hosts in total, we believe that 2 copies would be sufficient for fault tolerance.

## Caching

We use Redis to handle caching. When the system receives a GET request, it would first check if the data exists in Redis. If it does, then the request would never reach Cassandra. For PUT requests, if the data exists in Redis, the old data would get updated first, then Cassadra would also get updated. Below is a graph showing the time difference between 20k GET requests.

<img src=./img/graph1.png alt="Custom Size 3"/>

## Load Balancing

Load balancing is achieved through Docker Swarm's routing mesh and Docker's load balancing features. Incoming requests are distributed evenly across multiple instances of the Flask application and Cassandra nodes.

## Recovery

We have a default recovery among Docker Swarm and Cassandra. If a node for any reason fails, it would get restarted automatically. Cassandra would also replicate data to the newly started host to ensure that it has the most up-to-date data.

## Logging

Recovery logging is implemented by the default Docker logging. We log all other system events ourselves. We have one urlshortner container per VM, and we have a specific directory in each container to store the logged results (GET and PUT requests), and we synchronize all of those logs in each container to each of their corresponding locations in their VM.

## Monitoring

We implement monitoring using a container with Flask, which we call an endpoint. It retrieves the current state of the application system. Here is a sample output from the monitor service:

<img src=./img/monitor.png alt="Custom Size 3"/>

## Data Partition Tolerance

Cassandra handles partition tolerance by replicating data, allowing for tunable consistency levels, and employing mechanisms to reconcile inconsistencies after partitions are resolved.

## Vertical Scalability

We can utilize the start-stack function, which is implemented using docker commands, in our orchestration.sh to add potential functional layers to enhance the system.

## Admin Scalability

New resources can be added with minimal configuration. Docker Swarm and Cassandra handle the orchestration and data distribution automatically.

## Orchestration

Our orchestration shell script serves as the conductor of our system. In addition to starting and stopping our workflows, it is also capable of adding and removing new nodes. It is capable of scaling horizontally. All of its functionalities are listed below:

<img src=./img/orchestration.png alt="Custom Size 3"/>

## Performance

<img src=./img/perf1.png alt="Custom Size 3"/>

The performance of GET and PUT requests are about the same for LoadTest 1 and 2. However, LoadTest2 with cached data is significantly faster since data retrieval from Redis is faster.

<img src=./img/perf2.png alt="Custom Size 3"/>

Above is a diagram showing the LoadTest1 result using 2, 3 and 4 nodes.