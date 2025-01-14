CREATE KEYSPACE IF NOT EXISTS urlshortner
WITH replication = {'class': 'SimpleStrategy', 'replication_factor' : 2};
