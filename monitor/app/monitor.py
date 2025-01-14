from flask import Flask, request
import paramiko
import re

app = Flask(__name__)

def ssh_execute(host, username, password, command):
    """
    Executes an SSH command on a remote host using paramiko and returns the output.
    """
    try:
        # Create an SSH client
        ssh_client = paramiko.SSHClient()
        ssh_client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        
        # Connect to the remote host
        ssh_client.connect(hostname=host, username=username, password=password)
        
        # Execute the command
        stdin, stdout, stderr = ssh_client.exec_command(command)
        
        # Get the output
        output = stdout.read().decode('utf-8')
        error = stderr.read().decode('utf-8')
        
        ssh_client.close()
        return output, error
    except Exception as e:
        return None, str(e)

def get_created_and_status(output):
    # Returns tuple of (created, status)
    split_output = re.split(r'\s{3,}', str(output))
    return split_output[3], split_output[4]

def formatter(node, cass_output, app_output, redis_output, final_output):
    # Takes in cass_output, app_output, redis_output and checks if the service is down, appends results to final_output array
    
    # Cassandra Status
    if "tcp" not in str(cass_output):
        final_output.append("{:<15}{:<10}\t DOWN\n".format("Cassandra", node))
    else:
        created, status = get_created_and_status(cass_output)
        final_output.append("{:<15}{:<10}\t UP \t{:<20}\t{:<20}\n".format("Cassandra", node, created, status))

    # App (URL Shortener) Status
    if "tcp" not in str(app_output):
        final_output.append("{:<15}{:<10}\t DOWN\n".format("URL Shortener", node))
    else:
        created, status = get_created_and_status(app_output)
        final_output.append("{:<15}{:<10}\t UP \t{:<20}\t{:<20}\n".format("URL Shortener", node, created, status))

    # Redis Status
    if "tcp" not in str(redis_output):
        final_output.append("{:<15}{:<10}\t DOWN\n".format("Redis", node))
    else:
        created, status = get_created_and_status(redis_output)
        final_output.append("{:<15}{:<10}\t UP \t{:<20}\t{:<20}\n".format("Redis", node, created, status))

def check_status():
    nodes = []

    with open('nodes') as config_file:
        for line in config_file:
            nodes.append(line.rstrip())

    final_output = ["\nURL Shortener System Status\n\n"]
    username = "student"
    password = "hhhhiotwwg!!"

    for n, node in enumerate(nodes):
        final_output.append("Node {} Status\n".format(n))
        
        # Cassandra Status
        cass_output, _ = ssh_execute(node, username, password, "docker container ls | grep cassandra")
        # App (URL Shortener) Status
        app_output, _ = ssh_execute(node, username, password, "docker container ls | grep urlshortner")
        # Redis Status
        redis_output, _ = ssh_execute(node, username, password, "docker container ls | grep redis:latest")
        
        formatter(node, cass_output, app_output, redis_output, final_output)

    return ''.join(final_output)

@app.route('/', methods=['GET'])
def request_handler():
    return '<meta http-equiv="refresh" content="5"><span style="white-space: pre-line">' + check_status() + '</span>'

@app.route('/', methods=['PUT'])
def request_handler_new_host():
    new_host = request.args.get('host')
    with open('nodes', 'a') as myfile:
        myfile.write(new_host + '\n')
    return 'New node ' + new_host + ' added\n'

@app.route('/', methods=['DELETE'])
def request_handler_host_remove():
    old_host = request.args.get('host')
    with open('nodes', 'r') as f:
        lines = f.readlines()
    with open('nodes', 'w') as f:
        for line in lines:
            if line.strip('\n') != old_host:
                f.write(line)
    return 'Node ' + old_host + ' removed\n'

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=80)
