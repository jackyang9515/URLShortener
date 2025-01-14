import logging
from flask import Flask, request, abort, render_template, redirect
from redis_client import Redis_Client
from cassandra_client import Cassandra_Client

# Initialize the Flask application and external clients
application = Flask(__name__)
redis = Redis_Client('redis-primary')
cassandra_server = Cassandra_Client(['10.128.1.106', '10.128.2.106', '10.128.3.106', '10.128.4.106'], 'urlshortner')


@application.route('/', methods=['GET', 'PUT'])
def request_handler_insert():
    """Handles URL insertion requests via GET or PUT."""
    if request.method == 'GET':
        application.logger.error('ERROR 400: BAD REQUEST - GET not allowed')
        abort(400)  # Only PUT requests are valid for insertion

    # Extract parameters from request
    shorturl = request.args.get('short')
    longurl = request.args.get('long')

    # Validate input
    if not shorturl or not longurl or len(request.args) != 2:
        application.logger.error('ERROR 400: BAD REQUEST - Missing or extra parameters')
        abort(400)

    application.logger.info(f'PUT - short: {shorturl}, long: {longurl}')

    # Check if short URL already exists in Redis; insert/update if not
    result = redis.get('urlshortner', shorturl)
    if not result or result != longurl:
        redis.insert('urlshortner', shorturl, longurl)

    cassandra_server.insert(shorturl, longurl)

    # Return confirmation HTML response
    html_response = '''
    <html>
        <body>
            <h1>Got It!</h1>
        </body>
    </html>
    '''
    return html_response


@application.route('/<shorturl>', methods=['GET'])
def request_handler_get(shorturl):
    """Handles URL redirection requests based on the short URL."""
    application.logger.info(f'GET - /{shorturl}')

    # Attempt to retrieve the long URL from Redis first
    longurl = redis.get('urlshortner', shorturl)
    if longurl:
        application.logger.info('REDIS PROCESSED')
        return redirect(longurl, code=307)

    # If not in Redis, retrieve from Cassandra and cache in Redis
    longurl = cassandra_server.get(shorturl)
    if longurl:
        application.logger.info('CASSANDRA PROCESSED')
        redis.insert('urlshortner', shorturl, longurl)
        return redirect(longurl, code=307)

    # Return 404 if the short URL is not found in either database
    application.logger.error('ERROR 404: NOT FOUND')
    abort(404)


if __name__ != '__main__':
    # Configure logging for Gunicorn if running under it
    gunicorn_logger = logging.getLogger('gunicorn.error')
    application.logger.handlers = gunicorn_logger.handlers
    application.logger.setLevel(gunicorn_logger.level)

if __name__ == '__main__':
    # Run the application directly (useful for local testing)
    application.run(host='0.0.0.0', port=80)
