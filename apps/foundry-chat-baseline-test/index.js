const http = require('http');
const port = process.env.PORT || 3000;

const server = http.createServer((req, res) => {
  console.log(Request: ${req.method} ${req.url});
  if (req.url === '/healthz') {
    res.writeHead(200, {'Content-Type': 'application/json'});
    res.end(JSON.stringify({status: 'ok'}));
  } else if (req.url === '/') {
    res.writeHead(200, {'Content-Type': 'text/html'});
    res.end('<h1>Test OK</h1>');
  } else {
    res.writeHead(404, {'Content-Type': 'text/html'});
    res.end('<h1>Not Found</h1>');
  }
});

server.listen(port, () => {
  console.log(Server running on port ${port});
});
