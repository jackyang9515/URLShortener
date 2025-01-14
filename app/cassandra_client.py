from cassandra.cluster import Cluster

insert_statement = """
UPDATE bitly SET longurl=%s WHERE shorturl=%s;
"""
select_statement = """
SELECT longurl FROM bitly WHERE shorturl=%s;
"""


class Cassandra_Client:
  def __init__(self, hosts, keyspace):
    self._hosts = hosts
    self._keyspace = keyspace
    self.connect(hosts, keyspace)
  
  def connect(self, hosts, keyspace):
    cluster = Cluster(hosts, port=9042)
    self._session = cluster.connect(keyspace)

  def insert(self, short_resource, long_resource):
    if self._session == None:
      self.connect(self._hosts, self._keyspace)
    self._session.execute(insert_statement, (long_resource, short_resource))

  def get(self, short_resource):
    if self._session == None:
      self.connect(self._hosts, self._keyspace)
    rows = self._session.execute(select_statement, (short_resource, ))
    if rows:
      return rows[0].long_resource
    return None
